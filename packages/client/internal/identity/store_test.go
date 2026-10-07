package identity

import (
	"errors"
	"os"
	"testing"
)

func TestLoadUUIDReturnsErrNoIdentityWhenFileMissing(t *testing.T) {
	path := t.TempDir() + "/id"

	_, err := NewStore(path).LoadUUID()
	if !errors.Is(err, ErrNoIdentity) {
		t.Fatalf("expected ErrNoIdentity, got %v", err)
	}
}

func TestLoadUUIDRejectsEmptyIdentityFile(t *testing.T) {
	path := t.TempDir() + "/id"
	if err := os.WriteFile(path, []byte("\n"), 0o600); err != nil {
		t.Fatalf("write identity file: %v", err)
	}

	_, err := NewStore(path).LoadUUID()
	if err == nil {
		t.Fatalf("expected empty identity file error")
	}
}

func TestLoadUUIDRejectsInvalidIdentityFile(t *testing.T) {
	path := t.TempDir() + "/id"
	if err := os.WriteFile(path, []byte("not-a-uuid"), 0o600); err != nil {
		t.Fatalf("write identity file: %v", err)
	}

	_, err := NewStore(path).LoadUUID()
	if err == nil {
		t.Fatalf("expected invalid UUID error")
	}
}

func TestLoadUUIDNormalizesValidIdentity(t *testing.T) {
	path := t.TempDir() + "/id"
	if err := os.WriteFile(path, []byte("A0EBD0B2-63E6-4A74-8B8C-7084C18C45E8\n"), 0o600); err != nil {
		t.Fatalf("write identity file: %v", err)
	}

	uuid, err := NewStore(path).LoadUUID()
	if err != nil {
		t.Fatalf("LoadUUID() error = %v", err)
	}
	if uuid != "a0ebd0b2-63e6-4a74-8b8c-7084c18c45e8" {
		t.Fatalf("LoadUUID() = %q", uuid)
	}
}

func TestStoreRemoveDeletesCredentials(t *testing.T) {
	path := t.TempDir() + "/registration"
	store := NewStore(path)
	credentials := Credentials{UUID: "a0ebd0b2-63e6-4a74-8b8c-7084c18c45e8", Token: "proof"}

	if err := store.Save(credentials); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	if err := store.Remove(); err != nil {
		t.Fatalf("Remove() error = %v", err)
	}
	if _, err := store.Load(); !errors.Is(err, ErrNoIdentity) {
		t.Fatalf("Load() after Remove() error = %v, want ErrNoIdentity", err)
	}
}
