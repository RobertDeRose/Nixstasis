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
	// Set config path to a non-existent file.
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "/nonexistent/frpc.toml")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/usr/bin/true")

	err := runFRPSession(nil)
	if err == nil || !strings.Contains(err.Error(), "frpc config not found") {
		t.Fatalf("expected config not found error, got %v", err)
	}
}

func TestRunFRPSession_MissingBinary(t *testing.T) {
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
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	// Use "true" as the frpc binary — exits 0 immediately.
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/usr/bin/true")

	origExec := execCommand
	defer func() { execCommand = origExec }()

	var capturedArgs []string
	execCommand = func(ctx context.Context, name string, args ...string) *exec.Cmd {
		capturedArgs = append([]string{name}, args...)
		return exec.CommandContext(ctx, name, args...)
	}

	err := runFRPSession(nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	// Verify it was called with -c <configPath>.
	if len(capturedArgs) < 3 || capturedArgs[1] != "-c" || capturedArgs[2] != configPath {
		t.Fatalf("expected frpc -c %s, got %v", configPath, capturedArgs)
	}
}

func TestRunFRPSession_ContextCancellation(t *testing.T) {
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	// Use "sleep" as the frpc binary so it blocks until cancelled.
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/bin/sleep")

	origExec := execCommand
	defer func() { execCommand = origExec }()

	// Override to launch "sleep 3600" but let context cancellation kill it.
	execCommand = func(ctx context.Context, name string, _ ...string) *exec.Cmd {
		return exec.CommandContext(ctx, "sleep", "3600")
	}

	// We can't easily test the full runFRPSession with its own context,
	// but we can test that frpc termination via context is treated as normal.
	// The function creates its own context with 1h timeout. Instead, test
	// that a quick exit with error when context is not cancelled is reported.
	// For a proper cancellation test, we'd need to refactor the function.
	// For now, verify the happy path works (tested above) and binary validation.
	t.Skip("full cancellation test requires refactoring runFRPSession to accept context")
}

func TestRunFRPSession_FRPCFailure(t *testing.T) {
	configPath := t.TempDir() + "/frpc.toml"
	if err := os.WriteFile(configPath, []byte("# test"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", configPath)
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/usr/bin/false")

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
