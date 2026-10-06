package identity

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestEnrollmentStoreBeforeUUIDAssignment(t *testing.T) {
	path := filepath.Join(t.TempDir(), "registration")
	store := NewStore(path)
	if _, err := store.LoadEnrollment(); !errors.Is(err, ErrNoIdentity) {
		t.Fatalf("missing enrollment error = %v", err)
	}
	enrollment := Enrollment{Token: NewToken(), ReplacementToken: NewToken()}
	if err := store.SaveEnrollment(enrollment); err != nil {
		t.Fatal(err)
	}
	loaded, err := NewStore(path).LoadEnrollment()
	if err != nil {
		t.Fatal(err)
	}
	if loaded != enrollment {
		t.Fatal("stored enrollment does not match prepared credentials")
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("enrollment permissions = %o, want 600", info.Mode().Perm())
	}
	if _, err := store.Load(); err == nil {
		t.Fatal("unassigned enrollment must not be usable as a runtime identity")
	}
}
