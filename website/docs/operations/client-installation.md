# Client Installation

How to install the `nixstasis` agent on a device and point it at your server. What the agent does once it is running
is covered in [Client CLI](../modules/client-cli.md).

## Choose an install method

Every method installs the `nixstasis` CLI and a matching `frpc` binary, so devices need no separate FRP package. The
browser terminal also needs an OpenSSH server and `sudo` on the device. The `.deb` and `.rpm` packages declare both as
dependencies; with the `.run` installer, install them yourself first. Pick the one that fits how the device is managed:

| Device                               | Use                                   |
|--------------------------------------|---------------------------------------|
| Debian, Ubuntu, and similar          | The `.deb` package.                   |
| Fedora, RHEL, and similar            | The `.rpm` package.                   |
| Other Linux with systemd             | The self-extracting `.run` installer. |
| Managed with Nix, or for development | The Nix flake package.                |

### deb and rpm packages

The packages install:

- `nixstasis` at `/usr/bin/nixstasis`;
- `frpc` at `/usr/libexec/nixstasis/frpc`;
- templates under `/usr/share/nixstasis/`.

If the device has no `/etc/nixstasis/config.yaml` yet, the package creates one from
`/usr/share/nixstasis/config.example.yaml`. An existing config is left alone.

After installing, the package enables the registration and polling services. If systemd is running, it starts them
straight away.

### Self-extracting `.run` installer

The installer does not install dependencies. Before running it, install `sudo` and an OpenSSH server, and make sure
`sshd` is running, so the installer can validate and reload it with the Nixstasis SSH configuration.

Run it with `sh`, because downloads from GitHub Releases lose their executable bit:

```sh
sudo sh nixstasis-<version>-linux-<arch>.run
```

It installs the same files as the packages: `/usr/bin/nixstasis`, `/usr/libexec/nixstasis/frpc`,
`/usr/share/nixstasis/*`, the systemd unit files, and `/etc/nixstasis/config.yaml` on a first install.

On an upgrade, it replaces the binaries, the unit files, and the FRP template at `/usr/share/nixstasis/frpc.toml`. It
keeps your existing `/etc/nixstasis/config.yaml` unless you use the force-config option described in the client
package README.

To look inside an installer without installing anything:

```sh
sh nixstasis-<version>-linux-<arch>.run --noexec --target /tmp/nixstasis-installer
```

### Nix flake package

Build the client for the current system:

```sh
nix build .#client
```

Or for a specific Linux system:

```sh
nix build .#packages.x86_64-linux.client
nix build .#packages.aarch64-linux.client
```

The package puts `nixstasis` at `$out/bin/nixstasis`, links `frpc` at `$out/libexec/nixstasis/frpc`, and installs
templates under `$out/share/nixstasis/`. The `nixstasis` wrapper points its default `frpc` paths into the Nix store.
The build uses Go's standard JSON v2 packages and vendors Go modules with a fixed-output hash.

Unlike the other methods, the flake package does not touch `/etc`, create `/etc/nixstasis/config.yaml`, or install
systemd units. Manage the config and services with NixOS, Home Manager, or your own deployment tooling.

## Point the client at the server

Set these in `/etc/nixstasis/config.yaml`, or with the matching environment variable:

- **`api.url`** (`NIXSTASIS_API_URL`): the server's HTTPS address, such as `https://nixstasis.<base-domain>`. The default
  is `https://localhost:4000`. It cannot include a username or password, a query string, or a fragment, and an invalid
  URL stops registration before any request is sent.
- **`api.allow_loopback_http`** (`NIXSTASIS_API_ALLOW_LOOPBACK_HTTP`): `false` by default. Turn it on only to test
  against a local HTTP mock. It allows plain HTTP to `localhost` (connected to as `127.0.0.1`) or a loopback IP, and
  skips any configured proxy. It never allows plain HTTP to a LAN or Compose address.
- **`frp.server_addr`** (`NIXSTASIS_FRP_SERVER_ADDR`): the FRPS host that remote access tunnels connect to, usually
  `nixstasis.<base-domain>`. The server never sends it, so set it on every device; the default is
  `nixstasis.example.com`. `frp.server_port` defaults to `7000`, matching the Compose `FRPS_BIND_PORT`.
- **`identity.interface`** (`NIXSTASIS_IDENTITY_INTERFACE`): the network interface whose MAC identifies the device.
  Leave it empty to use the interface that routes to the server. Set it when that interface has no MAC, for example
  when the route to the server goes through a VPN tunnel. A named interface that is missing, or has no MAC, stops the
  client with an error.

The client always checks the server's certificate and hostname. If your server uses a private CA, either add its
public certificate to the device's OS trust store, or point Go's `SSL_CERT_FILE` at a PEM bundle. The packaged systemd
services use the OS trust store, so either install the certificate there or set the variable in a unit override.

The client never follows redirects, not even to the same host, so it can never send its registration details or
credentials somewhere you did not configure. Set `api.url` to the final address.
