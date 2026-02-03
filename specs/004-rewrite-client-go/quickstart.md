# Quickstart - Nixstasis Client (Go)

## Prerequisites

- Go 1.21+
- `frpc` installed in `$PATH` (for remote access features)
- Systemd (for service management)

## Installation

### From Source
```bash
git clone https://github.com/checkpoint/sfero-nixstasis.git
cd sfero-nixstasis/packages/client-go
go build -o nixstasis cmd/nixstasis/main.go
sudo mv nixstasis /usr/local/bin/
```

### Configuration
Create `/etc/nixstasis/config.yaml`:

```yaml
api_url: "https://nixstasis.example.com/api/v1"
interface: "eth0"
plugin_dir: "/usr/libexec/nixstasis/plugins"
log_level: "info"
```

## Usage

### Registration
Manually trigger registration (usually handled by systemd on first boot):
```bash
sudo nixstasis register
```

### Polling
Run the polling loop (foreground):
```bash
sudo nixstasis poll
```

### Developing Plugins
1. Create a directory: `mkdir -p my-plugin`
2. Create `manifest.json`:
   ```json
   {
     "version": "1.0.0",
     "executables": ["collect_data.sh"]
   }
   ```
3. Create `collect_data.sh` (ensure it prints JSON to stdout and is executable).
4. Install to `/usr/libexec/nixstasis/plugins/my-plugin`.

## Service Management
```bash
sudo systemctl start nixstasis-client
sudo systemctl status nixstasis-client
```
