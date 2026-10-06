package sshauth

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"strings"
)

var defaultHostPublicKeyPaths = []string{
	"/etc/ssh/ssh_host_ed25519_key.pub",
	"/etc/ssh/ssh_host_ecdsa_key.pub",
	"/etc/ssh/ssh_host_rsa_key.pub",
}

var allowedHostKeyAlgorithms = map[string]struct{}{
	"ssh-ed25519":         {},
	"ssh-rsa":             {},
	"ecdsa-sha2-nistp256": {},
	"ecdsa-sha2-nistp384": {},
	"ecdsa-sha2-nistp521": {},
}

// LoadHostPublicKey returns the first valid OpenSSH host public key from the
// standard sshd host-key locations. Comments are removed before transmission.
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
	if _, ok := allowedHostKeyAlgorithms[algorithm]; !ok {
		return "", fmt.Errorf("unsupported SSH host key algorithm %q", algorithm)
	}

	decoded, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil || len(decoded) < 4 {
		return "", errors.New("invalid SSH host public key encoding")
	}

	nameLength := int(binary.BigEndian.Uint32(decoded[:4]))
	if nameLength <= 0 || len(decoded) < 4+nameLength || string(decoded[4:4+nameLength]) != algorithm {
		return "", errors.New("SSH host key algorithm does not match key blob")
	}

	return algorithm + " " + fields[1], nil
}
