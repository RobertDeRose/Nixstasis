package identity

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// Store handles persistence of the Device ID.
type Store struct {
	path string
}

// NewStore creates a new Store instance.
func NewStore(path string) *Store {
	return &Store{path: path}
}

// LoadUUID reads the UUID from the storage file.
// Returns empty string if file doesn't exist.
func (s *Store) LoadUUID() (string, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

// SaveUUID writes the UUID to the storage file.
// Creates directories if they don't exist.
func (s *Store) SaveUUID(uuid string) error {
	if uuid == "" {
		return errors.New("cannot save empty UUID")
	}

	dir := filepath.Dir(s.path)
	// Use 0750 for directory permissions (gosec G301)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return err
	}

	// Write to temp file and rename for atomic write
	tmpFile := s.path + ".tmp"
	// Use 0o644 octal literal (gocritic)
	if err := os.WriteFile(tmpFile, []byte(uuid), 0o644); err != nil {
		return err
	}

	return os.Rename(tmpFile, s.path)
}
