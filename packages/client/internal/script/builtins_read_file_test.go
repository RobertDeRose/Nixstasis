package script

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestReadFileRequiresExplicitCapability(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	_, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="/proc/loadavg")}
`)
	if err == nil || !strings.Contains(err.Error(), "read_file capability is not configured") {
		t.Fatalf("expected read_file capability error, got %v", err)
	}
}

func TestReadFileReadsOnlyExplicitlyAllowlistedPath(t *testing.T) {
	dir := t.TempDir()
	allowed := filepath.Join(dir, "allowed")
	secret := filepath.Join(dir, "secret")
	if err := os.WriteFile(allowed, []byte("diagnostic\n"), 0o600); err != nil {
		t.Fatalf("write allowed file: %v", err)
	}
	if err := os.WriteFile(secret, []byte("device-token\n"), 0o600); err != nil {
		t.Fatalf("write secret file: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout:           5 * time.Second,
		ReadFileAllowlist: []string{allowed},
	})

	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="`+allowed+`")}
`)
	if err != nil {
		t.Fatalf("read allowlisted file: %v", err)
	}
	if got := out["out"]; got != "diagnostic" {
		t.Fatalf("read_file output = %q", got)
	}

	_, err = runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="`+secret+`")}
`)
	if err == nil || !strings.Contains(err.Error(), "not allowlisted") {
		t.Fatalf("expected non-allowlisted secret read to fail, got %v", err)
	}
}

func TestReadFileRejectsNixstasisStateEvenIfConfigured(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{
		Timeout:           5 * time.Second,
		ReadFileAllowlist: []string{"/etc/nixstasis/id"},
	})

	_, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="/etc/nixstasis/id")}
`)
	if err == nil || !strings.Contains(err.Error(), "protected") {
		t.Fatalf("expected protected identity path to fail, got %v", err)
	}
}

func TestReadFileRejectsOversizedContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "large")
	if err := os.WriteFile(path, []byte(strings.Repeat("x", maxReadFileBytes+1)), 0o600); err != nil {
		t.Fatalf("write large file: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout:           5 * time.Second,
		ReadFileAllowlist: []string{path},
	})
	_, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="`+path+`")}
`)
	if err == nil || !strings.Contains(err.Error(), "read limit") {
		t.Fatalf("expected oversized read to fail, got %v", err)
	}
}

func TestReadFilePreservesStableAllowlistedSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "target")
	link := filepath.Join(dir, "allowed-link")
	if err := os.WriteFile(target, []byte("diagnostic\n"), 0o600); err != nil {
		t.Fatalf("write target file: %v", err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatalf("create allowlisted symlink: %v", err)
	}

	runtime := NewRuntime(RuntimeConfig{
		Timeout:           5 * time.Second,
		ReadFileAllowlist: []string{link},
	})
	out, err := runtime.Execute(context.Background(), "test.star", `
def main():
    return {"out": read_file(path="`+link+`")}
`)
	if err != nil {
		t.Fatalf("read stable allowlisted symlink: %v", err)
	}
	if got := out["out"]; got != "diagnostic" {
		t.Fatalf("read_file symlink output = %q", got)
	}
}
