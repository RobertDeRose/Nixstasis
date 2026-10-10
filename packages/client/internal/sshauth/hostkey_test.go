package sshauth

import (
	"crypto/ecdh"
	"crypto/rand"
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
	encoded := encodeSSHBlob("ssh-ed25519", make([]byte, 32))
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

func TestNormalizeHostPublicKeyAcceptsCompleteKeyBodies(t *testing.T) {
	t.Parallel()

	keys := map[string]string{
		"rsa":      "ssh-rsa " + encodeSSHBlob("ssh-rsa", []byte{1, 0, 1}, append([]byte{0}, make([]byte, 256)...)),
		"nistp256": "ecdsa-sha2-nistp256 " + encodeSSHBlob("ecdsa-sha2-nistp256", []byte("nistp256"), ecPoint(t, ecdh.P256())),
		"nistp384": "ecdsa-sha2-nistp384 " + encodeSSHBlob("ecdsa-sha2-nistp384", []byte("nistp384"), ecPoint(t, ecdh.P384())),
		"nistp521": "ecdsa-sha2-nistp521 " + encodeSSHBlob("ecdsa-sha2-nistp521", []byte("nistp521"), ecPoint(t, ecdh.P521())),
	}
	for name, key := range keys {
		got, err := normalizeHostPublicKey(key + " root@test")
		if err != nil {
			t.Fatalf("%s: normalizeHostPublicKey: %v", name, err)
		}
		if got != key {
			t.Fatalf("%s: got %q, want %q", name, got, key)
		}
	}
}

func TestNormalizeHostPublicKeyRejectsMalformedKeyBodies(t *testing.T) {
	t.Parallel()

	keys := map[string]string{
		"ed25519 missing key":   "ssh-ed25519 " + encodeSSHBlob("ssh-ed25519"),
		"ed25519 short key":     "ssh-ed25519 " + encodeSSHBlob("ssh-ed25519", make([]byte, 31)),
		"ed25519 trailing data": "ssh-ed25519 " + encodeSSHBlob("ssh-ed25519", make([]byte, 32), nil),
		"rsa missing modulus":   "ssh-rsa " + encodeSSHBlob("ssh-rsa", []byte{1, 0, 1}),
		"ecdsa curve mismatch":  "ecdsa-sha2-nistp256 " + encodeSSHBlob("ecdsa-sha2-nistp256", []byte("nistp384"), ecPoint(t, ecdh.P256())),
		"ecdsa short point":     "ecdsa-sha2-nistp256 " + encodeSSHBlob("ecdsa-sha2-nistp256", []byte("nistp256"), ecPoint(t, ecdh.P256())[:64]),
		"ecdsa off curve":       "ecdsa-sha2-nistp256 " + encodeSSHBlob("ecdsa-sha2-nistp256", []byte("nistp256"), append([]byte{0x04}, make([]byte, 64)...)),
		"ecdsa compressed":      "ecdsa-sha2-nistp256 " + encodeSSHBlob("ecdsa-sha2-nistp256", []byte("nistp256"), append([]byte{0x02}, make([]byte, 32)...)),
	}
	for name, key := range keys {
		if _, err := normalizeHostPublicKey(key); err == nil {
			t.Fatalf("%s: expected malformed host key to be rejected", name)
		}
	}
}

func encodeSSHBlob(algorithm string, fields ...[]byte) string {
	var blob []byte
	for _, field := range append([][]byte{[]byte(algorithm)}, fields...) {
		blob = binary.BigEndian.AppendUint32(blob, uint32(len(field)))
		blob = append(blob, field...)
	}
	return base64.StdEncoding.EncodeToString(blob)
}

func ecPoint(t *testing.T, curve ecdh.Curve) []byte {
	t.Helper()
	key, err := curve.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ecdh key: %v", err)
	}
	return key.PublicKey().Bytes()
}
