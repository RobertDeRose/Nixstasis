// Package script provides Starlark execution support and builtins.
package script

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

func (r *Runtime) execCmdBuiltin(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	var cmdName string
	var argList *starlark.List

	if err := starlark.UnpackArgs("exec_cmd", args, kwargs,
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

	ctx, cancel := context.WithTimeout(context.Background(), r.config.Timeout)
	defer cancel()

	// #nosec G204 -- command is resolved from an explicit pinned allowlist.
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir = r.config.ExecWorkDir
	cmd.Env = append([]string(nil), r.config.ExecEnv...)

	if r.config.ExecUser != nil && os.Geteuid() == 0 {
		setExecUser(cmd, r.config.ExecUser)
	}

	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, fmt.Errorf("command timed out after %s", r.config.Timeout)
	}
	if err != nil {
		return nil, fmt.Errorf("command failed: %w", err)
	}

	return starlark.String(strings.TrimSpace(string(output))), nil
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
