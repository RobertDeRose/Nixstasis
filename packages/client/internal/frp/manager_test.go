package frp

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

// commandLog captures commands invoked via execCommandContext during a test.
type commandLog struct {
	mu       sync.Mutex
	calls    []capturedCommand
	isActive bool // controls what systemctl is-active returns
}

type capturedCommand struct {
	command string
	args    []string
}

// fakeExec returns a mock exec function that records calls and uses
// TestHelperProcess for actual execution. systemctl is-active returns
// success (exit 0) when cl.isActive is true.
func (cl *commandLog) fakeExec() func(ctx context.Context, command string, args ...string) *exec.Cmd {
	return func(ctx context.Context, command string, args ...string) *exec.Cmd {
		cl.mu.Lock()
		defer cl.mu.Unlock()

		// Record the call for assertions.
		cl.calls = append(cl.calls, capturedCommand{command: command, args: args})

		// For systemctl is-active, return exit 0 or 1 based on cl.isActive.
		if command == systemctlPath && len(args) > 0 && args[0] == "is-active" {
			if cl.isActive {
				return exec.CommandContext(ctx, "true")
			}
			return exec.CommandContext(ctx, "false")
		}

		// For systemctl stop, just succeed.
		if command == systemctlPath && len(args) > 0 && args[0] == "stop" {
			cl.isActive = false
			return exec.CommandContext(ctx, "true")
		}

		// For systemd-run, succeed and mark as active.
		if command == systemdRunPath {
			cl.isActive = true
			return exec.CommandContext(ctx, "true")
		}

		// Fallback: succeed.
		return exec.CommandContext(ctx, "true")
	}
}

func (cl *commandLog) lastSystemdRun() *capturedCommand {
	cl.mu.Lock()
	defer cl.mu.Unlock()
	for i := len(cl.calls) - 1; i >= 0; i-- {
		if cl.calls[i].command == systemdRunPath {
			return &cl.calls[i]
		}
	}
	return nil
}

func setupTest(t *testing.T) (*commandLog, func()) {
	t.Helper()
	cl := &commandLog{}
	origExec := execCommandContext
	origSys := systemdAvailable
	execCommandContext = cl.fakeExec()
	systemdAvailable = func() bool { return true }
	return cl, func() {
		execCommandContext = origExec
		systemdAvailable = origSys
	}
}

func validFRPConfig() config.FRPConfig {
	return config.FRPConfig{
		AuthToken:     "secret-token",
		Name:          "atom-aabbcc",
		ServerAddr:    "frps.internal",
		ServerPort:    7001,
		WebServerAddr: "127.0.0.1",
		WebServerPort: 7401,
		HTTPLocalAddr: "127.0.0.1:8443",
		SSHLocalPort:  2222,
	}
}

// --- Start / Stop / IsActive ---

func TestManager_StartStop(t *testing.T) {
	cl, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	// Initially inactive.
	if mgr.IsActive() {
		t.Fatal("expected inactive before start")
	}

	// Start should invoke systemd-run.
	if err := mgr.Start(configPath, validFRPConfig()); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	// After start, IsActive should return true.
	if !mgr.IsActive() {
		t.Fatal("expected active after start")
	}

	// Idempotent start should be a no-op.
	callsBefore := len(cl.calls)
	if err := mgr.Start(configPath, validFRPConfig()); err != nil {
		t.Fatalf("idempotent Start() error = %v", err)
	}
	// Should have checked is-active but not called systemd-run again.
	found := false
	cl.mu.Lock()
	for i := callsBefore; i < len(cl.calls); i++ {
		if cl.calls[i].command == systemdRunPath {
			found = true
		}
	}
	cl.mu.Unlock()
	if found {
		t.Fatal("idempotent Start should not call systemd-run again")
	}

	// Stop should invoke systemctl stop.
	if err := mgr.Stop(); err != nil {
		t.Fatalf("Stop() error = %v", err)
	}
	if mgr.IsActive() {
		t.Fatal("expected inactive after stop")
	}

	// Idempotent stop should succeed.
	if err := mgr.Stop(); err != nil {
		t.Fatalf("idempotent Stop() error = %v", err)
	}
}

func TestManager_GetStatus(t *testing.T) {
	cl, cleanup := setupTest(t)
	defer cleanup()
	_ = cl

	mgr := NewManager()

	// Inactive status.
	status := mgr.GetStatus()
	if status.Active {
		t.Error("expected inactive status")
	}
	if status.ConnectionString != "" {
		t.Errorf("expected empty ConnectionString, got %q", status.ConnectionString)
	}

	// Make active.
	cl.isActive = true
	status = mgr.GetStatus()
	if !status.Active {
		t.Error("expected active status")
	}
	if status.ConnectionString != frpcTransientUnit {
		t.Errorf("ConnectionString = %q, want %q", status.ConnectionString, frpcTransientUnit)
	}
}

// --- systemd-run argument assertions ---

func TestStart_SystemdRunArgs(t *testing.T) {
	cl, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`)

	if err := mgr.Start(configPath, validFRPConfig()); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	run := cl.lastSystemdRun()
	if run == nil {
		t.Fatal("expected systemd-run call")
	}

	args := strings.Join(run.args, "\x00")

	requiredFragments := []string{
		"--quiet",
		"--collect",
		"--service-type=simple",
		"--unit\x00" + frpcTransientUnit,
		"--property\x00PrivateTmp=true",
		"--property\x00Restart=on-failure",
		"--setenv\x00FRPS_AUTH_TOKEN=secret-token",
		"--setenv\x00FRPS_SERVER_ADDR=frps.internal",
		"--setenv\x00FRPS_SERVER_PORT=7001",
		"--setenv\x00NAME=atom-aabbcc",
		"--setenv\x00SSH_NAME=atom-aabbcc-ssh",
		"--setenv\x00FRPC_WEB_SERVER_ADDR=127.0.0.1",
		"--setenv\x00FRPC_WEB_SERVER_PORT=7401",
		"--setenv\x00FRPC_HTTP_LOCAL_ADDR=127.0.0.1:8443",
		"--setenv\x00FRPC_SSH_LOCAL_PORT=2222",
	}

	for _, want := range requiredFragments {
		if !strings.Contains(args, want) {
			t.Errorf("systemd-run args missing %q\ngot: %v", want, run.args)
		}
	}

	// Should end with -- nixstasis frp-session
	if !argsContainSequence(run.args, "--") {
		t.Error("expected -- separator in systemd-run args")
	}
	// The command after -- should contain "frp-session"
	for i, arg := range run.args {
		if arg == "--" && i+2 < len(run.args) {
			if run.args[i+2] != "frp-session" {
				t.Errorf("expected frp-session subcommand, got %q", run.args[i+2])
			}
			break
		}
	}
}

func TestStart_NoWaitFlag(t *testing.T) {
	cl, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	if err := mgr.Start(configPath, validFRPConfig()); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	run := cl.lastSystemdRun()
	if run == nil {
		t.Fatal("expected systemd-run call")
	}
	for _, arg := range run.args {
		if arg == "--wait" {
			t.Fatal("fire-and-forget model must not use --wait")
		}
	}
}

// --- Validation ---

func TestStart_RejectsEmptyName(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.Name = ""
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "non-empty name") {
		t.Fatalf("expected missing-name error, got %v", err)
	}
}

func TestStart_RejectsEmptyAuthToken(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.AuthToken = ""
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "non-empty auth_token") {
		t.Fatalf("expected missing-auth_token error, got %v", err)
	}
}

func TestStart_RejectsEmptyServerAddr(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.ServerAddr = ""
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "non-empty server_addr") {
		t.Fatalf("expected missing-server_addr error, got %v", err)
	}
}

func TestStart_RejectsNonLoopbackWebServerAddr(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.WebServerAddr = "0.0.0.0"
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "loopback") {
		t.Fatalf("expected loopback validation error, got %v", err)
	}
}

func TestStart_RejectsInvalidPorts(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.ServerPort = 0
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "server_port") {
		t.Fatalf("expected port validation error, got %v", err)
	}
}

func TestStart_RejectsInvalidHTTPLocalAddr(t *testing.T) {
	_, cleanup := setupTest(t)
	defer cleanup()

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	cfg := validFRPConfig()
	cfg.HTTPLocalAddr = "nocolon"
	err := mgr.Start(configPath, cfg)
	if err == nil || !strings.Contains(err.Error(), "host:port") {
		t.Fatalf("expected http_local_addr validation error, got %v", err)
	}
}

func TestStart_RequiresSystemd(t *testing.T) {
	origExec := execCommandContext
	origSys := systemdAvailable
	defer func() {
		execCommandContext = origExec
		systemdAvailable = origSys
	}()
	cl := &commandLog{}
	execCommandContext = cl.fakeExec()
	systemdAvailable = func() bool { return false }

	mgr := NewManager()
	configPath := writeFRPConfig(t, `test = true`)

	err := mgr.Start(configPath, validFRPConfig())
	if err == nil || !strings.Contains(err.Error(), "systemd is required") {
		t.Fatalf("expected systemd requirement error, got %v", err)
	}
}

// --- loopbackAddr ---

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

// --- systemdRunEnv ---

func TestSystemdRunEnv_MinimalEnv(t *testing.T) {
	env := systemdRunEnv()
	foundPATH := false
	for _, e := range env {
		if strings.HasPrefix(e, "PATH=") {
			foundPATH = true
		}
		// Should not contain template vars.
		if strings.HasPrefix(e, "FRPS_") || strings.HasPrefix(e, "NAME=") {
			t.Errorf("systemdRunEnv should not contain template vars, got %q", e)
		}
	}
	if !foundPATH {
		t.Error("systemdRunEnv should include PATH")
	}
}

// --- frpcTemplateEnv ---

func TestFRPCTemplateEnv(t *testing.T) {
	cfg := validFRPConfig()
	env := frpcTemplateEnv(cfg)

	checks := map[string]string{
		"FRPS_AUTH_TOKEN":      "secret-token",
		"FRPS_SERVER_ADDR":     "frps.internal",
		"FRPS_SERVER_PORT":     "7001",
		"NAME":                 "atom-aabbcc",
		"SSH_NAME":             "atom-aabbcc-ssh",
		"FRPC_WEB_SERVER_ADDR": "127.0.0.1",
		"FRPC_WEB_SERVER_PORT": "7401",
		"FRPC_HTTP_LOCAL_ADDR": "127.0.0.1:8443",
		"FRPC_SSH_LOCAL_PORT":  "2222",
	}

	for key, want := range checks {
		if got := envValue(env, key); got != want {
			t.Errorf("%s = %q, want %q", key, got, want)
		}
	}
}

// --- Packaged config assertions ---

func TestPackagedConfigUsesQuotedPlaceholders(t *testing.T) {
	configPath := filepath.Join("..", "..", "build", "root-dir", "usr", "share", "nixstasis", "frpc.toml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read packaged frpc config: %v", err)
	}

	text := string(data)

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

// --- Helpers ---

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
