package commands

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/sshauth"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

const testPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINvzG0y0QHdLAX8s791E20Tbk2UrOUAe6GmmVcJvHIPn user@example"

func TestGivenDuplicateCommandID_WhenExecuteBatch_ThenLaterDuplicateFails(t *testing.T) {
	handler := NewHandler("")
	commands := []transport.CommandRequest{
		{CommandID: "cmd-1", Type: "list_scripts"},
		{CommandID: "cmd-1", Type: "list_scripts"},
	}

	results := handler.ExecuteBatch(context.Background(), commands)
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusOK {
		t.Fatalf("expected first command to succeed, got %s", results[0].Status)
	}
	if results[1].Status != transport.CommandStatusFailed || results[1].Error != "duplicate_command_id" {
		t.Fatalf("expected duplicate to fail with duplicate_command_id, got status=%s error=%s", results[1].Status, results[1].Error)
	}
}

func TestGivenOversizedCommandList_WhenExecuteBatch_ThenOnlyMaxAccepted(t *testing.T) {
	handler := NewHandler("")
	commands := make([]transport.CommandRequest, MaxCommandsPerPoll+5)
	for i := range commands {
		commands[i] = transport.CommandRequest{CommandID: fmt.Sprintf("cmd-%d", i), Type: "list_scripts"}
	}

	results := handler.ExecuteBatch(context.Background(), commands)

	if len(results) != MaxCommandsPerPoll {
		t.Fatalf("expected %d results, got %d", MaxCommandsPerPoll, len(results))
	}
}

func TestGivenExpiredContext_WhenExecuteBatch_ThenTimeoutReported(t *testing.T) {
	handler := NewHandler("")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	commands := []transport.CommandRequest{
		{CommandID: "cmd-2", Type: "list_scripts"},
	}

	results := handler.ExecuteBatch(ctx, commands)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusFailed || results[0].Error != "timeout" {
		t.Fatalf("expected timeout failure, got status=%s error=%s", results[0].Status, results[0].Error)
	}
}

func TestGivenPathTraversalScriptName_WhenInstallScript_ThenFails(t *testing.T) {
	handler := NewHandler(t.TempDir())
	content := strings.TrimSpace(`---
name: "../evil"
version: "1"
schema:
  type: object
---
def main():
    return {}
`)

	results := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-install",
		Type:      "install_script",
		Payload:   &transport.CommandPayload{Data: content},
	}})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusFailed {
		t.Fatalf("expected install to fail, got status=%s", results[0].Status)
	}
	if !strings.Contains(results[0].Error, "invalid script name") {
		t.Fatalf("expected invalid script name error, got %q", results[0].Error)
	}
}

func TestGivenConfiguredScriptsDir_WhenInstallScript_ThenWritesThere(t *testing.T) {
	scriptsDir := t.TempDir()
	handler := NewHandler(scriptsDir)
	content := strings.TrimSpace(`---
name: server_installed
version: "1"
schema:
  type: object
---
def main():
    return {}
`)

	results := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-install",
		Type:      "install_script",
		Payload:   &transport.CommandPayload{Data: content},
	}})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusOK {
		t.Fatalf("expected install to succeed, got status=%s error=%s", results[0].Status, results[0].Error)
	}
	installedPath := filepath.Join(scriptsDir, "server_installed_1.stary")
	if _, err := os.Stat(installedPath); err != nil {
		t.Fatalf("expected script installed in configured scripts dir: %v", err)
	}
}

func TestGivenInstallCommitAndExpiredContext_WhenExecuteBatch_ThenSuccessReported(t *testing.T) {
	scriptsDir := t.TempDir()
	handler := NewHandler(scriptsDir)
	content := strings.TrimSpace(`---
name: server_installed
version: "1"
schema:
  type: object
---
	def main():
	    return {}
`)

	originalHook := afterCommandCommitHook
	defer func() { afterCommandCommitHook = originalHook }()
	ctx, cancel := context.WithCancel(context.Background())
	afterCommandCommitHook = cancel
	result := handler.installScript(ctx, "cmd-install", nil, &transport.CommandPayload{Data: content})

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected install_script to succeed once committed, got status=%s error=%s", result.Status, result.Error)
	}
}

func TestGivenPathTraversalScriptVersion_WhenRemoveScript_ThenFails(t *testing.T) {
	handler := NewHandler(t.TempDir())
	results := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-remove",
		Type:      "remove_script",
		Args:      []string{"safe", "../v1"},
	}})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusFailed {
		t.Fatalf("expected remove to fail, got status=%s", results[0].Status)
	}
	if !strings.Contains(results[0].Error, "invalid script version") {
		t.Fatalf("expected invalid script version error, got %q", results[0].Error)
	}
}

func TestSSHAuthorizeStoresDynamicKeyInMemory(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", store)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-dynamic",
		Type:      "ssh_authorize",
		PublicKey: testPublicKey,
		Payload: &transport.CommandPayload{
			ContentType: sshauth.PayloadContentType,
			Name:        "session-1",
			Data:        `{"target_user":"nixstasis-support","ttl_seconds":300,"session_ref":"session-1"}`,
		},
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected dynamic ssh_authorize to succeed, got %s: %s", result.Status, result.Error)
	}
	key, err := sshauth.ParseAuthorizedKeyLine(testPublicKey)
	if err != nil {
		t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
	}
	if _, ok := store.Authorize("nixstasis-support", key.Type, key.Blob); !ok {
		t.Fatal("dynamic key was not stored")
	}
}

func TestSSHAuthorizeRejectsInvalidDynamicPayloads(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", store)
	cases := []struct {
		name    string
		payload string
	}{
		{name: "invalid ttl", payload: `{"target_user":"nixstasis-support","ttl_seconds":0,"session_ref":"session-1"}`},
		{name: "wrong user", payload: `{"target_user":"root","ttl_seconds":300,"session_ref":"session-1"}`},
		{name: "missing session", payload: `{"target_user":"nixstasis-support","ttl_seconds":300}`},
		{name: "malformed json", payload: `{`},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
				CommandID: "cmd-" + tc.name,
				Type:      "ssh_authorize",
				PublicKey: testPublicKey,
				Payload: &transport.CommandPayload{
					ContentType: sshauth.PayloadContentType,
					Data:        tc.payload,
				},
			}})[0]
			if result.Status != transport.CommandStatusFailed {
				t.Fatalf("expected failure, got %s", result.Status)
			}
		})
	}
}

func TestSSHRevokeRemovesStoredAuthorization(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", store)

	authorize := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-auth",
		Type:      "ssh_authorize",
		PublicKey: testPublicKey,
		Payload: &transport.CommandPayload{
			ContentType: sshauth.PayloadContentType,
			Name:        "session-revoke",
			Data:        `{"target_user":"nixstasis-support","ttl_seconds":300,"session_ref":"session-revoke"}`,
		},
	}})[0]
	if authorize.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_authorize ok, got %s: %s", authorize.Status, authorize.Error)
	}
	if store.Len() != 1 {
		t.Fatalf("store len = %d, want 1", store.Len())
	}

	revoke := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-revoke",
		Type:      "ssh_revoke",
		Payload: &transport.CommandPayload{
			ContentType: sshauth.RevokePayloadContentType,
			Name:        "session-revoke",
		},
	}})[0]
	if revoke.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_revoke ok, got %s: %s", revoke.Status, revoke.Error)
	}
	output, ok := revoke.Output.(map[string]any)
	if !ok {
		t.Fatalf("revoke output = %v, want map", revoke.Output)
	}
	if got, want := output["mode"], "dynamic_ssh_revoke"; got != want {
		t.Fatalf("output mode = %v, want %v", got, want)
	}
	if got, want := output["session_ref"], "session-revoke"; got != want {
		t.Fatalf("output session_ref = %v, want %v", got, want)
	}
	if got, _ := output["revoked"].(int); got != 1 {
		t.Fatalf("output revoked = %v, want 1", output["revoked"])
	}
	if store.Len() != 0 {
		t.Fatalf("store len after revoke = %d, want 0", store.Len())
	}
}

func TestSSHRevokeResolvesSessionRefFromData(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", store)

	_, err := store.Add(testPublicKey, "nixstasis-support", "cmd-auth", "session-data", 5*time.Minute)
	if err != nil {
		t.Fatalf("Add() error = %v", err)
	}

	revoke := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-revoke",
		Type:      "ssh_revoke",
		Payload: &transport.CommandPayload{
			ContentType: sshauth.RevokePayloadContentType,
			Data:        `{"session_ref":"session-data"}`,
		},
	}})[0]
	if revoke.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_revoke ok, got %s: %s", revoke.Status, revoke.Error)
	}
	if store.Len() != 0 {
		t.Fatalf("store len = %d, want 0", store.Len())
	}
}

func TestSSHRevokeFailsWithoutSessionRef(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", store)

	revoke := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-revoke",
		Type:      "ssh_revoke",
		Payload: &transport.CommandPayload{
			ContentType: sshauth.RevokePayloadContentType,
		},
	}})[0]
	if revoke.Status != transport.CommandStatusFailed {
		t.Fatalf("expected ssh_revoke failure, got %s", revoke.Status)
	}
}

func TestSSHRevokeIsSerial(t *testing.T) {
	if !commandRequiresSerial(transport.CommandRequest{Type: "ssh_revoke"}) {
		t.Fatal("ssh_revoke must run serially with the other stateful commands")
	}
	if !commandRequiresSerial(transport.CommandRequest{Type: "ssh_authorize"}) {
		t.Fatal("ssh_authorize must run serially with the other stateful commands")
	}
}

func TestGivenRemoveCommitAndExpiredContext_WhenExecuteBatch_ThenSuccessReported(t *testing.T) {
	scriptsDir := t.TempDir()
	path := filepath.Join(scriptsDir, "safe_1.stary")
	content := strings.TrimSpace(`---
name: safe
version: "1"
schema:
  type: object
---
def main():
    return {}
`)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write script: %v", err)
	}
	handler := NewHandler(scriptsDir)
	originalHook := afterCommandCommitHook
	defer func() { afterCommandCommitHook = originalHook }()

	ctx, cancel := context.WithCancel(context.Background())
	afterCommandCommitHook = cancel
	result := handler.removeScript(ctx, "cmd-remove", []string{"safe", "1"}, nil)

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected remove_script to succeed once committed, got status=%s error=%s", result.Status, result.Error)
	}
}
