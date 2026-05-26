package main

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestRunFRPSession_MissingConfig(t *testing.T) {
	resetFRPSessionFlags(t)
	// Set config path to a non-existent file.
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "/nonexistent/frpc.toml")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", commandPath(t, "true"))

	err := runFRPSession(nil)
	if err == nil || !strings.Contains(err.Error(), "frpc config not found") {
		t.Fatalf("expected config not found error, got %v", err)
	}
}

func TestRunFRPSession_MissingBinary(t *testing.T) {
	resetFRPSessionFlags(t)
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/nonexistent/frpc")

	err := runFRPSession(nil)
	if err == nil || !strings.Contains(err.Error(), "frpc binary not found") {
		t.Fatalf("expected binary not found error, got %v", err)
	}
}

func TestRunFRPSession_SuccessfulRun(t *testing.T) {
	resetFRPSessionFlags(t)
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	// Use "true" as the frpc binary — exits 0 immediately.
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", commandPath(t, "true"))
	t.Setenv("FRPS_AUTH_TOKEN", "secret-token")

	origExec := execCommand
	defer func() { execCommand = origExec }()

	var capturedArgs []string
	var capturedCmd *exec.Cmd
	execCommand = func(ctx context.Context, name string, args ...string) *exec.Cmd {
		capturedArgs = append([]string{name}, args...)
		cmd := exec.CommandContext(ctx, name, args...)
		capturedCmd = cmd
		return cmd
	}

	err := runFRPSession(nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	// Verify it was called with -c <configPath>.
	if len(capturedArgs) < 3 || capturedArgs[1] != "-c" || capturedArgs[2] != configPath {
		t.Fatalf("expected frpc -c %s, got %v", configPath, capturedArgs)
	}
	if capturedCmd == nil || envValue(capturedCmd.Env, "FRPS_AUTH_TOKEN") != "secret-token" {
		t.Fatalf("expected frpc env to include FRPS_AUTH_TOKEN")
	}
}

func TestRunFRPSession_UsesExplicitPaths(t *testing.T) {
	resetFRPSessionFlags(t)
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	frpcPath := commandPath(t, "true")
	frpSessionConfigPath = configPath
	frpSessionBinaryPath = frpcPath
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "/nonexistent/wrong.toml")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/nonexistent/wrong-frpc")
	t.Setenv("FRPS_AUTH_TOKEN", "secret-token")

	origExec := execCommand
	defer func() { execCommand = origExec }()

	var capturedArgs []string
	execCommand = func(ctx context.Context, name string, args ...string) *exec.Cmd {
		capturedArgs = append([]string{name}, args...)
		return exec.CommandContext(ctx, name, args...)
	}

	if err := runFRPSession(nil); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(capturedArgs) < 3 || capturedArgs[0] != frpcPath || capturedArgs[2] != configPath {
		t.Fatalf("expected explicit frpc/config paths, got %v", capturedArgs)
	}
}

func TestRunFRPSession_ContextCancellation(t *testing.T) {
	resetFRPSessionFlags(t)
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	// Use "sleep" as the frpc binary so it blocks until canceled.
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", commandPath(t, "sleep"))

	origExec := execCommand
	defer func() { execCommand = origExec }()

	// Override to launch "sleep 3600" but let context cancellation kill it.
	execCommand = func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
		return exec.CommandContext(ctx, "sleep", "3600")
	}

	// We can't easily test the full runFRPSession with its own context,
	// but we can test that frpc termination via context is treated as normal.
	// The function creates its own context with 1h timeout. Instead, test
	// that a quick exit with error when context is not canceled is reported.
	// For a proper cancellation test, we'd need to refactor the function.
	// For now, verify the happy path works (tested above) and binary validation.
	t.Skip("full cancellation test requires refactoring runFRPSession to accept context")
}

func TestRunFRPSession_FRPCFailure(t *testing.T) {
	resetFRPSessionFlags(t)
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", commandPath(t, "false"))
	t.Setenv("FRPS_AUTH_TOKEN", "secret-token")

	origExec := execCommand
	defer func() { execCommand = origExec }()

	execCommand = func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
		return exec.CommandContext(ctx, "false")
	}

	done := make(chan error, 1)
	go func() {
		done <- runFRPSession(nil)
	}()

	select {
	case err := <-done:
		if err == nil || !strings.Contains(err.Error(), "frpc exited with error") {
			t.Fatalf("expected frpc error, got %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("runFRPSession did not return in time")
	}
}

func resetFRPSessionFlags(t *testing.T) {
	t.Helper()
	frpSessionConfigPath = ""
	frpSessionBinaryPath = ""
}

func commandPath(t *testing.T, name string) string {
	t.Helper()

	path, err := exec.LookPath(name)
	if err != nil {
		t.Fatalf("expected %s on PATH: %v", name, err)
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
