package sshauth

import (
	"encoding/base64"
	"encoding/binary"
	"strings"
	"testing"
	"time"
)

const testAuthorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINvzG0y0QHdLAX8s791E20Tbk2UrOUAe6GmmVcJvHIPn user@example"

func TestParseOfferedKeyCanonicalizesValidKey(t *testing.T) {
	key, err := ParseAuthorizedKeyLine(testAuthorizedKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}

	decoded, err := base64.RawStdEncoding.DecodeString(key.Blob)
	if err != nil {
		t.Fatalf("DecodeString() error = %v", err)
	}
	got, err := ParseOfferedKey(key.Type, base64.StdEncoding.EncodeToString(decoded))
	if err != nil {
		t.Fatalf("ParseOfferedKey() error = %v", err)
	}
	if got.Type != key.Type || got.Blob != key.Blob || got.Line != key.Line {
		t.Fatalf("canonical key = %#v, want %#v", got, key)
	}
}

func TestParseOfferedKeyRejectsUnsupportedKeyType(t *testing.T) {
	key, err := ParseAuthorizedKeyLine(testAuthorizedKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}

	if _, err := ParseOfferedKey("not-an-open-ssh-key", key.Blob); err == nil {
		t.Fatal("ParseOfferedKey() accepted unsupported key type")
	}
}

func TestParseOfferedKeyRejectsOversizedKeyInput(t *testing.T) {
	if _, err := ParseOfferedKey("ssh-ed25519", strings.Repeat("A", maxAuthorizedKeyLine)); err == nil {
		t.Fatal("ParseOfferedKey() accepted oversized key input")
	}
}

func TestParseOfferedKeyRejectsMismatchedEmbeddedType(t *testing.T) {
	key, err := ParseAuthorizedKeyLine(testAuthorizedKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}

	if _, err := ParseOfferedKey("ssh-rsa", key.Blob); err == nil {
		t.Fatal("ParseOfferedKey() accepted mismatched embedded key type")
	}
}

func TestMaxAuthorizationTTLMatchesDocumentedContract(t *testing.T) {
	if MaxAuthorizationTTL != 3_600*time.Second {
		t.Fatalf("MaxAuthorizationTTL = %s, want one hour", MaxAuthorizationTTL)
	}
}

func TestParseOfferedKeyAcceptsStructurallyValidRSAKey(t *testing.T) {
	blob := sshBlob("ssh-rsa", sshField([]byte{1, 0, 1}), sshField([]byte(strings.Repeat("N", 64))))
	if _, err := ParseOfferedKey("ssh-rsa", base64.RawStdEncoding.EncodeToString(blob)); err != nil {
		t.Fatalf("ParseOfferedKey() error = %v", err)
	}
}

func TestParseOfferedKeyRejectsTruncatedRSAKeyBody(t *testing.T) {
	blob := sshBlob("ssh-rsa", sshField([]byte{1, 0, 1}))
	if _, err := ParseOfferedKey("ssh-rsa", base64.RawStdEncoding.EncodeToString(blob)); err == nil {
		t.Fatal("ParseOfferedKey() accepted a truncated RSA key body")
	}
}

func TestParseOfferedKeyRejectsTruncatedKeyBody(t *testing.T) {
	blob := make([]byte, 0, 20)
	blob = append(blob, 0, 0, 0, byte(len("ssh-ed25519")))
	blob = append(blob, []byte("ssh-ed25519")...)
	blob = append(blob, 0, 0, 0, 32, 1)

	if _, err := ParseOfferedKey("ssh-ed25519", base64.RawStdEncoding.EncodeToString(blob)); err == nil {
		t.Fatal("ParseOfferedKey() accepted a truncated key body")
	}
}

func TestParseOfferedKeyRejectsTrailingKeyData(t *testing.T) {
	key, err := ParseAuthorizedKeyLine(testAuthorizedKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	blob, err := base64.RawStdEncoding.DecodeString(key.Blob)
	if err != nil {
		t.Fatalf("DecodeString() error = %v", err)
	}
	blob = append(blob, 0)

	if _, err := ParseOfferedKey(key.Type, base64.RawStdEncoding.EncodeToString(blob)); err == nil {
		t.Fatal("ParseOfferedKey() accepted trailing key data")
	}
}

func sshBlob(keyType string, fields ...[]byte) []byte {
	blob := sshField([]byte(keyType))
	for _, field := range fields {
		blob = append(blob, field...)
	}
	return blob
}

func sshField(field []byte) []byte {
	result := make([]byte, 4, 4+len(field))
	binary.BigEndian.PutUint32(result, uint32(len(field)))
	return append(result, field...)
}
