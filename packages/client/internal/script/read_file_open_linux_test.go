//go:build linux

package script

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSecureOpenReadFileRejectsFinalSymlinkSwap(t *testing.T) {
	dir := t.TempDir()
	allowed := filepath.Join(dir, "allowed")
	secret := filepath.Join(dir, "secret")
	if err := os.WriteFile(allowed, []byte("allowed\n"), 0o600); err != nil {
		t.Fatalf("write allowed file: %v", err)
	}
	if err := os.WriteFile(secret, []byte("secret\n"), 0o600); err != nil {
		t.Fatalf("write secret file: %v", err)
	}

	resolved, err := canonicalReadFilePath(allowed, dir)
	if err != nil {
		t.Fatalf("canonicalize allowed file: %v", err)
	}
	if err := os.Rename(allowed, allowed+".original"); err != nil {
		t.Fatalf("move allowed file: %v", err)
	}
	if err := os.Symlink(secret, allowed); err != nil {
		t.Fatalf("replace allowed file with symlink: %v", err)
	}

	file, err := secureOpenReadFile(resolved)
	if file != nil {
		_ = file.Close()
	}
	if err == nil {
		t.Fatal("expected final-component symlink swap to fail")
	}
}

func TestSecureOpenReadFileRejectsIntermediateSymlinkSwap(t *testing.T) {
	root := t.TempDir()
	allowedDir := filepath.Join(root, "allowed-dir")
	secretDir := filepath.Join(root, "secret-dir")
	if err := os.MkdirAll(allowedDir, 0o700); err != nil {
		t.Fatalf("create allowed directory: %v", err)
	}
	if err := os.MkdirAll(secretDir, 0o700); err != nil {
		t.Fatalf("create secret directory: %v", err)
	}
	allowed := filepath.Join(allowedDir, "value")
	if err := os.WriteFile(allowed, []byte("allowed\n"), 0o600); err != nil {
		t.Fatalf("write allowed file: %v", err)
	}
	if err := os.WriteFile(filepath.Join(secretDir, "value"), []byte("secret\n"), 0o600); err != nil {
		t.Fatalf("write secret file: %v", err)
	}

	resolved, err := canonicalReadFilePath(allowed, root)
	if err != nil {
		t.Fatalf("canonicalize allowed file: %v", err)
	}
	if err := os.Rename(allowedDir, allowedDir+".original"); err != nil {
		t.Fatalf("move allowed directory: %v", err)
	}
	if err := os.Symlink(secretDir, allowedDir); err != nil {
		t.Fatalf("replace allowed directory with symlink: %v", err)
	}

	file, err := secureOpenReadFile(resolved)
	if file != nil {
		_ = file.Close()
	}
	if err == nil {
		t.Fatal("expected intermediate-component symlink swap to fail")
	}
}

func TestSecureOpenReadFileReadsCanonicalFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "allowed")
	if err := os.WriteFile(path, []byte("diagnostic\n"), 0o600); err != nil {
		t.Fatalf("write allowed file: %v", err)
	}

	resolved, err := canonicalReadFilePath(path, filepath.Dir(path))
	if err != nil {
		t.Fatalf("canonicalize allowed file: %v", err)
	}
	file, err := secureOpenReadFile(resolved)
	if err != nil {
		t.Fatalf("secure open canonical file: %v", err)
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		t.Fatalf("read canonical file: %v", err)
	}
	if got := strings.TrimSpace(string(data)); got != "diagnostic" {
		t.Fatalf("secure read = %q", got)
	}
}
