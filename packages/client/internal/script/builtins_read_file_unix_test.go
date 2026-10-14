//go:build linux || darwin

package script

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestReadFileRejectsSymlinkAndSymlinkParent(t *testing.T) {
	dir := readFileTestDir(t)
	target := filepath.Join(dir, "target")
	if err := os.WriteFile(target, []byte("secret"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	parentLink := filepath.Join(dir, "parent")
	if err := os.Symlink(dir, parentLink); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{link, filepath.Join(parentLink, "target")} {
		runtime := NewRuntime(RuntimeConfig{Timeout: time.Second, ReadFileAllowlist: []string{path}})
		_, err := runtime.Execute(context.Background(), "test.star", `def main():
    return {"out": read_file(path="`+path+`")}`)
		if err == nil {
			t.Fatalf("symlink-based allowlist accepted: %s", path)
		}
	}
}

func TestReadFileRejectsSymlinkReplacementAfterAuthorization(t *testing.T) {
	dir := readFileTestDir(t)
	path := filepath.Join(dir, "allowed")
	secret := filepath.Join(dir, "secret")
	for _, name := range []string{path, secret} {
		if err := os.WriteFile(name, []byte("data"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	runtime := NewRuntime(RuntimeConfig{ReadFileAllowlist: []string{path}})
	resolved, err := runtime.resolveReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(secret, path); err != nil {
		t.Fatal(err)
	}
	file, err := openReadFile(resolved)
	if file != nil {
		_ = file.Close()
	}
	if err == nil {
		t.Fatal("symlink swapped after authorization was followed")
	}
}

func TestReadFileRejectsFIFOWithoutWaitingForWriter(t *testing.T) {
	path := filepath.Join(readFileTestDir(t), "fifo")
	if err := unix.Mkfifo(path, 0o600); err != nil {
		t.Fatal(err)
	}
	runtime := NewRuntime(RuntimeConfig{Timeout: 50 * time.Millisecond, ReadFileAllowlist: []string{path}})
	done := make(chan error, 1)
	go func() {
		_, err := runtime.Execute(context.Background(), "test.star", `def main():
    return {"out": read_file(path="`+path+`")}`)
		done <- err
	}()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("FIFO read was accepted")
		}
	case <-time.After(time.Second):
		// Release a blocking implementation so the regression test does not leak it.
		file, _ := os.OpenFile(path, os.O_WRONLY|unix.O_NONBLOCK, 0)
		if file != nil {
			_ = file.Close()
		}
		t.Fatal("FIFO open outlived script timeout")
	}
}
