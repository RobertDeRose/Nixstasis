// Package frp manages the Fast Reverse Proxy (frp) client process.
package frp

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const defaultFRPExecPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

const defaultFRPExecPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

// execCommandContext allows mocking the command execution in tests.
var execCommandContext = exec.CommandContext

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
	return m.StartWithConfig(ctx, configPath, config.FRPConfig{Name: defaultProxyName})
}

// StartWithConfig launches the frpc process with additional runtime config.
func (m *Manager) StartWithConfig(_ context.Context, configPath string, frpConfig config.FRPConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.status.Active {
		slog.Debug("FRP tunnel already active")
		return nil
	}

	renderedConfigPath, err := renderConfig(configPath, frpConfig)
	if err != nil {
		return err
	}

	slog.Info("Starting FRP tunnel", "config", renderedConfigPath)

	// Create a context that we can cancel to kill the process
	cmdCtx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel
	m.waitCh = make(chan struct{})

	// -c configPath is standard for frpc
	//nolint:contextcheck // Intentional creation of new context for background process
	cmd := execCommandContext(cmdCtx, config.FRPCBinaryPath(), "-c", renderedConfigPath)
	pathValue := os.Getenv("PATH")
	if pathValue == "" {
		pathValue = defaultFRPExecPath
	}
	baseEnv := []string{"PATH=" + pathValue}
	if home := os.Getenv("HOME"); home != "" {
		baseEnv = append(baseEnv, "HOME="+home)
	}
	if tmpDir := os.Getenv("TMPDIR"); tmpDir != "" {
		baseEnv = append(baseEnv, "TMPDIR="+tmpDir)
	}
	cmd.Env = append(baseEnv,
		"FRPS_AUTH_TOKEN="+frpConfig.AuthToken,
		"FRPS_SERVER_ADDR="+frpConfig.ServerAddr,
	)
	m.cmd = cmd

	if err := cmd.Start(); err != nil {
		m.cancel()
		_ = os.Remove(renderedConfigPath)
		return fmt.Errorf("failed to start frpc: %w", err)
	}

	m.status.Active = true
	m.status.PID = cmd.Process.Pid
	m.status.StartTime = time.Now()
	m.status.ConnectionString = renderedConfigPath // Storing config path as proxy for connection string for now
	waitCh := m.waitCh

	// Wait for process in background to handle cleanup if it crashes
	go func() {
		defer close(waitCh)
		defer func() { _ = os.Remove(renderedConfigPath) }()

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

func renderConfig(configPath string, frpConfig config.FRPConfig) (string, error) {
	template, err := os.ReadFile(configPath)
	if err != nil {
		return "", fmt.Errorf("failed to read frpc config: %w", err)
	}

	if frpConfig.Name == "" && strings.Contains(string(template), "{{ .Envs.NAME }}") {
		return "", fmt.Errorf("frpc config requires a non-empty name")
	}

	replacements := map[string]string{
		"{{ .Envs.NAME }}": frpConfig.Name,
	}

	rendered := stripTemplateCommentPlaceholders(string(template))
	for placeholder, value := range replacements {
		rendered = strings.ReplaceAll(rendered, placeholder, value)
	}
	if unresolvedNonEnvPlaceholder(rendered) {
		return "", fmt.Errorf("frpc config contains unresolved template placeholders")
	}

	file, err := os.CreateTemp(os.TempDir(), "nixstasis-frpc-*.toml")
	if err != nil {
		return "", fmt.Errorf("failed to create rendered frpc config: %w", err)
	}
	path := file.Name()
	defer file.Close()

	if err := file.Chmod(0o600); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("failed to secure rendered frpc config: %w", err)
	}

	if _, err := file.WriteString(rendered); err != nil {
		_ = os.Remove(path)
		return "", fmt.Errorf("failed to write rendered frpc config: %w", err)
	}

	return path, nil
}

var templateCommentPattern = regexp.MustCompile(`(?m)^\s*#.*\{\{.*\}\}.*$`)

// envPlaceholderPattern matches FRP-native {{ .Envs.VAR }} placeholders that
// frpc resolves from its own process environment at startup.
var envPlaceholderPattern = regexp.MustCompile(`\{\{\s*\.Envs\.\w+\s*\}\}`)

func stripTemplateCommentPlaceholders(template string) string {
	return templateCommentPattern.ReplaceAllString(template, "")
}

// unresolvedNonEnvPlaceholder returns true if the rendered config still
// contains {{ ... }} placeholders that are NOT frpc-native .Envs references.
func unresolvedNonEnvPlaceholder(rendered string) bool {
	cleaned := envPlaceholderPattern.ReplaceAllString(rendered, "")
	return strings.Contains(cleaned, "{{")
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
