// Package commands handles execution of server-issued commands.
package commands

import (
	"context"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

const commandTimeout = 5 * time.Second

// Handler executes supported command types.
type Handler struct {
	scriptsDir string
}

// NewHandler constructs a Handler with a scripts discovery directory.
func NewHandler(scriptsDir string) *Handler {
	return &Handler{scriptsDir: scriptsDir}
}

// ExecuteBatch runs commands in parallel when possible and aggregates results.
func (h *Handler) ExecuteBatch(ctx context.Context, commands []transport.CommandRequest) []transport.CommandResult {
	results := make([]transport.CommandResult, len(commands))
	seen := make(map[string]bool)

	var wg sync.WaitGroup
	var batch []int

	flushBatch := func() {
		if len(batch) == 0 {
			return
		}
		for _, idx := range batch {
			cmd := commands[idx]
			wg.Add(1)
			go func(i int, command transport.CommandRequest) {
				defer wg.Done()
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
	default:
		return failureResult(cmd.CommandID, fmt.Sprintf("unsupported command: %s", cmd.Type))
	}
}

func commandRequiresSerial(cmd transport.CommandRequest) bool {
	switch cmd.Type {
	case "install_script", "remove_script":
		return true
	default:
		return false
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

func (h *Handler) installScript(ctx context.Context, commandID string, args []string, payload *transport.CommandPayload) transport.CommandResult {
	path, content, err := resolveInstallSource(args, payload)
	if err != nil {
		return failureResult(commandID, err.Error())
	}

	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
	}

	fm, rawText, err := loadInstallScript(path, content)
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

	installDir := script.DefaultInstallDir()
	if err := ensureDir(installDir); err != nil {
		return failureResult(commandID, err.Error())
	}

	destPath := filepath.Join(installDir, script.InstallFilename(fm.Name, fm.Version))
	if err := installScriptFile(path, rawText, destPath); err != nil {
		return failureResult(commandID, err.Error())
	}
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
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

	scripts, err := script.DiscoverScripts(script.DefaultInstallDir())
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
	if ctx.Err() != nil {
		return failureResult(commandID, "timeout")
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

func resolveInstallSource(args []string, payload *transport.CommandPayload) (path, content string, err error) {
	content = stringField(payload, "content")
	if path == "" && len(args) > 0 {
		path = args[0]
	}
	if path == "" && content == "" {
		return "", "", fmt.Errorf("missing path or content")
	}
	return path, content, nil
}

func loadInstallScript(path, content string) (script.FrontMatter, string, error) {
	if path != "" {
		fm, _, err := script.ParseStaryFile(path)
		return fm, "", err
	}
	fm, _, err := script.ParseStaryContent(content)
	return fm, content, err
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

func installScriptFile(path, rawText, destPath string) error {
	if path != "" {
		return copyFile(path, destPath)
	}
	return writeFile(destPath, rawText)
}

func resolveRemoveTarget(args []string, payload *transport.CommandPayload) (name, version string, err error) {
	name = stringField(payload, "name")
	version = stringField(payload, "version")
	if name == "" && len(args) > 0 {
		name = args[0]
	}
	if version == "" && len(args) > 1 {
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

func stringField(payload *transport.CommandPayload, key string) string {
	if payload == nil {
		return ""
	}
	switch key {
	case "content":
		return payload.Data
	case "name":
		return payload.Name
	case "version":
		return ""
	default:
		return ""
	}
}
