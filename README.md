# Welcome to Nixstasis

This project is built using the following tools:

* [`Python 3.13+`](https://docs.python.org/3.13/)
* [`uv`](https://docs.astral.sh/uv/getting-started/installation/): Project and dependency management
* [`Reflex`](https://reflex.dev/open-source/): Front-end and Back-end development in pure Python
* [`FRP`](https://gofrp.org/en/): Fast Reverse Proxy, for NAT punching port forwarding
* [`Caddy`](http://caddyserver.com): Automatic on-demand TLS certificates using Let's Encrypt
* [`AuthCrunch`](https://authcrunch.com): Authorization using Azure, with support for many other OIDC providers

## Overview

<!-- ```mermaid GitHub still doesn't support ELK layout
---
config:
  layout: elk
---
flowchart TB
 subgraph Edge["<b>Remote Access</b>"]
        User["FS Agent"]
        Browser["Browser"]
        Shell["Terminal"]
        AuthCrunch["Microsoft Entra ID"]
        Caddy["Caddy + AuthCrunch"]
  end
 subgraph Server["<b>Server Infrastructure</b>"]
        UI["Nixstasis UI"]
        API["Nixstasis API"]
        DB[("Database")]
        Alembic["Alembic Migrations"]
        FRPS["FRPS Server"]
  end
 subgraph Device["<b>AlarmBox</b>"]
        Client["Nixstasis Client"]
        WebUI["Cockpit"]
        SSH["SSH"]
        FRPC["FRP Client"]
  end
    User ==> Browser & Shell
    Browser == "|1. Authentication|" ==> AuthCrunch
    AuthCrunch == "|2. Authorize|" ==> Caddy
    Caddy == |HTTPS/WSS| ==> UI
    Caddy == |Proxy| ==> FRPS
    Shell == |SSH Access| ==> FRPS
    UI <== State/Data ==> API
    API <== Queries ==> DB
    Alembic == Migrations ==> DB
    Client == |Events/Data| ==> API
    FRPC <== Secure Tunnel ==> FRPS
    Client ==> FRPC
    WebUI ==> FRPC
    SSH ==> FRPC
    FRPS == |Web UI| ==> WebUI
    FRPS == |Terminal| ==> SSH

    style User fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Browser fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Shell fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style AuthCrunch fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style Caddy fill:#B3E5FC,stroke:#01579B,stroke-width:3px,color:#000
    style UI fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style API fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style DB fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style Alembic fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style FRPS fill:#C8E6C9,stroke:#1B5E20,stroke-width:3px,color:#000
    style Client fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style WebUI fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style SSH fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style FRPC fill:#E1BEE7,stroke:#4A148C,stroke-width:3px,color:#000
    style Edge fill:#FFE4E1,stroke:#8B0000,stroke-width:4px,color:#000
    style Server fill:#E0F2F7,stroke:#004D7A,stroke-width:4px,color:#000
    style Device fill:#F3E5F5,stroke:#4A148C,stroke-width:4px,color:#000
``` -->

## Reflex Project Structure

This project has the following directory structure:

```bash
├── README.md
├── assets
├── rxconfig.py
└── nixstasis
    ├── __init__.py
    ├── backend
    │   ├── __init__.py
    │   └── . . .
    ├── components
    │   ├── __init__.py
    │   └── . . .
    ├── pages
    │   ├── __init__.py
    │   └── . . .
    ├── models
    │   │   ├── __init__.py
    │   └── . . .
    ├── states
    │   ├── __init__.py
    │   └── . . .
    ├── styles.py
    ├── templates
    │   ├── __init__.py
    │   └── . . .
    └── nixstasis.py
```

See [Reflex's Project Structure docs](https://reflex.dev/docs/getting-started/project-structure/) for more general
information about the Reflex project structure.

### Adding Pages

Pages live in `nixstasis/pages/`. Each page is a function that returns a Reflex component and is registered by importing
it from `nixstasis/pages/__init__.py`.

This project uses the `@template` decorator in `nixstasis/templates/template.py` instead of using `@rx.page` or calling
`rx.add_page` directly.

To add a page:

1. Create a new file in `nixstasis/pages/` Its recommend to use one file per page.
2. Add a function decorated with `@template`, it accepts the same args as `@rx.page`.
3. Import the page in `nixstasis/pages/__init__.py` to register it; the sidebar order follows the import order in
  `nixstasis/components/sidebar.py`.

### Adding Components

Put reusable UI components that are shared across pages in `nixstasis/components/`. For example, the sidebar lives in
`nixstasis/components/sidebar.py`.

### Adding State

As the app grows, it's recommended to use [substates](https://reflex.dev/docs/substates/overview/) to organize state.

Define substates in their own files when they are shared, or colocate them in the page file when the state is
page-scoped.

### Running Nixstasis in Development Mode

Use the `Start Nixstasis` VS Code launch configuration to run the app locally for development and debugging. It invokes
`reflex run` and attaches the debugger to the running instance.

## FRP (Fast Reverse Proxy)

This service has two components:

* `frps`: The server, which must run on the same server as Nixstasis and must have a wildcard domain name assigned to
          the IP Address that the server is running. The IP Address must be publicly reachable on the Internet.
* `frpc`: This is the client that must be deployed on the devices that Nixstasis will monitor and provide remote access.

These services are configured using a `toml` file. The documentation can be referenced in the link above.

This repo includes a fully deployable configuration for the server designed for this service. It currently supports both
`ssh` and `https` proxying. This allows Nixstasis to provide remote access to the device's Web UI (Cockpit) and to
connect to the device via a terminal using `ssh` if for some reason the Web UI becomes unreachable due to a
configuration issue.

The nixstasis client includes a configuration file as well, that uses environment variables to provide a template. When
the Nixstasis client starts the `frpc` program, it provides the required values to ensure that each device gets a unique
subdomain. The current pattern for subdomains is `atom-${MAC_ADDRESS}` where the MAC Address is lowercased with the `:`
stripped. For example `atom-8268a89d95e7`.

## Caddy Server

Caddy is the front-end server and provides these features:

* Reverse proxying to FRPS
* Automatic TLS (HTTPS) certificates per device
* Static file serving for Nixstasis's UI
* Authentication via the AuthCrunch plugin

FRPS provides the public tunnel to devices but is not used for TLS termination. FRPS also does not reliably handle HTTP
upgrade requests (required for WebSockets) and lacks built-in ACME support. Caddy handles TLS termination and ACME,
which is why it's used in front of FRPS.

For on-demand certificates, Caddy requests approval the first time a subdomain is accessed. Nixstasis exposes the
`/permit_tls` endpoint to authorize these requests. The endpoint expects a `domain` query parameter and only allows a
certificate when the domain should be exposed for remote access. If no device matches the requested domain, or if remote
access hasn't been requested, the request is denied. Requests for the `nixstasis`, `auth`, and `frp-admin` domains are
always approved because Nixstasis depends on them.

Caddy may be configured using its Caddyfile or JSON formats; the repo includes a deployable Caddyfile covering the
current features.

## AuthCrunch

`AuthCrunch` is a plugin for Caddy that provides Authentication, Authorization, and Accounting (AAA) via a highly
flexible set of configuration options it adds to Caddy. The main feature used for Nixstasis is to provide authentication
using Microsoft Entra ID. The current configuration just provides basic support for authentication. If the user is a
valid user in the tenant, the user has permission to access Nixstasis.

However, AuthCrunch provides the ability to do user transforms. It can be configured to translate Entra ID Groups into
defined groups. Out of the box, those groups are `authp/admin`, `authp/user`, and `authp/guest`. These groups can be
passed to the backend application, in this case Nixstasis's backend, to be used to modify the actions a user can take.
This is left as a future TODO.
