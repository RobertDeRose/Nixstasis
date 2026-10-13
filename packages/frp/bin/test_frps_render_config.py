#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise the frps config renderer against the real Compose template."""

import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
RENDERER = REPO_ROOT / "packages/frp/bin/frps-render-config.sh"
TEMPLATE = REPO_ROOT / "deploy/compose/frps/frps.toml"

BASE_ENV = {
    "FRPS_DASHBOARD_USER": "operator",
    "FRPS_DASHBOARD_PASSWORD": "hunter2",
    "BASE_DOMAIN": "devices.example",
    "FRPS_BIND_PORT": "7000",
    "FRPS_DASHBOARD_PORT": "7500",
    "FRPS_TCPMUX_PORT": "2022",
    "FRPS_HTTP_PORT": "8080",
}


def render(template: Path, env: dict[str, str]) -> tuple[subprocess.CompletedProcess, str | None]:
    """Run the renderer and return the process result and the rendered text, if any."""
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "frps.toml"
        result = subprocess.run(
            ["sh", str(RENDERER), str(template), str(output)],
            env={"PATH": os.environ["PATH"], **env},
            capture_output=True, text=True, check=False, timeout=30,
        )
        rendered = output.read_text() if output.exists() else None
    return result, rendered


class RenderConfigTest(unittest.TestCase):
    """The renderer must produce valid TOML with the exact operator values."""

    def test_real_template_round_trips_awkward_values(self):
        """Quotes, backslashes, slashes, and ampersands survive sed and TOML."""
        awkward = {
            "FRPS_DASHBOARD_USER": 'ad"min\\ops',
            "FRPS_DASHBOARD_PASSWORD": 'p/a&ss\\"word" \\\\ end',
            "BASE_DOMAIN": "dev&ices.example",
        }
        result, rendered = render(TEMPLATE, {**BASE_ENV, **awkward})
        self.assertEqual(result.returncode, 0, result.stderr)
        config = tomllib.loads(rendered)
        self.assertEqual(config["bindPort"], 7000)
        self.assertEqual(config["webServer"]["port"], 7500)
        self.assertEqual(config["webServer"]["user"], awkward["FRPS_DASHBOARD_USER"])
        self.assertEqual(config["webServer"]["password"], awkward["FRPS_DASHBOARD_PASSWORD"])
        self.assertEqual(config["tcpmuxHTTPConnectPort"], 2022)
        self.assertEqual(config["vhostHTTPPort"], 8080)
        self.assertEqual(config["subDomainHost"], awkward["BASE_DOMAIN"])
        self.assertEqual(config["httpPlugins"][0]["name"], "nixstasis-device-authorization")

    def test_values_may_contain_placeholder_shaped_text(self):
        """Only the template is checked for unfilled variables, never the values."""
        password = "pass__2024__word"
        result, rendered = render(TEMPLATE, {**BASE_ENV, "FRPS_DASHBOARD_PASSWORD": password})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tomllib.loads(rendered)["webServer"]["password"], password)

    def test_rejects_unknown_placeholders_including_digits(self):
        """A placeholder the renderer does not fill fails instead of leaking."""
        for placeholder in ["__FRPS_AUTH_TOKEN__", "__FRPS_DASHBOARD_USER_2__"]:
            with self.subTest(placeholder=placeholder), tempfile.TemporaryDirectory() as tmp:
                template = Path(tmp) / "frps.toml"
                template.write_text(TEMPLATE.read_text() + f'\nauth.extra = "{placeholder}"\n')
                result, _ = render(template, BASE_ENV)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("does not fill", result.stderr)
                self.assertIn(placeholder, result.stderr)

    def test_rejects_values_holding_a_template_variable(self):
        """A value the sed chain would rewrite fails without echoing the value."""
        password = "secret__BASE_DOMAIN__suffix"
        result, _ = render(TEMPLATE, {**BASE_ENV, "FRPS_DASHBOARD_PASSWORD": password})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FRPS_DASHBOARD_PASSWORD must not contain the template variable __BASE_DOMAIN__", result.stderr)
        self.assertNotIn(password, result.stderr)

    def test_rejects_bad_ports_missing_values_and_control_characters(self):
        """Input validation matches what the Compose service used to enforce."""
        cases = {
            "non-numeric port": ({**BASE_ENV, "FRPS_HTTP_PORT": "80a"}, "FRPS_HTTP_PORT must be numeric"),
            "empty port": ({**BASE_ENV, "FRPS_BIND_PORT": ""}, "FRPS_BIND_PORT must be numeric"),
            "missing domain": ({k: v for k, v in BASE_ENV.items() if k != "BASE_DOMAIN"}, "BASE_DOMAIN is required"),
            "newline in password": ({**BASE_ENV, "FRPS_DASHBOARD_PASSWORD": "a\nb"}, "must not contain a newline"),
            "carriage return in user": (
                {**BASE_ENV, "FRPS_DASHBOARD_USER": "a\rb"},
                "FRPS_DASHBOARD_USER must not contain control characters",
            ),
        }
        for name, (env, message) in cases.items():
            with self.subTest(case=name):
                result, _ = render(TEMPLATE, env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
