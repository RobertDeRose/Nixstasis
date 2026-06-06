// Package commands handles execution of server-issued commands.
package commands

import (
	"context"
	"encoding/json"
	"fmt"
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
	scriptsDir         string
	authorizedKeysPath string
	sshAuthStore       *sshauth.Store
}

// NewHandler constructs a Handler with a scripts discovery directory.
func NewHandler(scriptsDir string) *Handler {
	return &Handler{scriptsDir: scriptsDir}
}

// NewHandlerWithAuthorizedKeys constructs a Handler with an explicit authorized_keys target.
func NewHandlerWithAuthorizedKeys(scriptsDir, authorizedKeysPath string) *Handler {
	return &Handler{scriptsDir: scriptsDir, authorizedKeysPath: authorizedKeysPath}
}

// NewHandlerWithSSHAuth constructs a Handler with dynamic SSH authorization support.
func NewHandlerWithSSHAuth(scriptsDir, authorizedKeysPath string, store *sshauth.Store) *Handler {
	return &Handler{scriptsDir: scriptsDir, authorizedKeysPath: authorizedKeysPath, sshAuthStore: store}
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
	case "remove_script":
		return h.removeScript(ctx, cmd.CommandID, cmd.Args, cmd.Payload)
	case "ssh_authorize":
		return h.sshAuthorize(ctx, cmd.CommandID, cmd.PublicKey, cmd.Args, cmd.Payload)
	case "ssh_revoke":
		return h.sshRevoke(ctx, cmd.CommandID, cmd.Payload)
	default:
		return failureResult(cmd.CommandID, fmt.Sprintf("unsupported command: %s", cmd.Type))
	}
}

func commandRequiresSerial(cmd transport.CommandRequest) bool {
	switch cmd.Type {
	case "install_script", "remove_script", "ssh_authorize", "ssh_revoke":
		return true
	default:
		return false
	}
}

func (h *Handler) sshAuthorize(ctx context.Context, commandID, publicKey string, args []string, payload *transport.CommandPayload) transport.CommandResult {
	if isDynamicSSHAuthorizePayload(payload) {
		return h.dynamicSSHAuthorize(ctx, commandID, publicKey, payload)
	}

	key, requestedPath, err := resolveSSHAuthorize(publicKey, args, payload)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	path, err := h.resolveAuthorizedKeysPath(requestedPath)
	if err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}
	if err := appendAuthorizedKey(path, key); err != nil {
		return failureResult(commandID, err.Error())
	}
	afterCommandCommitHook()
	if ctx.Err() != nil {
		return transport.CommandResult{
			CommandID: commandID,
			Status:    transport.CommandStatusOK,
			Output:    map[string]any{"path": path, "timed_out_after_commit": true},
		}
	}
	return transport.CommandResult{
		CommandID: commandID,
		Status:    transport.CommandStatusOK,
		Output:    map[string]any{"path": path},
	}
}

type dynamicSSHAuthorizePayload struct {
	TargetUser string `json:"target_user"`
	TTLSeconds int    `json:"ttl_seconds"`
	SessionRef string `json:"session_ref"`
}

func (h *Handler) dynamicSSHAuthorize(ctx context.Context, commandID, publicKey string, payload *transport.CommandPayload) transport.CommandResult {
	if h.sshAuthStore == nil {
		return failureResult(commandID, "ssh authorization store is not configured")
	}
	if strings.TrimSpace(publicKey) == "" {
		return failureResult(commandID, "missing public key")
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

func isDynamicSSHAuthorizePayload(payload *transport.CommandPayload) bool {
	if payload == nil {
		return false
	}
	contentType := strings.ToLower(strings.TrimSpace(payload.ContentType))
	return strings.HasPrefix(contentType, strings.ToLower(sshauth.PayloadContentType)) ||
		strings.HasPrefix(contentType, "application/vnd.nixstasis.ssh-authorize+json")
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

func (h *Handler) resolveAuthorizedKeysPath(requestedPath string) (string, error) {
	if h.authorizedKeysPath == "" {
		return "", fmt.Errorf("authorized_keys path is not configured")
	}
	canonical, err := canonicalAuthorizedKeysPath(h.authorizedKeysPath)
	if err != nil {
		return "", err
	}
	if requestedPath == "" {
		return canonical, nil
	}
	requested, err := canonicalAuthorizedKeysPath(requestedPath)
	if err != nil {
		return "", err
	}
	if requested != canonical {
		return "", fmt.Errorf("authorized_keys path is not allowed")
	}
	return canonical, nil
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

func resolveSSHAuthorize(publicKey string, args []string, payload *transport.CommandPayload) (key, path string, err error) {
	key = publicKey
	if key == "" && payload != nil {
		key = payload.Data
	}
	if payload != nil {
		path = payload.Name
	}
	if key == "" && len(args) > 0 {
		key = args[0]
	}
	if path == "" && len(args) > 1 {
		path = args[1]
	}
	if key == "" {
		return "", "", fmt.Errorf("missing public key")
	}
	return key, path, nil
}
