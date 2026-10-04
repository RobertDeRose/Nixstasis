package sshauth

import (
	"encoding/base64"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadHostPublicKeyFromNormalizesComment(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "ssh_host_ed25519_key.pub")
	blob := make([]byte, 4+len("ssh-ed25519")+32)
	binary.BigEndian.PutUint32(blob[:4], uint32(len("ssh-ed25519")))
	copy(blob[4:], "ssh-ed25519")
	encoded := base64.StdEncoding.EncodeToString(blob)
	if err := os.WriteFile(path, []byte("ssh-ed25519 "+encoded+" root@test\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	got, err := LoadHostPublicKeyFrom(path)
	if err != nil {
		t.Fatalf("LoadHostPublicKeyFrom: %v", err)
	}
	want := "ssh-ed25519 " + encoded
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestLoadHostPublicKeyFromRejectsMismatchedBlobAlgorithm(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "ssh_host_key.pub")
	blob := make([]byte, 4+len("ssh-rsa")+8)
	binary.BigEndian.PutUint32(blob[:4], uint32(len("ssh-rsa")))
	copy(blob[4:], "ssh-rsa")
	encoded := base64.StdEncoding.EncodeToString(blob)
	if err := os.WriteFile(path, []byte("ssh-ed25519 "+encoded+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	if _, err := LoadHostPublicKeyFrom(path); err == nil {
		t.Fatal("expected mismatched algorithm to be rejected")
	}
}
