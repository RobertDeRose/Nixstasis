package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/sshauth"
)

const helperTestPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINvzG0y0QHdLAX8s791E20Tbk2UrOUAe6GmmVcJvHIPn user@example"

func TestAuthorizedKeyLineRejectsInvalidArgumentsBeforeIPC(t *testing.T) {
	t.Setenv(envSSHAuthoritySocket, filepath.Join(t.TempDir(), "missing.sock"))

	if _, err := authorizedKeyLine(context.Background(), "nixstasis-support", "not-a-key", "blob"); err == nil {
		t.Fatal("authorizedKeyLine() accepted an invalid key type")
	}
}

func TestAuthorizedKeyLineReturnsEmptyForDeniedResponse(t *testing.T) {
	key, err := sshauth.ParseAuthorizedKeyLine(helperTestPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	startHelperResponseServer(t, sshauth.QueryResponse{Authorized: false})

	got, err := authorizedKeyLine(context.Background(), "nixstasis-support", key.Type, key.Blob)
	if err != nil {
		t.Fatalf("authorizedKeyLine() error = %v", err)
	}
	if got != "" {
		t.Fatalf("authorizedKeyLine() = %q, want empty output", got)
	}
}

func TestAuthorizedKeyLineReturnsEmptyForMissingSocket(t *testing.T) {
	key, err := sshauth.ParseAuthorizedKeyLine(helperTestPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	t.Setenv(envSSHAuthoritySocket, filepath.Join("/tmp", "nxa-missing-socket"))

	got, err := authorizedKeyLine(context.Background(), "nixstasis-support", key.Type, key.Blob)
	if err != nil {
		t.Fatalf("authorizedKeyLine() error = %v", err)
	}
	if got != "" {
		t.Fatalf("authorizedKeyLine() = %q, want empty output", got)
	}
}

func TestAuthorizedKeyLineReturnsEmptyForTimedOutSocket(t *testing.T) {
	path := filepath.Join("/tmp", "nxa-timeout-socket")
	listener, err := new(net.ListenConfig).Listen(context.Background(), "unix", path)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	t.Cleanup(func() {
		_ = listener.Close()
		_ = os.Remove(path)
	})
	t.Setenv(envSSHAuthoritySocket, path)
	go func() {
		conn, err := listener.Accept()
		if err == nil {
			defer conn.Close()
			<-time.After(100 * time.Millisecond)
		}
	}()

	key, err := sshauth.ParseAuthorizedKeyLine(helperTestPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	got, err := authorizedKeyLine(ctx, "nixstasis-support", key.Type, key.Blob)
	if err != nil {
		t.Fatalf("authorizedKeyLine() error = %v", err)
	}
	if got != "" {
		t.Fatalf("authorizedKeyLine() = %q, want empty output", got)
	}
}

func TestAuthorizedKeyLineReturnsCanonicalOfferedKey(t *testing.T) {
	key, err := sshauth.ParseAuthorizedKeyLine(helperTestPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	path := startHelperResponseServer(t, sshauth.QueryResponse{
		Authorized: true,
		KeyType:    key.Type,
		KeyBlob:    key.Blob,
	})

	got, err := authorizedKeyLine(context.Background(), "nixstasis-support", key.Type, key.Blob)
	if err != nil {
		t.Fatalf("authorizedKeyLine() error = %v", err)
	}
	if got != key.Line {
		t.Fatalf("authorizedKeyLine() = %q, want %q", got, key.Line)
	}
	_ = path
}

func TestAuthorizedKeyLineRejectsMismatchedAuthorizedResponse(t *testing.T) {
	key, err := sshauth.ParseAuthorizedKeyLine(helperTestPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	differentBlob := base64.RawStdEncoding.EncodeToString(validEd25519Blob(2))
	startHelperResponseServer(t, sshauth.QueryResponse{
		Authorized: true,
		KeyType:    key.Type,
		KeyBlob:    differentBlob,
	})

	if _, err := authorizedKeyLine(context.Background(), "nixstasis-support", key.Type, key.Blob); err == nil {
		t.Fatal("authorizedKeyLine() accepted a mismatched authorized response")
	}
}

func validEd25519Blob(seed byte) []byte {
	blob := make([]byte, 0, 51)
	blob = append(blob, 0, 0, 0, 11)
	blob = append(blob, []byte("ssh-ed25519")...)
	blob = append(blob, 0, 0, 0, 32)
	return append(blob, bytes.Repeat([]byte{seed}, 32)...)
}

func startHelperResponseServer(t *testing.T, response sshauth.QueryResponse) string {
	t.Helper()
	temporaryFile, err := os.CreateTemp("/tmp", "nxa-")
	if err != nil {
		t.Fatalf("CreateTemp() error = %v", err)
	}
	path := temporaryFile.Name() + ".sock"
	if err := temporaryFile.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	if err := os.Remove(temporaryFile.Name()); err != nil {
		t.Fatalf("Remove() error = %v", err)
	}
	listener, err := new(net.ListenConfig).Listen(context.Background(), "unix", path)
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	t.Cleanup(func() {
		_ = listener.Close()
		_ = os.Remove(path)
	})
	t.Setenv(envSSHAuthoritySocket, path)

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(time.Second))
		var request sshauth.QueryRequest
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			return
		}
		_ = json.NewEncoder(conn).Encode(response)
	}()
	return path
}
