package commandpolicy

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestStoreSaveLoadRoundTrip(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "command-policy.json"))
	want := State{Version: "v1", Commands: map[string]string{"safe": "/bin/echo"}}
	if err := store.Save(want); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	got, err := store.Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got.Version != want.Version || got.Commands["safe"] != want.Commands["safe"] {
		t.Fatalf("Load() = %+v, want %+v", got, want)
	}
}

func TestStoreLoadMissingReturnsErrNoPolicy(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "missing.json"))
	_, err := store.Load()
	if !errors.Is(err, ErrNoPolicy) {
		t.Fatalf("Load() error = %v, want ErrNoPolicy", err)
	}
}
