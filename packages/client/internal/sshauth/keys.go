// Package sshauth provides local, in-memory SSH public-key authorization.
package sshauth

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"strings"
)

const (
	// DefaultSocketPath is the trusted local IPC path used by the OpenSSH helper.
	DefaultSocketPath = "/run/nixstasis/ssh-authority.sock"

	// PayloadContentType identifies dynamic ssh_authorize command payloads.
	PayloadContentType = "application/vnd.nixstasis.ssh-authorize+json;version=1"

	// RevokePayloadContentType identifies ssh_revoke command payloads sent on
	// terminal close to drop the in-memory authorization early.
	RevokePayloadContentType = "application/vnd.nixstasis.ssh-revoke+json;version=1"
)

const maxAuthorizedKeyLine = 16 * 1024

// AuthorizedKey is a canonical OpenSSH public key without comment/options.
type AuthorizedKey struct {
	Type        string
	Blob        string
	Fingerprint string
	Line        string
}

// ParseAuthorizedKeyLine parses an authorized_keys-style public key line.
func ParseAuthorizedKeyLine(line string) (AuthorizedKey, error) {
	line = strings.TrimSpace(line)
	if line == "" {
		return AuthorizedKey{}, errors.New("missing public key")
	}
	if len(line) > maxAuthorizedKeyLine {
		return AuthorizedKey{}, errors.New("public key is too large")
	}
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return AuthorizedKey{}, errors.New("malformed public key")
	}
	return ParseOfferedKey(fields[0], fields[1])
}

// ParseOfferedKey parses the key type and base64 key blob passed by OpenSSH's %t and %k tokens.
func ParseOfferedKey(keyType, keyBlob string) (AuthorizedKey, error) {
	keyType = strings.TrimSpace(keyType)
	keyBlob = strings.TrimSpace(keyBlob)
	if keyType == "" || keyBlob == "" {
		return AuthorizedKey{}, errors.New("missing public key")
	}
	if len(keyType)+len(keyBlob) > maxAuthorizedKeyLine {
		return AuthorizedKey{}, errors.New("public key is too large")
	}
	blob, err := decodeKeyBlob(keyBlob)
	if err != nil {
		return AuthorizedKey{}, fmt.Errorf("malformed public key: %w", err)
	}
	embeddedType, err := readSSHString(blob)
	if err != nil {
		return AuthorizedKey{}, fmt.Errorf("malformed public key: %w", err)
	}
	if embeddedType != keyType {
		return AuthorizedKey{}, errors.New("public key type does not match blob")
	}
	canonicalBlob := base64.RawStdEncoding.EncodeToString(blob)
	sum := sha256.Sum256(blob)
	return AuthorizedKey{
		Type:        keyType,
		Blob:        canonicalBlob,
		Fingerprint: "SHA256:" + base64.RawStdEncoding.EncodeToString(sum[:]),
		Line:        keyType + " " + canonicalBlob,
	}, nil
}

func decodeKeyBlob(keyBlob string) ([]byte, error) {
	if blob, err := base64.RawStdEncoding.DecodeString(keyBlob); err == nil {
		return blob, nil
	}
	return base64.StdEncoding.DecodeString(keyBlob)
}

func readSSHString(blob []byte) (string, error) {
	if len(blob) < 4 {
		return "", errors.New("short key blob")
	}
	length := binary.BigEndian.Uint32(blob[:4])
	if length == 0 || int(length) > len(blob)-4 {
		return "", errors.New("invalid key type length")
	}
	return string(blob[4 : 4+length]), nil
}
