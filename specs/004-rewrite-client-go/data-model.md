# Data Model - Rewrite Client in Go

## Entities

### DeviceIdentity
Represents the core identity of the device, persisted to `/etc/nixstasis/id`.

| Field | Type | Description |
| :--- | :--- | :--- |
| `uuid` | string (UUID) | Unique ID assigned by Nixstasis server. |
| `mac_address` | string | MAC address of the primary interface (eth0). |
| `ip_address` | string | IPv4 address of the primary interface. |
| `name` | string | Generated name `atom-<mac>`. |

### PluginManifest
Represents the metadata loaded from `manifest.json` in each plugin directory.

| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | string | Unique name of the plugin (derived from directory name or manifest). |
| `version` | string | Semantic version of the plugin. |
| `update_url` | string (URL) | URL to check for updates (metadata only). |
| `schema_url` | string (URL) | URL defining the JSON schema of the output. |
| `executables` | []string | List of binary names (relative to manifest) to execute. |

### TelemetryPayload
The aggregated payload sent to the Nixstasis API during a poll.

| Field | Type | Description |
| :--- | :--- | :--- |
| `device` | object | Core device stats (DeviceUpdate). |
| `plugins` | map[string]object | Merged output from plugins. |
| `meta` | object | Metadata about the poll (timestamp, duration, errors). |

### ConnectionStatus
Represents the state of the remote access tunnel.

| Field | Type | Description |
| :--- | :--- | :--- |
| `active` | boolean | Is the tunnel currently running? |
| `connection_string` | string | The FRP URL (if active). |
| `pid` | int | Process ID of the `frpc` instance. |
| `start_time` | timestamp | When the tunnel was started. |

## Storage

- **File**: `/etc/nixstasis/id` (Plain text UUID).
- **File**: `/etc/nixstasis/config.yaml` (Configuration).
- **Dir**: `/usr/libexec/nixstasis/plugins` (Read-only plugins).
