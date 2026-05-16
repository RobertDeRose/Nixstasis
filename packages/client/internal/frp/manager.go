// Package frp manages the Fast Reverse Proxy (frp) client process.
//
// The manager launches frpc as a systemd transient service via systemd-run.
// This is a fire-and-forget model: systemd owns the process lifecycle.
// The manager checks status via systemctl and stops via systemctl stop.
package frp

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const (
	defaultFRPExecPath      = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	systemdRunPath          = "systemd-run"
	systemctlPath           = "systemctl"
	frpcTransientUnit       = "nixstasis-frpc"
	frpsAuthTokenCredential = "FRPS_AUTH_TOKEN" // #nosec G101 -- credential name, not a credential value.
)

// execCommandContext allows mocking command execution in tests.
var execCommandContext = exec.CommandContext

var defaultSystemdAvailable = func() bool {
	_, err := os.Stat("/run/systemd/system")
	return err == nil
}

var systemdAvailable = defaultSystemdAvailable

// Manager handles launching and stopping the frpc transient service.
// It does not track in-process state — systemd is the source of truth.
type Manager struct{}

// NewManager creates a new Manager instance.
func NewManager() *Manager {
	return &Manager{}
}

// Start launches the frpc transient service via systemd-run.
// The call returns as soon as the unit is enqueued — systemd owns the
// process from that point forward.
//
// The transient unit runs `nixstasis frp-session`, which handles the
// 1-hour timeout and launches frpc as a child process. frpc reads
// frpc.toml directly and expands {{ .Envs.* }} from its environment.
func (m *Manager) Start(configPath string, frpConfig config.FRPConfig) error {
	if err := validateFRPConfig(frpConfig); err != nil {
		return err
	}
	if !systemdAvailable() {
		return fmt.Errorf("systemd is required to start frpc transient service")
	}

	// Check if already running — systemd is the source of truth.
	if m.IsActive() {
		slog.Debug("FRP tunnel already active")
		return nil
	}

	slog.Info("Starting FRP tunnel", "config", configPath, "name", frpConfig.Name)

	credentialPath, cleanup, err := writeCredential(frpsAuthTokenCredential, frpConfig.AuthToken)
	if err != nil {
		return err
	}
	defer cleanup()

	args := systemdRunArgs(configPath, frpConfig, credentialPath)
	cmd := execCommandContext(context.Background(), systemdRunPath, args...)
	cmd.Env = systemdRunEnv()

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to start frpc transient service: %w: %s", err, strings.TrimSpace(string(output)))
	}

	slog.Info("FRP transient service started", "unit", frpcTransientUnit)
	return nil
}

// Stop terminates the frpc transient service.
func (m *Manager) Stop() error {
	if !m.IsActive() {
		return nil
	}

	slog.Info("Stopping FRP tunnel")
	cmd := execCommandContext(context.Background(), systemctlPath, "stop", frpcTransientUnit+".service")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to stop frpc transient service: %w: %s", err, strings.TrimSpace(string(output)))
	}

	slog.Info("FRP transient service stopped")
	return nil
}

// IsActive checks whether the frpc transient service is currently running.
func (m *Manager) IsActive() bool {
	cmd := execCommandContext(context.Background(), systemctlPath, "is-active", "--quiet", frpcTransientUnit+".service")
	return cmd.Run() == nil
}

// GetStatus returns the current connection status by querying systemd.
func (m *Manager) GetStatus() ConnectionStatus {
	if !m.IsActive() {
		return ConnectionStatus{}
	}
	return ConnectionStatus{
		Active:           true,
		ConnectionString: frpcTransientUnit,
	}
}

// systemdRunArgs builds the systemd-run command arguments.
// The transient unit runs `nixstasis frp-session` which handles timeout
// and launches frpc. Non-secret template values are passed via --setenv so frpc
// can expand {{ .Envs.* }} placeholders natively. FRPS_AUTH_TOKEN is passed as a
// systemd credential to avoid exposing it in transient unit metadata.
func systemdRunArgs(configPath string, frpConfig config.FRPConfig, credentialPath string) []string {
	args := make([]string, 0, 18+2*len(frpcTemplateEnv(frpConfig)))
	args = append(args,
		"--quiet",
		"--collect",
		"--service-type=simple",
		"--unit", frpcTransientUnit,
		"--property", "PrivateTmp=true",
		"--property", "Restart=on-failure",
		"--property", "LoadCredential="+frpsAuthTokenCredential+":"+credentialPath,
	)

	// Pass non-secret FRP config as env vars for frpc template expansion.
	for _, entry := range frpcTemplateEnv(frpConfig) {
		args = append(args, "--setenv", entry)
	}

	// The transient unit runs the frp-session subcommand, which
	// launches frpc with a 1-hour timeout.
	nixstasisBin, err := os.Executable()
	if err != nil {
		// Fall back to PATH-based lookup.
		nixstasisBin = "nixstasis"
	}
	args = append(args, "--", nixstasisBin, "frp-session", "--config", configPath, "--frpc", config.FRPCBinaryPath())

	return args
}

func writeCredential(name, value string) (path string, cleanup func(), err error) {
	dir, err := os.MkdirTemp("", "nixstasis-frp-credential-*")
	if err != nil {
		return "", nil, fmt.Errorf("failed to create credential directory: %w", err)
	}
	cleanup = func() {
		if err := os.RemoveAll(dir); err != nil {
			slog.Error("failed to remove FRP credential directory", "error", err)
		}
	}

	path = filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(value), 0o600); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("failed to write FRP credential: %w", err)
	}

	return path, cleanup, nil
}

// systemdRunEnv returns the minimal environment for the systemd-run process.
// Template vars are passed via --setenv, not the systemd-run process env.
func systemdRunEnv() []string {
	pathValue := os.Getenv("PATH")
	if pathValue == "" {
		pathValue = defaultFRPExecPath
	}
	env := []string{"PATH=" + pathValue}
	if home := os.Getenv("HOME"); home != "" {
		env = append(env, "HOME="+home)
	}
	return env
}

// frpcTemplateEnv returns the environment variables that map to
// {{ .Envs.* }} placeholders in frpc.toml.
func frpcTemplateEnv(frpConfig config.FRPConfig) []string {
	return []string{
		"FRPS_SERVER_ADDR=" + frpConfig.ServerAddr,
		"FRPS_SERVER_PORT=" + strconv.Itoa(frpConfig.ServerPort),
		"NAME=" + frpConfig.Name,
		"SSH_NAME=" + frpConfig.Name + "-ssh",
		"FRPC_WEB_SERVER_ADDR=" + frpConfig.WebServerAddr,
		"FRPC_WEB_SERVER_PORT=" + strconv.Itoa(frpConfig.WebServerPort),
		"FRPC_HTTP_LOCAL_ADDR=" + frpConfig.HTTPLocalAddr,
		"FRPC_SSH_LOCAL_PORT=" + strconv.Itoa(frpConfig.SSHLocalPort),
	}
}

// validateFRPConfig checks that the FRPConfig is safe to pass to frpc.
func validateFRPConfig(frpConfig config.FRPConfig) error {
	if frpConfig.Name == "" {
		return fmt.Errorf("frpc config requires a non-empty name")
	}
	if frpConfig.AuthToken == "" {
		return fmt.Errorf("frpc config requires a non-empty auth_token")
	}
	if frpConfig.ServerAddr == "" {
		return fmt.Errorf("frpc config requires a non-empty server_addr")
	}
	if !loopbackAddr(frpConfig.WebServerAddr) {
		return fmt.Errorf("frp web_server_addr must be a loopback address (127.0.0.1, ::1, or localhost)")
	}
	for _, p := range []struct {
		name string
		val  int
	}{
		{"server_port", frpConfig.ServerPort},
		{"web_server_port", frpConfig.WebServerPort},
		{"ssh_local_port", frpConfig.SSHLocalPort},
	} {
		if p.val <= 0 || p.val > 65535 {
			return fmt.Errorf("frp %s must be between 1 and 65535, got %d", p.name, p.val)
		}
	}
	if frpConfig.HTTPLocalAddr == "" || !strings.Contains(frpConfig.HTTPLocalAddr, ":") {
		return fmt.Errorf("frp http_local_addr must be in host:port format, got %q", frpConfig.HTTPLocalAddr)
	}
	return nil
}

// loopbackAddr returns true if the address is a loopback address.
func loopbackAddr(value string) bool {
	if value == "localhost" {
		return true
	}
	stripped := value
	if len(stripped) > 2 && stripped[0] == '[' && stripped[len(stripped)-1] == ']' {
		stripped = stripped[1 : len(stripped)-1]
	}
	ip := net.ParseIP(stripped)
	return ip != nil && ip.IsLoopback()
}
