// Package commandpolicy persists the last server-delivered command policy.
package commandpolicy

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ErrNoPolicy reports that no persisted command policy exists yet.
var ErrNoPolicy = errors.New("no command policy file found")

// State is the persisted server-delivered command policy.
type State struct {
	Version  string            `json:"version"`
	Commands map[string]string `json:"commands"`
}

// Store reads and writes the persisted command policy file.
type Store struct {
	path string
}

// NewStore creates a command policy store rooted at path.
func NewStore(path string) *Store {
	return &Store{path: path}
}

// Load reads the persisted command policy.
func (s *Store) Load() (State, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return State{}, ErrNoPolicy
		}
		return State{}, err
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return State{}, err
	}
	return normalize(state)
}

// Save atomically persists a command policy.
func (s *Store) Save(state State) error {
	normalized, err := normalize(state)
	if err != nil {
		return err
	}

	data, err := json.Marshal(normalized)
	if err != nil {
		return err
	}

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	tmp, err := os.CreateTemp(dir, filepath.Base(s.path)+".tmp.*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	success := false
	defer func() {
		if !success {
			if err := os.Remove(tmpPath); err != nil && !os.IsNotExist(err) {
				fmt.Fprintf(os.Stderr, "failed to remove command policy temp file: %v\n", err)
			}
		}
	}()

	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, s.path); err != nil {
		return err
	}
	if err := syncDir(dir); err != nil {
		return err
	}
	success = true
	return nil
}

func syncDir(path string) error {
	dir, err := os.Open(path) // #nosec G304 -- store directory path is application-controlled.
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func normalize(state State) (State, error) {
	state.Version = strings.TrimSpace(state.Version)
	if state.Version == "" {
		return State{}, errors.New("policy version is required")
	}
	if len(state.Commands) == 0 {
		return State{}, errors.New("command policy is empty")
	}

	normalized := make(map[string]string, len(state.Commands))
	for name, path := range state.Commands {
		name = strings.TrimSpace(name)
		path = strings.TrimSpace(path)
		if name == "" {
			return State{}, errors.New("command name must not be empty")
		}
		if path == "" {
			return State{}, fmt.Errorf("command path must not be empty for %s", name)
		}
		normalized[name] = path
	}
	state.Commands = normalized
	return state, nil
}
