package script

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestExecCmdRejectsPathShadowedCommands(t *testing.T) {
	dir := t.TempDir()
	shadow := filepath.Join(dir, "safe-cmd")
	if err := os.WriteFile(shadow, []byte("#!/bin/sh\necho shadowed\n"), 0o755); err != nil {
		t.Fatalf("write shadow command: %v", err)
	}
	oldPath := os.Getenv("PATH")
	t.Setenv("PATH", dir+string(os.PathListSeparator)+oldPath)

	runtime := NewRuntime(RuntimeConfig{
		Timeout: 5 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"safe-cmd": "/definitely/not/the/pinned/command",
		},
	})

	_, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="safe-cmd")}
`)
	if err == nil {
		t.Fatalf("expected pinned path execution to fail instead of using PATH shadow")
	}
	if strings.Contains(err.Error(), "shadowed") || strings.Contains(err.Error(), shadow) {
		t.Fatalf("exec_cmd used PATH shadowed command: %v", err)
	}
}

func TestExecCmdDoesNotPassUnrelatedEnvironment(t *testing.T) {
	dir := t.TempDir()
	cmdPath := filepath.Join(dir, "print-env")
	if err := os.WriteFile(cmdPath, []byte("#!/bin/sh\nprintf '%s' \"$NIXSTASIS_SECRET\"\n"), 0o755); err != nil {
		t.Fatalf("write test command: %v", err)
	}
	t.Setenv("NIXSTASIS_SECRET", "leaked")

	runtime := NewRuntime(RuntimeConfig{
		Timeout: 5 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"print-env": cmdPath,
		},
		ExecEnv: []string{"LANG=C"},
	})

	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="print-env")}
`)
	if err != nil {
		t.Fatalf("exec_cmd failed: %v", err)
	}
	if got := out["out"]; got != "" {
		t.Fatalf("expected unrelated env to be omitted, got %q", got)
	}
}

func TestExecCmdRequiresCapability(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	_, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="uname")}
`)
	if err == nil || !strings.Contains(err.Error(), "capability is not configured") {
		t.Fatalf("expected capability error, got %v", err)
	}
}
