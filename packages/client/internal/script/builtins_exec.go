// Package script implements Starlark script execution and built-in functions.
package script

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"go.starlark.net/starlark"
)

const (
	maxExecOutputBytes = 1 << 20

	defaultExecPath   = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	defaultExecHome   = "/"
	defaultExecLang   = "C.UTF-8"
	defaultExecLCAll  = "C.UTF-8"
	defaultExecTmpDir = "/tmp"
)

var blockedExecEnvPrefixes = []string{
	"LD_",
	"DYLD_",
	"BASH_FUNC_",
}

var blockedExecEnvKeys = map[string]struct{}{
	"BASH_ENV":          {},
	"ENV":               {},
	"GCONV_PATH":        {},
	"GIO_EXTRA_MODULES": {},
	"HOSTALIASES":       {},
	"IFS":               {},
	"LD_AUDIT":          {},
	"LD_DEBUG":          {},
	"LD_DEBUG_OUTPUT":   {},
	"LD_DYNAMIC_WEAK":   {},
	"LD_HWCAP_MASK":     {},
	"LD_LIBRARY_PATH":   {},
	"LD_ORIGIN_PATH":    {},
	"LD_PRELOAD":        {},
	"LD_PROFILE":        {},
	"LD_SHOW_AUXV":      {},
	"LD_USE_LOAD_BIAS":  {},
	"LIBPATH":           {},
	"PYTHONHOME":        {},
	"PYTHONPATH":        {},
	"RUBYLIB":           {},
	"RUBYOPT":           {},
}

func (r *Runtime) execCmdBuiltin(thread *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	var cmdName string
	var argList *starlark.List

	if err := starlark.UnpackArgs(
		"exec_cmd", args, kwargs,
		"cmd", &cmdName,
		"args?", &argList,
	); err != nil {
		return nil, err
	}

	cmdPath, err := r.resolveExecCommand(cmdName)
	if err != nil {
		return nil, err
	}

	argv := []string{cmdPath}
	if argList != nil {
		iter := argList.Iterate()
		defer iter.Done()
		var item starlark.Value
		for iter.Next(&item) {
			arg, ok := item.(starlark.String)
			if !ok {
				return nil, fmt.Errorf("args must be strings")
			}
			argv = append(argv, string(arg))
		}
	}

	if err := r.validateExecArguments(cmdPath, argv[1:]); err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(runtimeContext(thread), r.config.Timeout)
	defer cancel()

	// #nosec G204 -- command is resolved from an explicit pinned allowlist.
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir = r.config.ExecWorkDir
	cmd.Env = buildExecEnv(r.config.ExecEnv)

	if r.config.ExecUser != nil && os.Geteuid() == 0 {
		setExecUser(cmd, r.config.ExecUser)
	}

	output := newLimitedExecOutput(maxExecOutputBytes, cancel)
	cmd.Stdout = output
	cmd.Stderr = output

	err = cmd.Run()
	if output.Exceeded() {
		return nil, fmt.Errorf("command output exceeded %d-byte limit", maxExecOutputBytes)
	}
	if ctx.Err() == context.DeadlineExceeded {
		return nil, fmt.Errorf("command timed out after %s", r.config.Timeout)
	}
	if err != nil {
		return nil, fmt.Errorf("command failed: %w", err)
	}

	return starlark.String(strings.TrimSpace(output.String())), nil
}

type limitedExecOutput struct {
	mu       sync.Mutex
	buffer   bytes.Buffer
	limit    int
	exceeded bool
	cancel   context.CancelFunc
}

func newLimitedExecOutput(limit int, cancel context.CancelFunc) *limitedExecOutput {
	return &limitedExecOutput{limit: limit, cancel: cancel}
}

func (w *limitedExecOutput) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.exceeded {
		return len(p), nil
	}

	remaining := w.limit - w.buffer.Len()
	if len(p) <= remaining {
		_, _ = w.buffer.Write(p)
		return len(p), nil
	}

	if remaining > 0 {
		_, _ = w.buffer.Write(p[:remaining])
	}
	w.exceeded = true
	if w.cancel != nil {
		w.cancel()
	}

	// Report the full write as consumed after canceling the command so os/exec
	// does not retain or surface an unrelated short-write error. Additional
	// output is discarded while the process exits.
	return len(p), nil
}

func (w *limitedExecOutput) Exceeded() bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.exceeded
}

func (w *limitedExecOutput) String() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buffer.String()
}

func (r *Runtime) resolveExecCommand(cmdName string) (string, error) {
	if len(r.config.ExecCommandAllowlist) == 0 {
		return "", fmt.Errorf("exec_cmd capability is not configured")
	}
	if strings.TrimSpace(cmdName) == "" {
		return "", fmt.Errorf("command is required")
	}
	if filepath.Base(cmdName) != cmdName && !filepath.IsAbs(cmdName) {
		return "", fmt.Errorf("command must be a basename or absolute path: %s", cmdName)
	}

	allowedPath, ok := r.config.ExecCommandAllowlist[cmdName]
	if !ok && filepath.IsAbs(cmdName) {
		allowedPath, ok = r.config.ExecCommandAllowlist[filepath.Base(cmdName)]
	}
	if !ok {
		return "", fmt.Errorf("command is not allowlisted: %s", cmdName)
	}
	if !filepath.IsAbs(allowedPath) {
		return "", fmt.Errorf("allowlisted command path must be absolute: %s", cmdName)
	}
	clean := filepath.Clean(allowedPath)
	if filepath.IsAbs(cmdName) && filepath.Clean(cmdName) != clean {
		return "", fmt.Errorf("command path does not match allowlist: %s", cmdName)
	}
	return clean, nil
}

func buildExecEnv(configured []string) []string {
	envMap := map[string]string{
		"HOME":   defaultExecHome,
		"LANG":   defaultExecLang,
		"LC_ALL": defaultExecLCAll,
		"PATH":   defaultExecPath,
		"TMPDIR": defaultExecTmpDir,
	}

	for _, entry := range configured {
		key, value, ok := strings.Cut(entry, "=")
		if !ok || key == "" || key == "PATH" || execEnvBlocked(key) {
			continue
		}
		envMap[key] = value
	}

	keys := make([]string, 0, len(envMap))
	for key := range envMap {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	env := make([]string, 0, len(keys))
	for _, key := range keys {
		env = append(env, key+"="+envMap[key])
	}

	return env
}

func execEnvBlocked(key string) bool {
	if _, blocked := blockedExecEnvKeys[key]; blocked {
		return true
	}

	for _, prefix := range blockedExecEnvPrefixes {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}

	return false
}

func (r *Runtime) validateExecArguments(cmdPath string, args []string) error {
	if len(args) == 0 {
		return nil
	}

	cleanPath := filepath.Clean(cmdPath)
	allowedSets, ok := r.config.ExecArgumentAllowlist[cleanPath]
	if !ok {
		return fmt.Errorf("arguments are not permitted for %s without a local exec_command_args rule", cleanPath)
	}

	for _, allowed := range allowedSets {
		if len(allowed) != len(args) {
			continue
		}
		matched := true
		for index := range args {
			if args[index] != allowed[index] {
				matched = false
				break
			}
		}
		if matched {
			return nil
		}
	}

	return fmt.Errorf("arguments are not allowlisted for %s", cleanPath)
}
