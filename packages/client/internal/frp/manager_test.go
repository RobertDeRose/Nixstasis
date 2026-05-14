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
	for _, arg := range os.Args {
		if arg == systemctlPath {
			return
		}
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
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)
	mgr := NewManager()

	tests := []struct {
		name        string
		action      func(t *testing.T) error
		wantActive  bool
		wantPID     bool
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
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)
	if err := mgr.Start(context.Background(), configPath); err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if mgr.cmd == nil {
		t.Fatal("expected command to be initialized")
	}

	if !argsContainSequence(mgr.cmd.Args, "--", config.FRPCBinaryPath(), "-c", configPath) {
		t.Fatalf("expected systemd-run to launch bundled frpc, got %#v", mgr.cmd.Args)
	}
}

func TestManagerPassesAllEnvVars(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	frpConfig := config.FRPConfig{
		AuthToken:     "secret-token",
		Name:          "atom-aabbcc",
		ServerAddr:    "frps.internal",
		ServerPort:    7001,
		WebServerAddr: "127.0.0.2",
		WebServerPort: 7401,
		HTTPLocalAddr: "127.0.0.1:8443",
		SSHLocalPort:  2222,
	}

	if err := mgr.StartWithConfig(context.Background(), configPath, frpConfig); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if mgr.cmd == nil {
		t.Fatal("expected command to be initialized")
	}

	checks := map[string]string{
		"FRPS_AUTH_TOKEN":      "secret-token",
		"FRPS_SERVER_ADDR":     "frps.internal",
		"FRPS_SERVER_PORT":     "7001",
		"NAME":                 "atom-aabbcc",
		"SSH_NAME":             "atom-aabbcc-ssh",
		"FRPC_WEB_SERVER_ADDR": "127.0.0.2",
		"FRPC_WEB_SERVER_PORT": "7401",
		"FRPC_HTTP_LOCAL_ADDR": "127.0.0.1:8443",
		"FRPC_SSH_LOCAL_PORT":  "2222",
	}

	for key, want := range checks {
		if got := envValue(mgr.cmd.Env, key); got != want {
			t.Errorf("%s = %q, want %q", key, got, want)
		}
	}
}

func TestManagerPassesConfigPathDirectlyToFRPC(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	frpConfig := config.FRPConfig{
		Name:          "test",
		WebServerAddr: "127.0.0.1",
	}

	if err := mgr.StartWithConfig(context.Background(), configPath, frpConfig); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	// The config path passed to frpc -c should be the original template path,
	// not a rendered temp file.
	args := mgr.cmd.Args
	for i, arg := range args {
		if arg == "-c" && i+1 < len(args) {
			if args[i+1] != configPath {
				t.Fatalf("frpc -c path = %q, want %q (original template)", args[i+1], configPath)
			}
			return
		}
	}
	t.Fatal("expected -c flag in frpc command args")
}

func TestManagerUsesSystemdRunWhenAvailable(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)
	frpConfig := config.FRPConfig{
		AuthToken:     "secret-token",
		Name:          "atom-aabbcc",
		ServerAddr:    "frps.internal",
		ServerPort:    7001,
		WebServerAddr: "127.0.0.1",
		WebServerPort: 7401,
		HTTPLocalAddr: "127.0.0.1:8443",
		SSHLocalPort:  2222,
	}

	if err := mgr.StartWithConfig(context.Background(), configPath, frpConfig); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if got := mgr.cmd.Args[3]; got != systemdRunPath {
		t.Fatalf("command = %q, want %q", got, systemdRunPath)
	}
	args := strings.Join(mgr.cmd.Args, "\x00")
	for _, want := range []string{
		"--unit\x00" + frpcTransientUnit,
		"--wait",
		"--collect",
		"--property\x00PrivateTmp=true",
		"--property\x00Restart=on-failure",
		"--setenv\x00FRPS_AUTH_TOKEN=secret-token",
		"--setenv\x00FRPS_SERVER_ADDR=frps.internal",
		"--\x00" + config.FRPCBinaryPath() + "\x00-c\x00" + configPath,
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("systemd-run args missing %q in %#v", want, mgr.cmd.Args)
		}
	}
}

func TestStartWithConfigRejectsEmptyName(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `name = "{{ .Envs.NAME }}"`)

	err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{
		WebServerAddr: "127.0.0.1",
	})
	if err == nil || !strings.Contains(err.Error(), "non-empty name") {
		t.Fatalf("expected missing-name error, got %v", err)
	}
}

func TestStartWithConfigRejectsNonLoopbackWebServerAddr(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `webServer.addr = "{{ .Envs.FRPC_WEB_SERVER_ADDR }}"`)

	err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{
		Name:          "test",
		WebServerAddr: "0.0.0.0",
	})
	if err == nil || !strings.Contains(err.Error(), "loopback") {
		t.Fatalf("expected loopback validation error, got %v", err)
	}
}

func TestStartWithConfigRequiresSystemd(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return false }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{
		Name:          "test",
		WebServerAddr: "127.0.0.1",
	})
	if err == nil || !strings.Contains(err.Error(), "systemd is required") {
		t.Fatalf("expected systemd requirement error, got %v", err)
	}
}

func TestLoopbackAddr(t *testing.T) {
	tests := []struct {
		addr string
		want bool
	}{
		{"127.0.0.1", true},
		{"localhost", true},
		{"::1", true},
		{"[::1]", true},
		{"0.0.0.0", false},
		{"192.168.1.1", false},
		{"", false},
	}
	for _, tt := range tests {
		t.Run(tt.addr, func(t *testing.T) {
			if got := loopbackAddr(tt.addr); got != tt.want {
				t.Errorf("loopbackAddr(%q) = %v, want %v", tt.addr, got, tt.want)
			}
		})
	}
}

func TestPackagedConfigUsesQuotedPlaceholders(t *testing.T) {
	configPath := filepath.Join("..", "..", "build", "root-dir", "usr", "share", "nixstasis", "frpc.toml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read packaged frpc config: %v", err)
	}

	text := string(data)

	// String values should be quoted in the template
	quotedPlaceholders := []string{
		`"{{ .Envs.FRPS_SERVER_ADDR }}"`,
		`"{{ .Envs.FRPS_AUTH_TOKEN }}"`,
		`"{{ .Envs.NAME }}"`,
		`"{{ .Envs.SSH_NAME }}"`,
		`"{{ .Envs.FRPC_WEB_SERVER_ADDR }}"`,
		`"{{ .Envs.FRPC_HTTP_LOCAL_ADDR }}"`,
	}
	for _, want := range quotedPlaceholders {
		if !strings.Contains(text, want) {
			t.Errorf("packaged frpc config missing quoted placeholder %s", want)
		}
	}

	// Integer values should be unquoted
	unquotedPlaceholders := []string{
		"{{ .Envs.FRPS_SERVER_PORT }}",
		"{{ .Envs.FRPC_WEB_SERVER_PORT }}",
		"{{ .Envs.FRPC_SSH_LOCAL_PORT }}",
	}
	for _, want := range unquotedPlaceholders {
		if !strings.Contains(text, want) {
			t.Errorf("packaged frpc config missing placeholder %s", want)
		}
	}

	// Template should document frpc-native expansion, not client rendering
	if strings.Contains(text, "client renders") {
		t.Error("packaged frpc config should not document client-side rendering")
	}
	if !strings.Contains(text, "frpc expands") {
		t.Error("packaged frpc config should document frpc-native expansion")
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

func TestManagerStartWithConfigTracksConfigPath(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	if err := mgr.StartWithConfig(context.Background(), configPath, config.FRPConfig{
		Name:          "atom-aabbcc",
		WebServerAddr: "127.0.0.1",
	}); err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	status := mgr.GetStatus()
	if status.ConnectionString != configPath {
		t.Fatalf("ConnectionString = %q, want %q", status.ConnectionString, configPath)
	}
}

func TestManagerStartUsesFallbackName(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `name = "{{ .Envs.NAME }}"`)

	// Start() uses defaultProxyName ("nixstasis") when no name is provided
	if err := mgr.Start(context.Background(), configPath); err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() { _ = mgr.Stop() }()

	if got := envValue(mgr.cmd.Env, "NAME"); got != "nixstasis" {
		t.Fatalf("NAME = %q, want %q", got, "nixstasis")
	}
	if got := envValue(mgr.cmd.Env, "SSH_NAME"); got != "nixstasis-ssh" {
		t.Fatalf("SSH_NAME = %q, want %q", got, "nixstasis-ssh")
	}
}

func TestManagerStopWaitsForOwnedProcessCleanup(t *testing.T) {
	execCommandContext = fakeExecCommand
	defer func() { execCommandContext = exec.CommandContext }()
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)
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
	systemdAvailable = func() bool { return true }
	defer func() { systemdAvailable = defaultSystemdAvailable }()

	originalHook := afterStopWaitHook
	defer func() { afterStopWaitHook = originalHook }()

	mgr := NewManager()
	firstConfigPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)
	secondConfigPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

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

func argsContainSequence(args []string, want ...string) bool {
	for i := 0; i+len(want) <= len(args); i++ {
		matched := true
		for j := range want {
			if args[i+j] != want[j] {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}
