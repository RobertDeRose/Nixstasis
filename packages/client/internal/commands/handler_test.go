package commands

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/commandpolicy"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
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

func TestGivenValidRunScriptPayload_WhenExecuteBatch_ThenReturnsStructuredResult(t *testing.T) {
	handler := NewHandler("")
	content := strings.TrimSpace(`---
name: test-run
schema:
  type: object
  properties:
    value:
      type: string
---
def main():
    return {"value": "ok"}
`)

	results := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-run",
		Type:      "run_script",
		Payload: &transport.CommandPayload{
			ContentType: "text/x-stary",
			Data:        content,
		},
	}})

	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusOK {
		t.Fatalf("expected run_script to succeed, got %s: %s", results[0].Status, results[0].Error)
	}
	output, ok := results[0].Output.(map[string]any)
	if !ok {
		t.Fatalf("expected structured output, got %T", results[0].Output)
	}
	if output["status"] != "passed" {
		t.Fatalf("expected passed status, got %v", output["status"])
	}
	if output["validation"] != "valid" {
		t.Fatalf("expected valid validation status, got %v", output["validation"])
	}
}

func TestGivenInvalidRunScriptPayload_WhenExecuteBatch_ThenReturnsFailedEnvelope(t *testing.T) {
	handler := NewHandler("")
	content := strings.TrimSpace(`---
name: test-run
schema:
  type: object
  properties:
    value:
      type: string
---
def main():
    return {"value": 1}
`)

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-run",
		Type:      "run_script",
		Payload: &transport.CommandPayload{
			ContentType: "text/x-stary",
			Data:        content,
		},
	}})[0]

	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected run_script failure, got %s", result.Status)
	}
	output, ok := result.Output.(map[string]any)
	if !ok {
		t.Fatalf("expected structured failure output, got %T", result.Output)
	}
	if output["status"] != "failed" {
		t.Fatalf("expected failed envelope, got %v", output["status"])
	}
	if output["error_type"] != "validation" {
		t.Fatalf("expected validation error type, got %v", output["error_type"])
	}
}

func TestGivenApplyCommandPolicy_WhenExecuteBatch_ThenAppliesPolicy(t *testing.T) {
	handler := NewHandler("")
	payload := `{"version":"v1","revision":1,"commands":{"safe":"/bin/echo"}}`

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-policy",
		Type:      "apply_command_policy",
		Payload: &transport.CommandPayload{
			Data: payload,
		},
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected apply_command_policy to succeed, got %s: %s", result.Status, result.Error)
	}
	out, ok := result.Output.(map[string]any)
	if !ok {
		t.Fatalf("expected output map, got %T", result.Output)
	}
	if out["mode"] != "apply_command_policy" {
		t.Fatalf("expected apply_command_policy mode, got %v", out["mode"])
	}
}

func TestGivenDuplicateApplyCommandPolicyVersion_WhenExecuteBatch_ThenReportsIdempotent(t *testing.T) {
	handler := NewHandler("")
	cmd := transport.CommandRequest{
		Type:    "apply_command_policy",
		Payload: &transport.CommandPayload{Data: `{"policy_version":"v1","commands":{"safe":"/bin/echo"}}`},
	}
	first := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-first",
		Type:      cmd.Type,
		Payload:   cmd.Payload,
	}})[0]
	if first.Status != transport.CommandStatusOK {
		t.Fatalf("expected first apply success, got %s", first.Status)
	}
	second := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-second",
		Type:      cmd.Type,
		Payload:   cmd.Payload,
	}})[0]
	if second.Status != transport.CommandStatusOK {
		t.Fatalf("expected second apply success, got %s", second.Status)
	}
	out, ok := second.Output.(map[string]any)
	if !ok {
		t.Fatalf("expected output map, got %T", second.Output)
	}
	if out["already_applied"] != true {
		t.Fatalf("expected already_applied=true, got %v", out["already_applied"])
	}
}

func TestGivenPreloadedRuntimePolicy_WhenExecuteBatch_ThenSameVersionReplayIsIdempotent(t *testing.T) {
	runtimeCfg := script.RuntimeConfig{
		ExecCommandAllowlist: map[string]string{"safe": "/bin/echo"},
		CommandPolicyVersion: "v1",
	}
	handler := NewHandlerWithSSHAuthRuntimeConfigAndPolicyStore("", nil, &runtimeCfg, nil)
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-policy",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"policy_version":"v1","commands":{"safe":"/bin/echo"}}`},
	}})[0]
	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected replayed apply_command_policy to succeed, got %s: %s", result.Status, result.Error)
	}
	out := result.Output.(map[string]any)
	if out["already_applied"] != true {
		t.Fatalf("expected already_applied=true, got %v", out["already_applied"])
	}
}

func TestGivenOlderApplyCommandPolicyRevision_WhenExecuteBatch_ThenRejectsStalePolicy(t *testing.T) {
	runtimeCfg := script.RuntimeConfig{
		ExecCommandAllowlist:  map[string]string{"new": "/bin/true"},
		CommandPolicyVersion:  "v2",
		CommandPolicyRevision: 2,
	}
	handler := NewHandlerWithSSHAuthRuntimeConfigAndPolicyStore("", nil, &runtimeCfg, nil)

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-policy",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"version":"v1","revision":1,"commands":{"old":"/bin/echo"}}`},
	}})[0]
	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected stale policy failure, got %s", result.Status)
	}
	if runtimeCfg.CommandPolicyVersion != "v2" || runtimeCfg.ExecCommandAllowlist["new"] != "/bin/true" {
		t.Fatalf("stale policy mutated runtime config: %+v", runtimeCfg)
	}
}

func TestGivenApplyCommandPolicyStore_WhenExecuteBatch_ThenPersistsPolicy(t *testing.T) {
	store := commandpolicy.NewStore(filepath.Join(t.TempDir(), "command-policy.json"))
	handler := &Handler{policyStore: store}

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-policy",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"version":"v1","revision":3,"commands":{"safe":"/bin/echo"}}`},
	}})[0]
	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected apply_command_policy to succeed, got %s: %s", result.Status, result.Error)
	}
	state, err := store.Load()
	if err != nil {
		t.Fatalf("store.Load() error = %v", err)
	}
	if state.Version != "v1" || state.Revision != 3 || state.Commands["safe"] != "/bin/echo" {
		t.Fatalf("persisted state = %+v", state)
	}
}

func TestGivenApplyCommandPolicyPersistFailure_WhenExecuteBatch_ThenFailsClosed(t *testing.T) {
	runtimeCfg := script.RuntimeConfig{ExecCommandAllowlist: map[string]string{"local": "/bin/true"}}
	handler := &Handler{runtimeConfig: &runtimeCfg, policyStore: commandpolicy.NewStore(t.TempDir())}

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-policy",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"policy_version":"v2","commands":{"safe":"/bin/echo"}}`},
	}})[0]
	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected apply_command_policy failure, got %s", result.Status)
	}
	if runtimeCfg.CommandPolicyVersion != "" {
		t.Fatalf("runtime policy version mutated on persist failure: %q", runtimeCfg.CommandPolicyVersion)
	}
	if runtimeCfg.ExecCommandAllowlist["local"] != "/bin/true" {
		t.Fatalf("runtime allowlist mutated on persist failure: %+v", runtimeCfg.ExecCommandAllowlist)
	}
}

func TestGivenEmptyApplyCommandPolicy_WhenExecuteBatch_ThenAppliesDenyAll(t *testing.T) {
	runtimeCfg := script.RuntimeConfig{ExecCommandAllowlist: map[string]string{"local": "/bin/true"}}
	store := commandpolicy.NewStore(filepath.Join(t.TempDir(), "command-policy.json"))
	handler := &Handler{runtimeConfig: &runtimeCfg, policyStore: store}
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-empty-policy",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"policy_version":"deny-all","commands":{}}`},
	}})[0]
	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected empty policy success, got %s: %s", result.Status, result.Error)
	}
	if len(runtimeCfg.ExecCommandAllowlist) != 0 {
		t.Fatalf("expected deny-all empty allowlist, got %+v", runtimeCfg.ExecCommandAllowlist)
	}
	state, err := store.Load()
	if err != nil {
		t.Fatalf("store.Load() error = %v", err)
	}
	if state.Version != "deny-all" || len(state.Commands) != 0 {
		t.Fatalf("persisted deny-all state = %+v", state)
	}
}

func TestGivenBadApplyCommandPolicyPayload_WhenExecuteBatch_ThenFails(t *testing.T) {
	handler := NewHandler("")
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-bad",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: `{"policy_version":"","commands":{"safe":"echo"}}`},
	}})[0]

	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected apply_command_policy failure, got %s", result.Status)
	}
}

func TestGivenRunScriptPolicyApplied_WhenExecuteBatch_ThenCanRunAllowedCommand(t *testing.T) {
	scriptPath, err := os.CreateTemp("", "cmd-*.sh")
	if err != nil {
		t.Fatalf("create temp script: %v", err)
	}
	cmdPath := scriptPath.Name()
	scriptPath.Close()
	defer os.Remove(cmdPath)
	if err := os.Chmod(cmdPath, 0o755); err != nil {
		t.Fatalf("chmod temp script: %v", err)
	}
	if err := os.WriteFile(cmdPath, []byte("#!/usr/bin/env sh\nprintf 'ok'"), 0o755); err != nil {
		t.Fatalf("write temp script: %v", err)
	}

	runtimeCfg := script.RuntimeConfig{}
	handler := &Handler{runtimeConfig: &runtimeCfg}
	applyPayload := fmt.Sprintf(`{"policy_version":"v2","commands":{"print-ok":"%s"}}`, cmdPath)
	setup := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-setup",
		Type:      "apply_command_policy",
		Payload:   &transport.CommandPayload{Data: applyPayload},
	}})[0]
	if setup.Status != transport.CommandStatusOK {
		t.Fatalf("expected policy setup success, got %s: %s", setup.Status, setup.Error)
	}

	content := strings.TrimSpace(`---
name: test-run
schema:
  type: object
  properties:
    value:
      type: string
---
def main():
    return {"value": exec_cmd(cmd="print-ok")}
`)

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-run",
		Type:      "run_script",
		Payload:   &transport.CommandPayload{ContentType: "text/x-stary", Data: content},
	}})[0]
	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected allowed run_script success, got %s: %s", result.Status, result.Error)
	}
	out, ok := result.Output.(map[string]any)
	if !ok {
		t.Fatalf("expected output map, got %T", result.Output)
	}
	outResult, ok := out["output"].(map[string]any)
	if !ok {
		t.Fatalf("expected output payload map, got %T", out["output"])
	}
	if outResult["value"] != "ok" {
		t.Fatalf("expected script output ok, got %v", outResult["value"])
	}
}

func TestGivenDeferredRunScriptPayload_WhenExecuteBatch_ThenFailsClosed(t *testing.T) {
	handler := NewHandler("")
	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID:  "cmd-run",
		Type:       "run_script",
		PayloadRef: "script-ref",
	}})[0]

	if result.Status != transport.CommandStatusFailed {
		t.Fatalf("expected deferred payload failure, got %s", result.Status)
	}
	if result.Error != "deferred script payload lookup is not available in command handler" {
		t.Fatalf("unexpected deferred payload error: %s", result.Error)
	}
}

func TestGivenRunScript_WhenExecuteBatch_ThenDoesNotTouchInstalledScripts(t *testing.T) {
	scriptsDir := t.TempDir()
	existing := filepath.Join(scriptsDir, "existing_1.stary")
	content := strings.TrimSpace(`---
name: installed
version: "1"
schema:
  type: object
  properties:
    value:
      type: string
---
def main():
    return {"value": "installed"}
`)
	if err := os.WriteFile(existing, []byte(content), 0o644); err != nil {
		t.Fatalf("write installed script: %v", err)
	}

	handler := NewHandler(scriptsDir)
	testContent := strings.TrimSpace(`---
name: test-run
schema:
  type: object
  properties:
    value:
      type: string
---
def main():
    return {"value": "ok"}
`)

	result := handler.ExecuteBatch(context.Background(), []transport.CommandRequest{{
		CommandID: "cmd-run",
		Type:      "run_script",
		Payload: &transport.CommandPayload{
			ContentType: "text/x-stary",
			Data:        testContent,
		},
	}})[0]

	if result.Status != transport.CommandStatusOK {
		t.Fatalf("expected run_script to succeed, got %s: %s", result.Status, result.Error)
	}

	discovered, err := filepath.Glob(filepath.Join(scriptsDir, "*.stary"))
	if err != nil {
		t.Fatalf("glob installed scripts: %v", err)
	}
	if len(discovered) != 1 || discovered[0] != existing {
		t.Fatalf("expected installed scripts to remain unchanged, got %v", discovered)
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
	if !commandRequiresSerial(transport.CommandRequest{Type: "apply_command_policy"}) {
		t.Fatal("apply_command_policy must run serially")
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
