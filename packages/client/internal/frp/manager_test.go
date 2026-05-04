package frp

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

// TestHelperProcess isn't a real test; it's used to mock exec.Command
// This is a standard Go pattern for mocking os/exec.
func TestHelperProcess(_ *testing.T) {
	if os.Getenv("GO_WANT_HELPER_PROCESS") != "1" {
		return
	}
	// Simulate a long-running process
	select {}
}

func fakeExecCommand(ctx context.Context, command string, args ...string) *exec.Cmd {
	cs := make([]string, 0, 3+len(args))
	cs = append(cs, "-test.run=TestHelperProcess", "--", command)
	cs = append(cs, args...)
	cmd := exec.CommandContext(ctx, os.Args[0], cs...)
	cmd.Env = []string{"GO_WANT_HELPER_PROCESS=1"}
	return cmd
}

func TestManager_Lifecycle(t *testing.T) {
	// Swap the exec command
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	configPath := "/tmp/frpc.toml"
	mgr := NewManager()

	tests := []struct {
		name        string
		action      func(t *testing.T) error
		wantActive  bool
		wantPID     bool // true if PID should be non-zero
		expectError bool
	}{
		{
			name: "Start FRP",
			action: func(_ *testing.T) error {
				return mgr.Start(context.Background(), configPath)
			},
			wantActive:  true,
			wantPID:     true,
			expectError: false,
		},
		{
			name: "Start FRP (Idempotent)",
			action: func(_ *testing.T) error {
				return mgr.Start(context.Background(), configPath)
			},
			wantActive:  true,
			wantPID:     true,
			expectError: false,
		},
		{
			name: "Stop FRP",
			action: func(_ *testing.T) error {
				return mgr.Stop()
			},
			wantActive:  false,
			wantPID:     false,
			expectError: false,
		},
		{
			name: "Stop FRP (Idempotent)",
			action: func(_ *testing.T) error {
				return mgr.Stop()
			},
			wantActive:  false,
			wantPID:     false,
			expectError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.action(t)
			if (err != nil) != tt.expectError {
				t.Errorf("Action returned error: %v, expectError: %v", err, tt.expectError)
			}

			status := mgr.GetStatus()
			if status.Active != tt.wantActive {
				t.Errorf("Active status = %v, want %v", status.Active, tt.wantActive)
			}

			if tt.wantPID && status.PID == 0 {
				t.Error("Expected PID to be set")
			} else if !tt.wantPID && status.PID != 0 {
				t.Errorf("Expected PID 0, got %d", status.PID)
			}
		})
	}
}

func TestManager_RealStatus(t *testing.T) {
	mgr := NewManager()
	s := mgr.GetStatus()
	if s.Active {
		t.Error("New manager should be inactive")
	}
}

func TestManagerUsesBundledFRPCPath(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	mgr := NewManager()
	if err := mgr.Start(context.Background(), "/tmp/frpc.toml"); err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if mgr.cmd == nil {
		t.Fatal("expected command to be initialized")
	}

	if got := mgr.cmd.Args[3]; got != config.FRPCBinaryPath() {
		t.Fatalf("frpc binary = %q", got)
	}
}

func TestManagerPassesFRPAuthToken(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	mgr := NewManager()
	if err := mgr.StartWithConfig(context.Background(), "/tmp/frpc.toml", config.FRPConfig{AuthToken: "secret-token"}); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if mgr.cmd == nil {
		t.Fatal("expected command to be initialized")
	}

	if got := envValue(mgr.cmd.Env, "FRPS_AUTH_TOKEN"); got != "secret-token" {
		t.Fatalf("FRPS_AUTH_TOKEN = %q", got)
	}
}

func envValue(env []string, key string) string {
	for _, entry := range env {
		if before, after, ok := strings.Cut(entry, "="); ok && before == key {
			return after
		}
	}

	return ""
}
