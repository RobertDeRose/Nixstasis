// Package frp manages the Fast Reverse Proxy (frp) client process.
package frp

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"sync"
	"time"

	"github.com/sfero-nixstasis/client/internal/config"
)

// execCommandContext allows mocking the command execution in tests.
var execCommandContext = exec.CommandContext

// Manager handles the lifecycle of the frpc process.
type Manager struct {
	mu     sync.Mutex
	status ConnectionStatus
	cmd    *exec.Cmd
	cancel context.CancelFunc
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
func (m *Manager) Start(_ context.Context, configPath string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.status.Active {
		slog.Debug("FRP tunnel already active")
		return nil
	}

	slog.Info("Starting FRP tunnel", "config", configPath)

	// Create a context that we can cancel to kill the process
	cmdCtx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	// -c configPath is standard for frpc
	//nolint:contextcheck // Intentional creation of new context for background process
	cmd := execCommandContext(cmdCtx, config.FRPCBinaryPath(), "-c", configPath)
	m.cmd = cmd

	if err := cmd.Start(); err != nil {
		m.cancel()
		return fmt.Errorf("failed to start frpc: %w", err)
	}

	m.status.Active = true
	m.status.PID = cmd.Process.Pid
	m.status.StartTime = time.Now()
	m.status.ConnectionString = configPath // Storing config path as proxy for connection string for now

	// Wait for process in background to handle cleanup if it crashes
	go func() {
		err := cmd.Wait()
		slog.Info("FRP process exited", "error", err)

		m.mu.Lock()
		defer m.mu.Unlock()
		// Only reset if this is still the current command
		if m.cmd == cmd {
			m.status.Active = false
			m.status.PID = 0
			m.cmd = nil
			if m.cancel != nil {
				m.cancel() // Ensure resources are cleaned up
				m.cancel = nil
			}
		}
	}()

	return nil
}

// Stop terminates the frpc process.
func (m *Manager) Stop() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.status.Active {
		return nil
	}

	slog.Info("Stopping FRP tunnel", "pid", m.status.PID)

	if m.cancel != nil {
		m.cancel() // This kills the process context
	}

	// We can also explicitly kill if needed, but context cancel should handle it via exec.CommandContext
	// Verify and cleanup
	m.status.Active = false
	m.status.PID = 0
	m.cmd = nil
	m.cancel = nil

	return nil
}

// GetStatus returns the current connection status.
func (m *Manager) GetStatus() ConnectionStatus {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.status
}
