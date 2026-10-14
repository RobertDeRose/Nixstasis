package identity

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json/v2"
	"errors"
	"fmt"
	"os"
)

// Enrollment holds credentials durably prepared before a registration request.
// UUID is absent until the first response; Token is the proof and ReplacementToken
// is the proposed runtime token, retained unchanged across retries.
type Enrollment struct {
	UUID             string `json:"uuid,omitempty"`
	Token            string `json:"token"`
	ReplacementToken string `json:"replacement_token,omitempty"`
}

// NewToken generates a 256-bit, unpadded base64url credential.
func NewToken() string {
	var token [32]byte
	_, _ = rand.Read(token[:]) // crypto/rand.Read always fills the buffer or terminates the process.
	return base64.RawURLEncoding.EncodeToString(token[:])
}

// LoadEnrollment also accepts the former UUID/token registration recovery file.
func (s *Store) LoadEnrollment() (Enrollment, error) {
	data, err := os.ReadFile(s.path) // #nosec G304 -- path is provided by application configuration.
	if errors.Is(err, os.ErrNotExist) {
		return Enrollment{}, ErrNoIdentity
	}
	if err != nil {
		return Enrollment{}, err
	}
	var enrollment Enrollment
	if err := json.Unmarshal(data, &enrollment); err != nil {
		return Enrollment{}, err
	}
	if err := validateEnrollment(enrollment); err != nil {
		return Enrollment{}, err
	}
	return enrollment, nil
}

// SaveEnrollment uses the same atomic, owner-only storage as runtime credentials.
func (s *Store) SaveEnrollment(enrollment Enrollment) error {
	if err := validateEnrollment(enrollment); err != nil {
		return err
	}
	data, err := json.Marshal(enrollment)
	if err != nil {
		return err
	}
	return s.write(data)
}

func validateEnrollment(enrollment Enrollment) error {
	if enrollment.UUID != "" && !uuidPattern.MatchString(enrollment.UUID) {
		return fmt.Errorf("registration file contains invalid UUID %q", enrollment.UUID)
	}
	if enrollment.Token == "" {
		return errors.New("registration file contains no proof")
	}
	return nil
}
