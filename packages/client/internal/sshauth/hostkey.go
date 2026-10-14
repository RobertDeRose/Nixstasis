package sshauth

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strings"
)

// Only Ed25519 host keys are reported. Its fixed 32-byte encoding is fully
// validated here, so a malformed key cannot be enrolled and pinned.
const hostKeyAlgorithm = "ssh-ed25519"

var defaultHostPublicKeyPaths = []string{
	"/etc/ssh/ssh_host_ed25519_key.pub",
}

// LoadHostPublicKey returns the sshd Ed25519 host public key. Comments are
// removed before transmission.
func LoadHostPublicKey() (string, error) {
	return LoadHostPublicKeyFrom(defaultHostPublicKeyPaths...)
}

// LoadHostPublicKeyFrom is the testable form of LoadHostPublicKey.
func LoadHostPublicKeyFrom(paths ...string) (string, error) {
	var lastErr error
	for _, path := range paths {
		// #nosec G304 -- Production paths are fixed sshd public-key locations; alternate paths are supplied only by tests.
		data, err := os.ReadFile(path)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			lastErr = err
			continue
		}

		normalized, err := normalizeHostPublicKey(string(data))
		if err != nil {
			lastErr = fmt.Errorf("%s: %w", path, err)
			continue
		}
		return normalized, nil
	}

	if lastErr != nil {
		return "", lastErr
	}
	return "", os.ErrNotExist
}

func normalizeHostPublicKey(value string) (string, error) {
	fields := strings.Fields(value)
	if len(fields) < 2 {
		return "", errors.New("invalid SSH host public key")
	}

	algorithm := fields[0]
	if algorithm != hostKeyAlgorithm {
		return "", fmt.Errorf("unsupported SSH host key algorithm %q", algorithm)
	}

	decoded, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil {
		return "", errors.New("invalid SSH host public key encoding")
	}

	embeddedAlgorithm, body, err := readSSHField(decoded)
	if err != nil || string(embeddedAlgorithm) != algorithm {
		return "", errors.New("SSH host key algorithm does not match key blob")
	}
	if err := validateKeyBody(algorithm, body); err != nil {
		return "", fmt.Errorf("invalid SSH host public key: %w", err)
	}

	return algorithm + " " + fields[1], nil
}
