// Package commands handles execution of server-issued commands.
package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/sshauth"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

const commandTimeout = 5 * time.Second

// MaxCommandsPerPoll caps the command list accepted from a single poll response.
const MaxCommandsPerPoll = 50

const maxConcurrentNonSerialCommands = 8

var afterCommandCommitHook = func() {}

// Handler executes supported command types.
type Handler struct {
	scriptsDir           string
	sshAuthStore         *sshauth.Store
	runtimeConfig        *script.RuntimeConfig
	appliedPolicyVersion string
	appliedCommandPolicy map[string]string
	policyMu             sync.RWMutex
}

// NewHandler constructs a Handler with a scripts discovery directory.
func NewHandler(scriptsDir string) *Handler {
	return &Handler{scriptsDir: scriptsDir}
}

// NewHandlerWithSSHAuth constructs a Handler with in-memory SSH authorization support.
func NewHandlerWithSSHAuth(scriptsDir string, store *sshauth.Store) *Handler {
	return &Handler{scriptsDir: scriptsDir, sshAuthStore: store}
}

// NewHandlerWithSSHAuthAndRuntimeConfig constructs a Handler with in-memory SSH authorization
// and command-policy runtime updates.
func NewHandlerWithSSHAuthAndRuntimeConfig(scriptsDir string, store *sshauth.Store, cfg *script.RuntimeConfig) *Handler {
	return &Handler{scriptsDir: scriptsDir, sshAuthStore: store, runtimeConfig: cfg}
}

// NewHandlerWithRuntimeConfig constructs a Handler and shares a runtime config pointer for
// command-policy updates.
func NewHandlerWithRuntimeConfig(scriptsDir string, cfg *script.RuntimeConfig) *Handler {
	return &Handler{scriptsDir: scriptsDir, runtimeConfig: cfg}
}

// ExecuteBatch runs commands in parallel when possible and aggregates results.
func (h *Handler) ExecuteBatch(ctx context.Context, commands []transport.CommandRequest) []transport.CommandResult {
	if len(commands) > MaxCommandsPerPoll {
		commands = commands[:MaxCommandsPerPoll]
	}

	results := make([]transport.CommandResult, len(commands))
	seen := make(map[string]bool)

	var wg sync.WaitGroup
	var batch []int

	flushBatch := func() {
		if len(batch) == 0 {
			return
		}
		sem := make(chan struct{}, maxConcurrentNonSerialCommands)
		for _, idx := range batch {
			cmd := commands[idx]
			wg.Add(1)
			go func(i int, command transport.CommandRequest) {
				defer wg.Done()
				select {
				case sem <- struct{}{}:
					defer func() { <-sem }()
				case <-ctx.Done():
					results[i] = failureResult(command.CommandID, "timeout")
					return
				}
				cmdCtx, cancel := context.WithTimeout(ctx, commandTimeout)
				defer cancel()
				results[i] = h.executeOne(cmdCtx, command)
			}(idx, cmd)
		}
		wg.Wait()
		batch = nil
	}
	for i, cmd := range commands {
		if cmd.CommandID == "" {
			results[i] = failureResult(cmd.CommandID, "missing_command_id")
			continue
		}
		if seen[cmd.CommandID] {
			results[i] = failureResult(cmd.CommandID, "duplicate_command_id")
			continue
		}
		seen[cmd.CommandID] = true

		if commandRequiresSerial(cmd) {
			flushBatch()
			cmdCtx, cancel := context.WithTimeout(ctx, commandTimeout)
			results[i] = h.executeOne(cmdCtx, cmd)
			cancel()
			continue
		}

		batch = append(batch, i)
	}

	flushBatch()
	return results
}

func (h *Handler) executeOne(ctx context.Context, cmd transport.CommandRequest) transport.CommandResult {
	if ctx.Err() != nil {
		return failureResult(cmd.CommandID, "timeout")
	}

	switch cmd.Type {
	case "list_scripts":
		return h.listScripts(ctx, cmd.CommandID)
	case "install_script":
		return h.installScript(ctx, cmd.CommandID, cmd.Args, cmd.Payload)
	case "run_script":
		return h.runScript(ctx, cmd.CommandID, cmd.Args, cmd.Payload, cmd.PayloadRef)
	case "remove_script":
		return h.removeScript(ctx, cmd.CommandID, cmd.Args, cmd.Payload)
	case "ssh_authorize":
		return h.sshAuthorize(ctx, cmd.CommandID, cmd.PublicKey, cmd.Payload)
	case "ssh_revoke":
		return h.sshRevoke(ctx, cmd.CommandID, cmd.Payload)
	case "apply_command_policy":
		return h.applyCommandPolicy(ctx, cmd.CommandID, cmd.Payload)
	default:
		return failureResult(cmd.CommandID, fmt.Sprintf("unsupported command: %s", cmd.Type))
	}
}

func commandRequiresSerial(cmd transport.CommandRequest) bool {
	switch cmd.Type {
	case "install_script", "remove_script", "ssh_authorize", "ssh_revoke", "run_script", "apply_command_policy":
		return true
	default:
		return false
	}
}

func (h *Handler) sshAuthorize(ctx context.Context, commandID, publicKey string, payload *transport.CommandPayload) transport.CommandResult {
	if h.sshAuthStore == nil {
		return failureResult(commandID, "ssh authorization store is not configured")
	}
	if strings.TrimSpace(publicKey) == "" {
		return failureResult(commandID, "missing public key")
	}
	if payload == nil {
		return failureResult(commandID, "missing ssh_authorize payload")
	}
	var data dynamicSSHAuthorizePayload
	if err := json.Unmarshal([]byte(payload.Data), &data); err != nil {
		return failureResult(commandID, "invalid ssh_authorize payload: "+err.Error())
	}
	if data.TargetUser != "nixstasis-support" {
		return failureResult(commandID, "unsupported target_user")
	}
	if data.SessionRef == "" {
		return failureResult(commandID, "session_ref is required")
	}
	if data.TTLSeconds <= 0 {
		return failureResult(commandID, "ttl_seconds must be positive")
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}
	entry, err := h.sshAuthStore.Add(publicKey, data.TargetUser, commandID, data.SessionRef, time.Duration(data.TTLSeconds)*time.Second)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	afterCommandCommitHook()
	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output: map[string]any{
			"mode":        "dynamic_ssh_authorize",
			"target_user": entry.TargetUser,
			"session_ref": entry.SessionRef,
			"expires_at":  entry.ExpiresAt.Format(time.RFC3339),
			"fingerprint": entry.Key.Fingerprint,
		},
	}
}

type dynamicSSHAuthorizePayload struct {
	TargetUser string `json:"target_user"`
	TTLSeconds int    `json:"ttl_seconds"`
	SessionRef string `json:"session_ref"`
}

type sshRevokePayload struct {
	SessionRef string `json:"session_ref"`
}

func (h *Handler) sshRevoke(ctx context.Context, commandID string, payload *transport.CommandPayload) transport.CommandResult {
	if h.sshAuthStore == nil {
		return failureResult(commandID, "ssh authorization store is not configured")
	}
	if payload == nil {
		return failureResult(commandID, "missing ssh_revoke payload")
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	sessionRef := strings.TrimSpace(payload.Name)
	if sessionRef == "" {
		var data sshRevokePayload
		if err := json.Unmarshal([]byte(payload.Data), &data); err == nil {
			sessionRef = strings.TrimSpace(data.SessionRef)
		}
	}
	if sessionRef == "" {
		return failureResult(commandID, "session_ref is required")
	}

	revoked := h.sshAuthStore.RevokeSession(sessionRef)
	afterCommandCommitHook()
	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output: map[string]any{
			"mode":        "dynamic_ssh_revoke",
			"session_ref": sessionRef,
			"revoked":     revoked,
		},
	}
}

func (h *Handler) listScripts(ctx context.Context, commandID string) transport.CommandResult {
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}
	scripts, err := script.DiscoverScripts(h.scriptsDir)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	output := make([]map[string]any, 0, len(scripts))
	for _, info := range scripts {
		output = append(output, map[string]any{
			"name":    info.Name,
			"version": info.Version,
			"path":    info.Path,
		})
	}

	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output:    map[string]any{"scripts": output},
	}
}

func (h *Handler) installScript(ctx context.Context, commandID string, _ []string, payload *transport.CommandPayload) transport.CommandResult {
	content, err := resolveInstallContent(payload)
	if err != nil {
		return failureResult(commandID, err.Error())
	}

	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	fm, _, err := script.ParseStaryContent(content)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if _, err := script.CompileSchema(fm.Schema); err != nil {
		return failureResult(commandID, err.Error())
	}
	if err := validateScriptTarget(fm.Name, fm.Version); err != nil {
		return failureResult(commandID, err.Error())
	}

	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	existing, err := script.DiscoverScripts(h.scriptsDir)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if err := ensureNewerVersion(existing, fm); err != nil {
		return failureResult(commandID, err.Error())
	}

	installDir := h.scriptsDir
	if err := ensureDir(installDir); err != nil {
		return failureResult(commandID, err.Error())
	}

	destPath := filepath.Join(installDir, script.InstallFilename(fm.Name, fm.Version))
	if err := writeFile(destPath, content); err != nil {
		return failureResult(commandID, err.Error())
	}
	afterCommandCommitHook()
	if ctx.Err() != nil {
		return transport.CommandResult{
			CommandID: commandID,
			Status:    transport.CommandStatusOK,
			Output: map[string]any{
				"name":                   fm.Name,
				"version":                fm.Version,
				"path":                   destPath,
				"timed_out_after_commit": true,
			},
		}
	}

	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output: map[string]any{
			"name":    fm.Name,
			"version": fm.Version,
			"path":    destPath,
		},
	}
}

func (h *Handler) runScript(ctx context.Context, commandID string, args []string, payload *transport.CommandPayload, payloadRef string) transport.CommandResult {
	content, err := resolveRunScriptContent(payload, payloadRef)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	cfg := h.commandRuntimeConfig()
	result, err := executeTestScript(ctx, cfg, content, args)
	if err != nil {
		return transport.CommandResult{
			CommandID: commandID,
			Status:    transport.CommandStatusFailed,
			Output:    result,
			Error:     err.Error(),
		}
	}

	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output:    result,
	}
}

func (h *Handler) commandRuntimeConfig() script.RuntimeConfig {
	cfg := script.RuntimeConfig{}
	if h.runtimeConfig != nil {
		cfg = *h.runtimeConfig
	}

	h.policyMu.RLock()
	defer h.policyMu.RUnlock()
	if h.appliedCommandPolicy != nil {
		cfg.ExecCommandAllowlist = copyCommandPolicy(h.appliedCommandPolicy)
		cfg.CommandPolicyVersion = h.appliedPolicyVersion
	}

	return cfg
}

func (h *Handler) applyCommandPolicy(ctx context.Context, commandID string, payload *transport.CommandPayload) transport.CommandResult {
	if payload == nil {
		return failureResult(commandID, "missing apply_command_policy payload")
	}

	policy, err := parseApplyCommandPolicy(payload.Data)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	applied := h.applyPolicy(policy)
	if applied.Err != nil {
		return failureResult(commandID, applied.Err.Error())
	}
	if h.runtimeConfig != nil {
		h.runtimeConfig.ExecCommandAllowlist = copyCommandPolicy(applied.Commands)
		h.runtimeConfig.CommandPolicyVersion = applied.Version
	}

	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output: map[string]any{
			"mode":             "apply_command_policy",
			"policy_version":   policy.Version,
			"commands_applied": len(policy.Commands),
			"already_applied":  applied.AlreadyApplied,
			"previous_version": applied.PreviousVersion,
		},
	}
}

func (h *Handler) removeScript(ctx context.Context, commandID string, args []string, payload *transport.CommandPayload) transport.CommandResult {
	name, version, err := resolveRemoveTarget(args, payload)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	scripts, err := script.DiscoverScripts(h.scriptsDir)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	target, err := selectRemovalTarget(scripts, name, version)
	if err != nil {
		return failureResult(commandID, err.Error())
	}

	if err := removeFile(target.Path); err != nil {
		return failureResult(commandID, err.Error())
	}
	afterCommandCommitHook()
	if ctx.Err() != nil {
		return transport.CommandResult{
			CommandID: commandID,
			Status:    transport.CommandStatusOK,
			Output: map[string]any{
				"name":                   name,
				"version":                target.Version,
				"timed_out_after_commit": true,
			},
		}
	}

	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output: map[string]any{
			"name":    name,
			"version": target.Version,
		},
	}
}

func failureResult(commandID, reason string) transport.CommandResult {
	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusFailed,
		Error:     reason,
	}
}

func resolveInstallContent(payload *transport.CommandPayload) (string, error) {
	if payload == nil || payload.Data == "" {
		return "", fmt.Errorf("missing script content")
	}
	return payload.Data, nil
}

func resolveRunScriptContent(payload *transport.CommandPayload, payloadRef string) (string, error) {
	if payload != nil {
		if payload.ContentType != "" && payload.ContentType != "text/x-stary" && payload.ContentType != "text/stary" {
			return "", fmt.Errorf("unsupported script payload content type: %s", payload.ContentType)
		}
		if payload.Data != "" {
			return payload.Data, nil
		}
	}
	if payloadRef != "" {
		return "", fmt.Errorf("deferred script payload lookup is not available in command handler")
	}
	return "", fmt.Errorf("script payload is required")
}

type applyCommandPolicyPayload struct {
	Version  string            `json:"policy_version"`
	Commands map[string]string `json:"commands"`
}

type appliedCommandPolicyResult struct {
	Version         string
	Commands        map[string]string
	PreviousVersion string
	AlreadyApplied  bool
	Err             error
}

func (h *Handler) applyPolicy(policy applyCommandPolicyPayload) appliedCommandPolicyResult {
	if h == nil {
		return appliedCommandPolicyResult{Err: fmt.Errorf("handler is nil")}
	}

	h.policyMu.Lock()
	defer h.policyMu.Unlock()

	previousVersion := h.appliedPolicyVersion
	if previousVersion != "" && policy.Version == previousVersion {
		if commandPolicyEquals(policy.Commands, h.appliedCommandPolicy) {
			return appliedCommandPolicyResult{Version: policy.Version, Commands: copyCommandPolicy(h.appliedCommandPolicy), AlreadyApplied: true, PreviousVersion: previousVersion}
		}
		return appliedCommandPolicyResult{Err: fmt.Errorf("policy version %q conflicts with existing policy", policy.Version)}
	}

	h.appliedPolicyVersion = policy.Version
	h.appliedCommandPolicy = copyCommandPolicy(policy.Commands)

	return appliedCommandPolicyResult{Version: policy.Version, Commands: copyCommandPolicy(policy.Commands), AlreadyApplied: false, PreviousVersion: previousVersion}
}

func commandPolicyEquals(left, right map[string]string) bool {
	if len(left) != len(right) {
		return false
	}
	for key, leftValue := range left {
		rightValue, ok := right[key]
		if !ok || rightValue != leftValue {
			return false
		}
	}
	return true
}

func copyCommandPolicy(source map[string]string) map[string]string {
	copyMap := make(map[string]string, len(source))
	maps.Copy(copyMap, source)
	return copyMap
}

func parseApplyCommandPolicy(payload string) (applyCommandPolicyPayload, error) {
	var req applyCommandPolicyPayload
	if payload == "" {
		return applyCommandPolicyPayload{}, fmt.Errorf("missing apply_command_policy payload data")
	}
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return applyCommandPolicyPayload{}, fmt.Errorf("invalid apply_command_policy payload: %w", err)
	}
	if req.Version == "" {
		return applyCommandPolicyPayload{}, fmt.Errorf("missing policy version")
	}
	if len(req.Commands) == 0 {
		return applyCommandPolicyPayload{}, fmt.Errorf("empty command policy")
	}

	resolved := make(map[string]string, len(req.Commands))
	for name, path := range req.Commands {
		name = strings.TrimSpace(name)
		path = strings.TrimSpace(path)
		if name == "" {
			return applyCommandPolicyPayload{}, fmt.Errorf("command name must not be empty")
		}
		if path == "" {
			return applyCommandPolicyPayload{}, fmt.Errorf("command path must not be empty for %s", name)
		}
		if !filepath.IsAbs(path) {
			return applyCommandPolicyPayload{}, fmt.Errorf("command path must be absolute: %s", name)
		}
		resolved[name] = path
	}

	return applyCommandPolicyPayload{Version: req.Version, Commands: resolved}, nil
}

func executeTestScript(ctx context.Context, cfg script.RuntimeConfig, content string, args []string) (map[string]any, error) {
	_ = args
	rt := script.NewRuntime(cfg)
	defer func() { _ = rt.Close() }() //nolint:errcheck // close is best-effort cleanup for runtime resources

	fm, body, err := script.ParseStaryContent(content)
	if err != nil {
		return map[string]any{
			"status":        "failed",
			"validation":    "invalid",
			"error_type":    "validation",
			"error_message": err.Error(),
		}, err
	}
	schema, err := script.CompileSchema(fm.Schema)
	if err != nil {
		return map[string]any{
			"status":        "failed",
			"validation":    "invalid",
			"error_type":    "validation",
			"error_message": err.Error(),
		}, err
	}

	output, err := rt.Execute(ctx, fm.Name+".stary", body)
	if err != nil {
		envelope := map[string]any{
			"status":        "failed",
			"validation":    "invalid",
			"error_type":    "execution",
			"error_message": err.Error(),
		}
		if err.Error() == script.ErrTimeout.Error() {
			envelope["status"] = "timed_out"
			envelope["error_type"] = "timeout"
		}
		return envelope, err
	}

	if err := script.ValidateOutput(schema, output); err != nil {
		return map[string]any{
			"status":        "failed",
			"validation":    "invalid",
			"error_type":    "validation",
			"error_message": err.Error(),
			"output":        output,
		}, err
	}

	return map[string]any{
		"status":     "passed",
		"validation": "valid",
		"output":     output,
	}, nil
}

func ensureNewerVersion(existing []script.ScriptInfo, fm script.FrontMatter) error {
	versionNumber, err := script.ParseVersionNumber(fm.Version)
	if err != nil {
		return err
	}
	if maxVersion, ok := script.MaxVersion(existing, fm.Name); ok && versionNumber <= maxVersion {
		return fmt.Errorf("version must be greater than v%d", maxVersion)
	}
	return nil
}

func resolveRemoveTarget(args []string, payload *transport.CommandPayload) (name, version string, err error) {
	if payload != nil {
		name = payload.Name
	}
	if name == "" && len(args) > 0 {
		name = args[0]
	}
	if len(args) > 1 {
		version = args[1]
	}
	if name == "" {
		return "", "", fmt.Errorf("missing name")
	}
	if err := validateScriptTarget(name, version); err != nil {
		return "", "", err
	}
	return name, version, nil
}

func validateScriptTarget(name, version string) error {
	if err := script.ValidateInstallIdentifier("script name", name); err != nil {
		return err
	}
	if version == "" {
		return nil
	}
	return script.ValidateInstallIdentifier("script version", version)
}

func selectRemovalTarget(scripts []script.ScriptInfo, name, version string) (script.ScriptInfo, error) {
	if version != "" {
		for _, info := range scripts {
			if info.Name == name && info.Version == version {
				return info, nil
			}
		}
		return script.ScriptInfo{}, fmt.Errorf("script not found")
	}
	if latest, ok := script.LatestScript(scripts, name); ok {
		return latest, nil
	}
	return script.ScriptInfo{}, fmt.Errorf("script not found")
}
