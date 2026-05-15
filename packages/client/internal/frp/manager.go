// Package frp manages the Fast Reverse Proxy (frp) client process.
package frp

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const defaultFRPExecPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
const systemdRunPath = "systemd-run"
const systemctlPath = "systemctl"
const frpcTransientUnit = "nixstasis-frpc"

// execCommandContext allows mocking the command execution in tests.
var execCommandContext = exec.CommandContext

var defaultSystemdAvailable = func() bool {
	_, err := os.Stat("/run/systemd/system")
	return err == nil
}

var systemdAvailable = defaultSystemdAvailable

var afterStopWaitHook = func() {}

const defaultProxyName = "nixstasis"

// Manager handles the lifecycle of the frpc process.
type Manager struct {
	mu     sync.Mutex
	status ConnectionStatus
	cmd    *exec.Cmd
	cancel context.CancelFunc
	waitCh chan struct{}
}

// NewManager creates a new Manager instance.
func NewManager() *Manager {
	return &Manager{
		status: ConnectionStatus{
			Active: false,
		},
	}
}

// Start launches the frpc process with the given config file.
// It is idempotent; if already running, it returns nil.
// The provided context is ignored for the process lifecycle to ensure it persists
// independent of the request context, but is kept for interface compatibility.
func (m *Manager) Start(ctx context.Context, configPath string) error {
	cfg, err := config.GetDefaultConfig()
	if err != nil {
		return fmt.Errorf("failed to load default frp config: %w", err)
	}
	frpConfig := cfg.FRP
	if frpConfig.Name == "" {
		frpConfig.Name = defaultProxyName
	}
	return m.StartWithConfig(ctx, configPath, frpConfig)
}

// StartWithConfig launches the frpc process with additional runtime config.
// The frpc.toml template is passed directly to frpc; all {{ .Envs.* }}
// placeholders are resolved by frpc from the process environment that this
// method constructs from the FRPConfig values.
func (m *Manager) StartWithConfig(_ context.Context, configPath string, frpConfig config.FRPConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.status.Active {
		slog.Debug("FRP tunnel already active")
		return nil
	}

	if err := validateFRPConfig(frpConfig); err != nil {
		return err
	}
	if !systemdAvailable() {
		return fmt.Errorf("systemd is required to start frpc transient service")
	}

	slog.Info("Starting FRP tunnel", "config", configPath)

	// Create a context that we can cancel to kill the process
	cmdCtx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel
	m.waitCh = make(chan struct{})

	args := frpcCommandArgs(configPath, frpConfig)

	// Pass the template directly to frpc; it expands {{ .Envs.* }} natively.
	//nolint:contextcheck // Intentional creation of new context for background process
	cmd := execCommandContext(cmdCtx, systemdRunPath, args...)
	cmd.Env = frpEnv(frpConfig)
	m.cmd = cmd

	if err := cmd.Start(); err != nil {
		m.cancel()
		return fmt.Errorf("failed to start frpc: %w", err)
	}

	m.status.Active = true
	m.status.PID = cmd.Process.Pid
	m.status.StartTime = time.Now()
	m.status.ConnectionString = configPath
	waitCh := m.waitCh

	// Wait for process in background to handle cleanup if it crashes
	go func() {
		defer close(waitCh)

		err := cmd.Wait()
		slog.Info("FRP process exited", "error", err)

		m.mu.Lock()
		defer m.mu.Unlock()
		// Only reset if this is still the current command
		if m.cmd == cmd {
			if m.cancel != nil {
				m.cancel()
				m.cancel = nil
			}
			m.status.Active = false
			m.status.PID = 0
			m.status.ConnectionString = ""
			m.status.StartTime = time.Time{}
			m.cmd = nil
			m.waitCh = nil
		}
	}()

	return nil
}

func frpcCommandArgs(configPath string, frpConfig config.FRPConfig) []string {
	args := []string{
		"--unit", frpcTransientUnit,
		"--wait",
		"--collect",
		"--property", "PrivateTmp=true",
		"--property", "Restart=on-failure",
	}
	for _, entry := range frpcTemplateEnv(frpConfig) {
		args = append(args, "--setenv", entry)
	}
	args = append(args, "--", config.FRPCBinaryPath(), "-c", configPath)
	return args
}

// frpEnv builds the environment for the frpc subprocess.  Every
// {{ .Envs.* }} placeholder in frpc.toml must have a corresponding entry
// here so frpc can resolve it at startup.
func frpEnv(frpConfig config.FRPConfig) []string {
	pathValue := os.Getenv("PATH")
	if pathValue == "" {
		pathValue = defaultFRPExecPath
	}
	env := []string{"PATH=" + pathValue}
	if home := os.Getenv("HOME"); home != "" {
		env = append(env, "HOME="+home)
	}
	if tmpDir := os.Getenv("TMPDIR"); tmpDir != "" {
		env = append(env, "TMPDIR="+tmpDir)
	}

	env = append(env,
		frpcTemplateEnv(frpConfig)...,
	)

	return env
}

func frpcTemplateEnv(frpConfig config.FRPConfig) []string {
	return []string{
		"FRPS_AUTH_TOKEN=" + frpConfig.AuthToken,
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
	if !loopbackAddr(frpConfig.WebServerAddr) {
		return fmt.Errorf("frp web_server_addr must be a loopback address (127.0.0.1, ::1, or localhost)")
	}
	return nil
}

// loopbackAddr returns true if the address is a loopback address.
func loopbackAddr(value string) bool {
	if value == "localhost" {
		return true
	}
	// Strip brackets for IPv6 addresses (e.g., "[::1]")
	stripped := value
	if len(stripped) > 2 && stripped[0] == '[' && stripped[len(stripped)-1] == ']' {
		stripped = stripped[1 : len(stripped)-1]
	}
	ip := net.ParseIP(stripped)
	return ip != nil && ip.IsLoopback()
}

// Stop terminates the frpc process.
func (m *Manager) Stop() error {
	m.mu.Lock()
	if !m.status.Active {
		m.mu.Unlock()
		return nil
	}

	slog.Info("Stopping FRP tunnel", "pid", m.status.PID)
	cancel := m.cancel
	waitCh := m.waitCh
	cmd := m.cmd
	m.mu.Unlock()

	stopCmd := execCommandContext(context.Background(), systemctlPath, "stop", frpcTransientUnit+".service")
	if err := stopCmd.Run(); err != nil {
		return fmt.Errorf("failed to stop frpc transient service: %w", err)
	}

	if cancel != nil {
		cancel()
	}

	if waitCh == nil {
		return nil
	}

	<-waitCh
	afterStopWaitHook()

	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cmd == cmd {
		return errors.New("frp process did not clean up after stop")
	}

	return nil
}

// GetStatus returns the current connection status.
func (m *Manager) GetStatus() ConnectionStatus {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.status
}
