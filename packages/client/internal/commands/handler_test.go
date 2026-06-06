package commands

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

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

func TestSSHAuthorizeRejectsMalformedKeys(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ssh", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", path)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-3",
		Type:      "ssh_authorize",
		Args:      []string{"not-a-key", path},
	}})[0]

	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected malformed key to fail, got %s", result.Status)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("expected no authorized_keys file, stat err=%v", err)
	}
}

func TestSSHAuthorizeWritesValidKeyWithStrictPermissions(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ssh", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", path)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-4",
		Type:      "ssh_authorize",
		Payload: &transport.CommandPayload{
			Name: path,
			Data: testPublicKey,
		},
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_authorize to succeed, got %s: %s", result.Status, result.Error)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read authorized_keys: %v", err)
	}
	if got := strings.TrimSpace(string(data)); got != testPublicKey {
		t.Fatalf("authorized_keys = %q, want %q", got, testPublicKey)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat authorized_keys: %v", err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Fatalf("mode = %o, want 600", mode)
	}
}

func TestSSHAuthorizeMatchesAuthorizedKeysOwnerToSSHDir(t *testing.T) {
	dir := t.TempDir()
	sshDir := filepath.Join(dir, ".ssh")
	path := filepath.Join(sshDir, "authorized_keys")
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		t.Fatalf("create ssh dir: %v", err)
	}

	handler := NewHandlerWithAuthorizedKeys("", path)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-owner",
		Type:      "ssh_authorize",
		PublicKey: testPublicKey,
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_authorize to succeed, got %s: %s", result.Status, result.Error)
	}

	sshDirInfo, err := os.Stat(sshDir)
	if err != nil {
		t.Fatalf("stat ssh dir: %v", err)
	}
	keysInfo, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat authorized_keys: %v", err)
	}

	sshDirStat := sshDirInfo.Sys().(*syscall.Stat_t)
	keysStat := keysInfo.Sys().(*syscall.Stat_t)
	if keysStat.Uid != sshDirStat.Uid || keysStat.Gid != sshDirStat.Gid {
		t.Fatalf("authorized_keys owner = %d:%d, want %d:%d", keysStat.Uid, keysStat.Gid, sshDirStat.Uid, sshDirStat.Gid)
	}
}

func TestSSHAuthorizeReplacesFileAtomicallyWithoutDuplicates(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ssh", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", path)
	cmd := transport.CommandRequest{
		CommandID: "cmd-5",
		Type:      "ssh_authorize",
		Args:      []string{testPublicKey, path},
	}

	first := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{cmd})[0]
	cmd.CommandID = "cmd-6"
	second := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{cmd})[0]
	if first.Status != transport.CommandStatusOK || second.Status != transport.CommandStatusOK {
		t.Fatalf("expected both writes to succeed, got %s/%s", first.Status, second.Status)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read authorized_keys: %v", err)
	}
	if count := strings.Count(string(data), testPublicKey); count != 1 {
		t.Fatalf("expected one key entry, got %d in %q", count, string(data))
	}
}

func TestSSHAuthorizeAcceptsTopLevelPublicKeyAtConfiguredPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ssh", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", path)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-7",
		Type:      "ssh_authorize",
		PublicKey: testPublicKey,
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_authorize to succeed, got %s: %s", result.Status, result.Error)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read authorized_keys: %v", err)
	}
	if got := strings.TrimSpace(string(data)); got != testPublicKey {
		t.Fatalf("authorized_keys = %q, want %q", got, testPublicKey)
	}
}

func TestSSHAuthorizeStoresDynamicKeyInMemory(t *testing.T) {
	store := sshauth.NewStore()
	handler := NewHandlerWithSSHAuth("", "", store)
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
	handler := NewHandlerWithSSHAuth("", "", store)
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
	handler := NewHandlerWithSSHAuth("", "", store)

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
	handler := NewHandlerWithSSHAuth("", "", store)

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
	handler := NewHandlerWithSSHAuth("", "", store)

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

func TestSSHRevokeIsSerialAndUnsupportedWithoutStore(t *testing.T) {
	if !commandRequiresSerial(transport.CommandRequest{Type: "ssh_revoke"}) {
		t.Fatal("ssh_revoke must run serially with the other stateful commands")
	}

	handler := NewHandlerWithAuthorizedKeys("", "")
	revoke := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-revoke",
		Type:      "ssh_revoke",
		Payload: &transport.CommandPayload{
			ContentType: sshauth.RevokePayloadContentType,
			Name:        "session-missing",
		},
	}})[0]
	if revoke.Status != transport.CommandStatusFailed {
		t.Fatalf("expected failure when store is missing, got %s", revoke.Status)
	}
}

func TestSSHAuthorizeDoesNotReportFailureAfterCommit(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ssh", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", path)
	originalHook := afterCommandCommitHook
	defer func() { afterCommandCommitHook = originalHook }()
	ctx, cancel := context.WithCancel(context.Background())
	afterCommandCommitHook = cancel

	result := handler.sshAuthorize(ctx, "cmd-9", testPublicKey, nil, nil)

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected ssh_authorize to succeed once committed, got %s: %s", result.Status, result.Error)
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

func TestSSHAuthorizeRejectsNonCanonicalRequestedPath(t *testing.T) {
	dir := t.TempDir()
	allowed := filepath.Join(dir, "allowed", "authorized_keys")
	other := filepath.Join(dir, "other", "authorized_keys")
	handler := NewHandlerWithAuthorizedKeys("", allowed)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-8",
		Type:      "ssh_authorize",
		Args:      []string{testPublicKey, other},
	}})[0]

	if result.Status != transport.CommandStatusFailed || result.Error != "authorized_keys path is not allowed" {
		t.Fatalf("expected path rejection, got status=%s error=%s", result.Status, result.Error)
	}
	if _, err := os.Stat(other); !os.IsNotExist(err) {
		t.Fatalf("expected other authorized_keys not to be written, stat err=%v", err)
	}
}
