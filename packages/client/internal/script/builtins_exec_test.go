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

func TestExecCmdSanitizesHighRiskEnvironment(t *testing.T) {
	dir := t.TempDir()
	cmdPath := filepath.Join(dir, "print-env")
	script := `#!/bin/sh
printf 'LD_PRELOAD=%s
DYLD_INSERT_LIBRARIES=%s
BASH_ENV=%s
PYTHONPATH=%s
PATH=%s
SAFE=%s' \
"$LD_PRELOAD" \
"$DYLD_INSERT_LIBRARIES" \
"$BASH_ENV" \
"$PYTHONPATH" \
"$PATH" \
"$SAFE"
`
	if err := os.WriteFile(cmdPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write test command: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout: 5 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"print-env": cmdPath,
		},
		ExecEnv: []string{
			"LD_PRELOAD=/tmp/preload.so",
			"DYLD_INSERT_LIBRARIES=/tmp/dyld.dylib",
			"BASH_ENV=/tmp/bashrc",
			"PYTHONPATH=/tmp/python",
			"PATH=/custom/bin",
			"SAFE=kept",
		},
	})

	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="print-env")}
`)
	if err != nil {
		t.Fatalf("exec_cmd failed: %v", err)
	}

	got, ok := out["out"].(string)
	if !ok {
		t.Fatalf("expected string output, got %T", out["out"])
	}

	const want = "LD_PRELOAD=\nDYLD_INSERT_LIBRARIES=\nBASH_ENV=\nPYTHONPATH=\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nSAFE=kept"
	if got != want {
		t.Fatalf("unexpected sanitized env:\nwant:\n%s\n\ngot:\n%s", want, got)
	}
}

func TestExecCmdProvidesNormalizedDefaultEnvironment(t *testing.T) {
	dir := t.TempDir()
	cmdPath := filepath.Join(dir, "print-env")
	script := `#!/bin/sh
printf 'HOME=%s
LANG=%s
LC_ALL=%s
PATH=%s
TMPDIR=%s' \
"$HOME" \
"$LANG" \
"$LC_ALL" \
"$PATH" \
"$TMPDIR"
`
	if err := os.WriteFile(cmdPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write test command: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout: 5 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"print-env": cmdPath,
		},
	})

	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="print-env")}
`)
	if err != nil {
		t.Fatalf("exec_cmd failed: %v", err)
	}

	got, ok := out["out"].(string)
	if !ok {
		t.Fatalf("expected string output, got %T", out["out"])
	}

	const want = "HOME=/\nLANG=C.UTF-8\nLC_ALL=C.UTF-8\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nTMPDIR=/tmp"
	if got != want {
		t.Fatalf("unexpected default env:\nwant:\n%s\n\ngot:\n%s", want, got)
	}
}

func TestExecCmdRunsAllowlistedCommandWithSanitizedEnvironment(t *testing.T) {
	dir := t.TempDir()
	cmdPath := filepath.Join(dir, "safe-cmd")
	if err := os.WriteFile(cmdPath, []byte("#!/bin/sh\nprintf '%s:%s' \"$SAFE\" \"$PATH\"\n"), 0o755); err != nil {
		t.Fatalf("write test command: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout: 5 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"safe-cmd": cmdPath,
		},
		ExecEnv: []string{"SAFE=ok", "LD_PRELOAD=/tmp/preload.so"},
	})

	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": exec_cmd(cmd="safe-cmd")}
`)
	if err != nil {
		t.Fatalf("exec_cmd failed: %v", err)
	}

	const want = "ok:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	if got := out["out"]; got != want {
		t.Fatalf("expected allowlisted command to succeed with sanitized env, got %q", got)
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
