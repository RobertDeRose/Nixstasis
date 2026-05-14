package identity

import (
	"encoding/json/v2"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$`)

// ErrNoIdentity is returned when no identity file exists on disk.
var ErrNoIdentity = errors.New("no device identity file found")

// Credentials contains the runtime identity assigned by the server.
type Credentials struct {
	UUID  string `json:"uuid"`
	Token string `json:"token,omitempty"`
}

// Store handles persistence of the Device ID.
type Store struct {
	path string
}

func syncDir(path string) error {
	dir, err := os.Open(path) // #nosec G304 -- store directory path is provided by application configuration.
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

// NewStore creates a new Store instance.
func NewStore(path string) *Store {
	return &Store{path: path}
}

// LoadUUID reads the UUID from the storage file.
// Returns ErrNoIdentity if the file doesn't exist.
func (s *Store) LoadUUID() (string, error) {
	credentials, err := s.Load()
	if err != nil {
		return "", err
	}
	return credentials.UUID, nil
}

// Load reads the persisted runtime credentials. Legacy plain UUID files are supported.
func (s *Store) Load() (Credentials, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return Credentials{}, ErrNoIdentity
		}
		return Credentials{}, err
	}

	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return Credentials{}, errors.New("identity file is empty")
	}

	var credentials Credentials
	if strings.HasPrefix(trimmed, "{") {
		if err := json.Unmarshal([]byte(trimmed), &credentials); err != nil {
			return Credentials{}, err
		}
		return normalizeCredentials(credentials)
	}

	return normalizeCredentials(Credentials{UUID: trimmed})
}

// SaveUUID writes the UUID to the storage file.
// Creates directories if they don't exist.
func (s *Store) SaveUUID(uuid string) error {
	return s.Save(Credentials{UUID: uuid})
}

// Save writes runtime credentials using owner-only file permissions.
func (s *Store) Save(credentials Credentials) error {
	normalized, err := normalizeCredentials(credentials)
	if err != nil {
		return err
	}

	data, err := json.Marshal(normalized)
	if err != nil {
		return err
	}

	return s.write(data)
}

func normalizeCredentials(credentials Credentials) (Credentials, error) {
	uuid := strings.TrimSpace(credentials.UUID)
	if uuid == "" {
		return Credentials{}, errors.New("identity file is empty")
	}
	if !uuidPattern.MatchString(uuid) {
		return Credentials{}, fmt.Errorf("identity file contains invalid UUID %q", uuid)
	}
	credentials.UUID = strings.ToLower(uuid)
	credentials.Token = strings.TrimSpace(credentials.Token)
	return credentials, nil
}

func (s *Store) write(data []byte) error {
	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	tmpFile, err := os.CreateTemp(dir, filepath.Base(s.path)+".tmp.*")
	if err != nil {
		return err
	}
	tmpPath := tmpFile.Name()

	// Clean up the temp file on any failure path.
	success := false
	defer func() {
		if !success {
			if err := os.Remove(tmpPath); err != nil && !os.IsNotExist(err) {
				fmt.Fprintf(os.Stderr, "failed to remove identity temp file: %v\n", err)
			}
		}
	}()

	if err := tmpFile.Chmod(0o600); err != nil {
		tmpFile.Close()
		return err
	}
	if _, err := tmpFile.Write(data); err != nil {
		tmpFile.Close()
		return err
	}
	if err := tmpFile.Sync(); err != nil {
		tmpFile.Close()
		return err
	}
	if err := tmpFile.Close(); err != nil {
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
