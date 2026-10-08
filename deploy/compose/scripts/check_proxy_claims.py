#!/usr/bin/env python3
"""Exercise the production/laptop claim boundary with Caddy and real signed JWTs."""

import argparse
import base64
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[3]
JWT_KEY = "proxy-test-jwt-signing-secret-0123456789abcdef"
PROXY_TOKEN = "proxy-test-proxy-secret-0123456789abcdef"
DEVICE_ID = "11111111-1111-4111-8111-111111111111"
ENV = {
    "BASE_DOMAIN": "proxy.test",
    "PORT": "4000",
    "ACME_EMAIL": "proxy@example.test",
    "CLIENT_ID": "00000000-0000-0000-0000-000000000001",
    "CLIENT_SECRET": "proxy-test-client-secret",
    "TENANT_ID": "00000000-0000-0000-0000-000000000002",
    "JWT_KEY": JWT_KEY,
    "NIXSTASIS_PROXY_AUTH_TOKEN": PROXY_TOKEN,
    "AUTHORIZED_ROLES": "nixstasis/viewer nixstasis/operator nixstasis/admin",
    "AUTHORIZED_GROUPS": "viewer operator admin",
    "NIXSTASIS_VIEWER_GROUPS": "viewer",
    "NIXSTASIS_OPERATOR_GROUPS": "operator",
    "NIXSTASIS_ADMIN_GROUPS": "admin",
    "FRPS_HTTP_PORT": "8080",
    "FRPS_DASHBOARD_PORT": "7500",
}
FORGED_HEADERS = {
    "X-Token-Subject": "attacker",
    "X-Token-User-Name": "Attacker",
    "X-Token-User-Email": "attacker@example.test",
    "X-Token-User-Roles": "nixstasis/admin",
    "X-Token-Device-Id": "22222222-2222-4222-8222-222222222222",
    "X-Token-Device-Ids": "33333333-3333-4333-8333-333333333333",
    "X-Token-Allowed-Device-Ids": "44444444-4444-4444-8444-444444444444",
    "X-Token-Future-Claim": "untrusted",
    "X-Nixstasis-Proxy-Token": "attacker-proxy-token",
}


class EchoHandler(BaseHTTPRequestHandler):
    """Expose the headers, path, and body that actually reach the test upstream."""

    def do_GET(self):
        """Echo a GET or POST as JSON so tests can inspect Caddy's forwarding.

        The do_POST alias uses this same handler; no application authentication
        runs here, because the assertions exercise the proxy boundary itself.
        """
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        payload = json.dumps({
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "path": self.path,
            "body": body.decode(),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_POST = do_GET

    def log_message(self, *_args):
        """Suppress default HTTP access logs to keep assertion failures readable."""
        pass


def signed_token():
    """Create a short-lived HS512 viewer JWT using the isolated test signing key.

    Includes a fixed device ID so the same token exercises both unrestricted
    forwarding and optional device-scope injection. This is not a production key.
    """
    def encode(value):
        """Return the unpadded base64url bytes required by JWT segments."""
        return base64.urlsafe_b64encode(value).rstrip(b"=")

    now = int(time.time())
    claims = {
        "sub": "trusted-viewer",
        "name": "Trusted Viewer",
        "email": "viewer@example.test",
        "roles": ["nixstasis/viewer"],
        "device_ids": [DEVICE_ID],
        "iat": now,
        "exp": now + 300,
    }
    message = b".".join(encode(json.dumps(value).encode()) for value in [
        {"alg": "HS512", "typ": "JWT"}, claims,
    ])
    signature = hmac.new(JWT_KEY.encode(), message, hashlib.sha512).digest()
    return (message + b"." + encode(signature)).decode()


def local_config(caddy, filename, backend_port, listen_port, scoped):
    """Adapt a deployment Caddyfile into a loopback-only integration-test config.

    Preserve its application handlers and authorization policies while replacing
    listeners and upstreams and removing unused TLS/OIDC services. When scoped,
    inject the signed token's device_ids claim using the documented option.
    Return the JSON-compatible config; failed adaptation or host selection raises.
    """
    adapted = subprocess.run(
        [caddy, "adapt", "--adapter", "caddyfile", "--config", str(filename)],
        env={**os.environ, **ENV}, capture_output=True, text=True, check=True,
    )
    config = json.loads(adapted.stdout)
    # Keep the adapted Nixstasis handlers and policy intact. Only replace external
    # listeners/upstreams and remove unused TLS/OIDC services for this local test.
    routes = [route for server in config["apps"]["http"]["servers"].values()
              for route in server["routes"]
              if any("nixstasis.proxy.test" in match.get("host", [])
                     for match in route.get("match", []))]
    if len(routes) != 1:
        raise AssertionError("Expected exactly one Nixstasis host route")
    config["admin"] = {"disabled": True}
    config["apps"].pop("tls", None)
    config["apps"]["http"]["servers"] = {"test": {
        "listen": [f"127.0.0.1:{listen_port}"],
        "automatic_https": {"disable": True},
        "routes": routes,
    }}
    policies = config["apps"]["security"]["config"]["authorization_policies"]
    config["apps"]["security"]["config"] = {"authorization_policies": policies}
    if scoped:
        # Exercise the documented optional deployment scope injection as well.
        for policy in policies:
            policy.setdefault("header_injection_configs", []).append({
                "header": "X-Token-Device-Ids", "field": "device_ids",
            })

    def redirect_upstreams(value):
        """Recursively point every reverse proxy at the local echo backend.

        Mutate only upstream addresses, leaving handler order and policy intact.
        """
        if isinstance(value, dict):
            if value.get("handler") == "reverse_proxy":
                value["upstreams"] = [{"dial": f"127.0.0.1:{backend_port}"}]
            for child in value.values():
                redirect_upstreams(child)
        elif isinstance(value, list):
            for child in value:
                redirect_upstreams(child)

    redirect_upstreams(routes)
    return config


class ProxyClaimsTest(unittest.TestCase):
    """Verify deployed claim sanitization with real Caddy and signed viewer JWTs."""

    caddy = "caddy"

    def check_config(self, name):
        """Check one Caddyfile with and without optional device-scope injection.

        Start an isolated echo backend and stop its serving thread even if a
        proxy assertion fails. Each scope mode is reported as a separate subtest.
        """
        with ThreadingHTTPServer(("127.0.0.1", 0), EchoHandler) as backend:
            thread = threading.Thread(target=backend.serve_forever, daemon=True)
            thread.start()
            try:
                for scoped in [False, True]:
                    with self.subTest(config=name, scoped=scoped):
                        self.check_proxy(name, backend.server_port, scoped)
            finally:
                backend.shutdown()
                thread.join()

    def check_proxy(self, name, backend_port, scoped):
        """Run one adapted Caddy instance and exercise its trusted-claim boundary.

        Use temporary config/data directories and a free local port. Fail with
        captured logs if startup exits or times out, and always reap the process.
        """
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        config = local_config(self.caddy, ROOT / "deploy/compose/caddy" / name,
                              backend_port, port, scoped)
        with tempfile.TemporaryDirectory(prefix="nixstasis-proxy-claims-") as tmp:
            config_path = Path(tmp) / "caddy.json"
            config_path.write_text(json.dumps(config))
            with (Path(tmp) / "caddy.log").open("w+") as log:
                process = subprocess.Popen(
                    [self.caddy, "run", "--config", str(config_path)],
                    env={**os.environ, "XDG_DATA_HOME": tmp, "XDG_CONFIG_HOME": tmp},
                    stdout=log, stderr=log,
                )
                try:
                    deadline = time.monotonic() + 15
                    while True:
                        if process.poll() is not None or time.monotonic() > deadline:
                            log.seek(0)
                            self.fail(f"Caddy failed to start: {log.read()}")
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                break
                        except OSError:
                            time.sleep(0.05)
                    self.exercise_requests(port, scoped)
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()

    def request(self, port, method, path, authenticated=False):
        """Send forged claim headers and return the proxy's status and body bytes.

        authenticated adds a genuine signed viewer token alongside the forged
        headers so tests can distinguish trusted claims from client input. Use
        the fixed runtime body and always close the local HTTP connection.
        """
        headers = dict(FORGED_HEADERS)
        headers["Host"] = "nixstasis.proxy.test"
        if authenticated:
            headers["Authorization"] = f"Bearer {signed_token()}"
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.request(method, path, body="runtime-body", headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def exercise_requests(self, port, scoped):
        """Assert that runtime routes strip claims and operator routes rebuild them.

        Runtime paths and bodies must survive proxying with only the proxy-owned
        credential. Operator routes must forward the signed viewer identity, add
        device scope only when configured, and reject requests without a token.
        """
        for method, path in [
            ("POST", "/api/v1/devices/register"),
            ("POST", "/api/v1/devices/device-a/heartbeat?api_key=device-credential"),
            ("POST", "/api/v1/devices/device-a/command_results?api_key=device-credential"),
            ("GET", "/api/v1/devices/device-a/command_payloads/ref-a?api_key=device-credential"),
        ]:
            status, body = self.request(port, method, path)
            self.assertEqual(status, 200, body)
            result = json.loads(body)
            self.assertEqual(result["path"], path)
            self.assertEqual(result["body"], "runtime-body")
            self.assertEqual(result["headers"]["x-nixstasis-proxy-token"], PROXY_TOKEN)
            self.assertFalse(any(k.startswith("x-token-") for k in result["headers"]), result)

        for path in ["/reports", "/api/json/devices"]:
            status, body = self.request(port, "GET", path, authenticated=True)
            self.assertEqual(status, 200, body)
            claims = {k: v for k, v in json.loads(body)["headers"].items()
                      if k.startswith("x-token-")}
            expected = {
                "x-token-subject": "trusted-viewer",
                "x-token-user-name": "Trusted Viewer",
                "x-token-user-email": "viewer@example.test",
                "x-token-user-roles": "nixstasis/viewer",
            }
            if scoped:
                expected["x-token-device-ids"] = DEVICE_ID
            self.assertEqual(claims, expected)
            self.assertEqual(json.loads(body)["headers"]["x-nixstasis-proxy-token"], PROXY_TOKEN)
            status, _body = self.request(port, "GET", path)
            self.assertIn(status, [302, 303, 401, 403])

    def test_production(self):
        """Verify the production Caddyfile's scoped and unrestricted claim boundary."""
        self.check_config("Caddyfile")

    def test_laptop(self):
        """Verify the laptop Caddyfile uses the same trusted-claim boundary."""
        self.check_config("Caddyfile.laptop")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--caddy", default=os.environ.get("CADDY_BIN", "caddy"),
                        help="Caddy binary built with the pinned security plugin")
    args = parser.parse_args()
    ProxyClaimsTest.caddy = args.caddy
    unittest.main(argv=[__file__], verbosity=2)
