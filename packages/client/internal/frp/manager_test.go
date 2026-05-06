package frp

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

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

	configPath := writeFRPConfig(t, "serverAddr = \"nixstasis.example.com\"\n")
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
	configPath := writeFRPConfig(t, "serverAddr = \"nixstasis.example.com\"\n")
	if err := mgr.Start(context.Background(), configPath); err != nil {
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
	configPath := writeFRPConfig(t, "auth.token = \"{{ .Envs.FRPS_AUTH_TOKEN }}\"\n")
	if err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{AuthToken: "secret-token"}); err != nil {
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

func TestRenderConfigReplacesPackagedPlaceholders(t *testing.T) {
	configPath := writeFRPConfig(t, strings.Join([]string{
		`auth.token = "{{ .Envs.FRPS_AUTH_TOKEN }}"`,
		`name = "{{ .Envs.NAME }}"`,
		`subdomain = "{{ .Envs.NAME }}"`,
	}, "\n"))

	renderedPath, err := renderConfig(configPath, config.FRPConfig{AuthToken: "secret-token", Name: "atom-aabbcc"})
	if err != nil {
		t.Fatalf("renderConfig() error = %v", err)
	}
	defer func() { _ = os.Remove(renderedPath) }()

	rendered, err := os.ReadFile(renderedPath)
	if err != nil {
		t.Fatalf("read rendered config: %v", err)
	}

	text := string(rendered)
	if strings.Contains(text, "{{") {
		t.Fatalf("rendered config still contains placeholders: %s", text)
	}
	if !strings.Contains(text, `auth.token = "secret-token"`) {
		t.Fatalf("rendered config missing token: %s", text)
	}
	if !strings.Contains(text, `name = "atom-aabbcc"`) {
		t.Fatalf("rendered config missing name: %s", text)
	}
	if !strings.Contains(text, `subdomain = "atom-aabbcc"`) {
		t.Fatalf("rendered config missing runtime subdomain name: %s", text)
	}
}

func TestRenderConfigAllowsTemplateCommentsInPackagedConfig(t *testing.T) {
	configPath := writeFRPConfig(t, strings.Join([]string{
		`# This file is processed by gomplate ({{ .Envs.NAME }})`,
		`auth.token = "{{ .Envs.FRPS_AUTH_TOKEN }}"`,
		`name = "{{ .Envs.NAME }}"`,
	}, "\n"))

	renderedPath, err := renderConfig(configPath, config.FRPConfig{AuthToken: "secret-token", Name: "atom-aabbcc"})
	if err != nil {
		t.Fatalf("renderConfig() error = %v", err)
	}
	defer func() { _ = os.Remove(renderedPath) }()

	rendered, err := os.ReadFile(renderedPath)
	if err != nil {
		t.Fatalf("read rendered config: %v", err)
	}

	if strings.Contains(string(rendered), "{{") {
		t.Fatalf("rendered config still contains placeholders: %s", string(rendered))
	}
}

func TestRenderConfigRequiresName(t *testing.T) {
	configPath := writeFRPConfig(t, `name = "{{ .Envs.NAME }}"`)

	_, err := renderConfig(configPath, config.FRPConfig{AuthToken: "secret-token"})
	if err == nil || !strings.Contains(err.Error(), "requires a non-empty name") {
		t.Fatalf("expected missing-name error, got %v", err)
	}
}

func TestPackagedConfigExampleProvidesFRPName(t *testing.T) {
	configPath := filepath.Join("..", "..", "build", "root-dir", "usr", "share", "nixstasis", "config.example.yaml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config example: %v", err)
	}

	if !strings.Contains(string(data), "name:") {
		t.Fatalf("expected frp.name in config example: %s", string(data))
	}
}

func TestManagerStartWithConfigRendersRuntimeValuesForProcess(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, strings.Join([]string{
		`auth.token = "{{ .Envs.FRPS_AUTH_TOKEN }}"`,
		`name = "{{ .Envs.NAME }}"`,
	}, "\n"))

	if err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{AuthToken: "secret-token", Name: "atom-aabbcc"}); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	status := mgr.GetStatus()
	if status.ConnectionString == "" {
		t.Fatal("expected rendered config path to be tracked")
	}

	rendered, err := os.ReadFile(status.ConnectionString)
	if err != nil {
		t.Fatalf("read rendered runtime config: %v", err)
	}

	text := string(rendered)
	if !strings.Contains(text, `auth.token = "secret-token"`) {
		t.Fatalf("runtime config missing token: %s", text)
	}
	if !strings.Contains(text, `name = "atom-aabbcc"`) {
		t.Fatalf("runtime config missing name: %s", text)
	}
}

func TestManagerStartUsesFallbackNameForPackagedTemplate(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	mgr := NewManager()
	configPath := filepath.Join("..", "..", "build", "root-dir", "etc", "nixstasis", "frpc.toml")

	if err := mgr.Start(context.Background(), configPath); err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	status := mgr.GetStatus()
	if status.ConnectionString == "" {
		t.Fatal("expected rendered config path to be tracked")
	}

	rendered, err := os.ReadFile(status.ConnectionString)
	if err != nil {
		t.Fatalf("read rendered fallback config: %v", err)
	}

	text := string(rendered)
	if strings.Contains(text, "{{") {
		t.Fatalf("rendered config still contains placeholders: %s", text)
	}
	if !strings.Contains(text, `name = "nixstasis"`) {
		t.Fatalf("rendered config missing fallback name: %s", text)
	}
	if !strings.Contains(text, `subdomain = "nixstasis"`) {
		t.Fatalf("rendered config missing fallback subdomain: %s", text)
	}
	if !strings.Contains(text, `customDomains = ["nixstasis-ssh"]`) {
		t.Fatalf("rendered config missing fallback ssh domain: %s", text)
	}
}

func TestManagerStopWaitsForOwnedProcessCleanup(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, "serverAddr = \"nixstasis.example.com\"\n")
	if err := mgr.Start(context.Background(), configPath); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	stopDone := make(chan error, 1)
	statusDuringStop := make(chan ConnectionStatus, 1)
	var once sync.Once

	go func() {
		stopDone <- mgr.Stop()
	}()

	deadline := time.Now().Add(5 * time.Second)
	for {
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for active status during stop")
		}

		status := mgr.GetStatus()
		if status.Active {
			once.Do(func() { statusDuringStop <- status })
			break
		}

		time.Sleep(10 * time.Millisecond)
	}

	select {
	case err := <-stopDone:
		if err != nil {
			t.Fatalf("Stop() error = %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Stop() did not return")
	}

	duringStop := <-statusDuringStop
	if !duringStop.Active || duringStop.PID == 0 {
		t.Fatalf("expected active process ownership during stop, got %+v", duringStop)
	}

	finalStatus := mgr.GetStatus()
	if finalStatus.Active {
		t.Fatalf("expected inactive final status, got %+v", finalStatus)
	}
	if finalStatus.PID != 0 {
		t.Fatalf("expected PID cleared after shutdown, got %+v", finalStatus)
	}
	if finalStatus.ConnectionString != "" {
		t.Fatalf("expected connection string cleared after shutdown, got %+v", finalStatus)
	}
}

func TestManagerStopDoesNotClearReplacementProcess(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()

	originalHook := afterStopWaitHook
	defer func() { afterStopWaitHook = originalHook }()

	mgr := NewManager()
	firstConfigPath := writeFRPConfig(t, "serverAddr = \"nixstasis.example.com\"\n")
	secondConfigPath := writeFRPConfig(t, "serverAddr = \"replacement.example.com\"\n")

	if err := mgr.Start(context.Background(), firstConfigPath); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	firstStatus := mgr.GetStatus()
	if !firstStatus.Active || firstStatus.PID == 0 {
		t.Fatalf("expected initial process to be active, got %+v", firstStatus)
	}

	afterStopWaitHook = func() {
		if err := mgr.Start(context.Background(), secondConfigPath); err != nil {
			t.Fatalf("replacement Start() error = %v", err)
		}
	}

	if err := mgr.Stop(); err != nil {
		t.Fatalf("Stop() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	finalStatus := mgr.GetStatus()
	if !finalStatus.Active {
		t.Fatalf("expected replacement process to remain active, got %+v", finalStatus)
	}
	if finalStatus.PID == 0 {
		t.Fatalf("expected replacement PID to be set, got %+v", finalStatus)
	}
	if finalStatus.PID == firstStatus.PID {
		t.Fatalf("expected replacement PID to differ from original, got %+v", finalStatus)
	}
	if finalStatus.ConnectionString == "" {
		t.Fatalf("expected replacement connection string, got %+v", finalStatus)
	}
	if finalStatus.ConnectionString == firstStatus.ConnectionString {
		t.Fatalf("expected replacement connection string to differ, got %+v", finalStatus)
	}
}

func writeFRPConfig(t *testing.T, content string) string {
	t.Helper()
	path := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write frpc config: %v", err)
	}
	return path
}

func envValue(env []string, key string) string {
	for _, entry := range env {
		if before, after, ok := strings.Cut(entry, "="); ok && before == key {
			return after
		}
	}

	return ""
}
