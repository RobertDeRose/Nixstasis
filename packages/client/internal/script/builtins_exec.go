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

	if !allowedCommand(cmdName, r.config.ExecAllowlist) {
		return nil, fmt.Errorf("command is not allowed: %s", cmdName)
	}

	argv := []string{cmdName}
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

	// #nosec G204 -- command is restricted to an operator-configured allowlist.
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Env = os.Environ()

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

func allowedCommand(cmd string, allowlist []string) bool {
	base := filepath.Base(cmd)
	for _, allowed := range allowlist {
		if base == allowed {
			return true
		}
		if strings.HasSuffix(allowed, ".") && strings.HasPrefix(base, allowed) {
			return true
		}
	}

	return false
}
