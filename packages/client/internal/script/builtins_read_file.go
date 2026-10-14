package script

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

const maxReadFileBytes = 64 * 1024

var protectedReadFileRoots = []string{
	"/etc/nixstasis",
	"/run/nixstasis",
}

func (r *Runtime) readFileBuiltin(
	thread *starlark.Thread,
	_ *starlark.Builtin,
	args starlark.Tuple,
	kwargs []starlark.Tuple,
) (starlark.Value, error) {
	var path string
	if err := starlark.UnpackArgs("read_file", args, kwargs, "path", &path); err != nil {
		return nil, err
	}

	resolved, err := r.resolveReadFile(path)
	if err != nil {
		return nil, err
	}

	file, err := openReadFile(resolved)
	if err != nil {
		return nil, fmt.Errorf("open allowlisted file: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat allowlisted file: %w", err)
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("read_file requires a regular file")
	}
	ctx := runtimeContext(thread)
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	stop := context.AfterFunc(ctx, func() { _ = file.Close() })
	defer stop()

	data, err := io.ReadAll(io.LimitReader(file, maxReadFileBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read allowlisted file: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(data) > maxReadFileBytes {
		return nil, fmt.Errorf("allowlisted file exceeds %d-byte read limit", maxReadFileBytes)
	}

	return starlark.String(strings.TrimSpace(string(data))), nil
}

func (r *Runtime) resolveReadFile(requested string) (string, error) {
	if len(r.config.ReadFileAllowlist) == 0 {
		return "", fmt.Errorf("read_file capability is not configured")
	}
	if strings.TrimSpace(requested) == "" {
		return "", fmt.Errorf("read_file path is required")
	}

	requestedCandidate := requested
	if !filepath.IsAbs(requestedCandidate) {
		requestedCandidate = filepath.Join(r.config.ExecWorkDir, requestedCandidate)
	}
	if protectedReadFilePath(requestedCandidate) {
		return "", fmt.Errorf("read_file path is protected: %s", requested)
	}

	requestedPath := filepath.Clean(requestedCandidate)
	if protectedReadFilePath(requestedPath) {
		return "", fmt.Errorf("read_file path is protected: %s", requested)
	}

	for _, allowed := range r.config.ReadFileAllowlist {
		if !filepath.IsAbs(allowed) {
			continue
		}

		allowedPath := filepath.Clean(allowed)
		if protectedReadFilePath(allowedPath) {
			continue
		}
		if requestedPath == allowedPath {
			return requestedPath, nil
		}
	}

	return "", fmt.Errorf("read_file path is not allowlisted: %s", requested)
}

func protectedReadFilePath(path string) bool {
	clean := filepath.Clean(path)
	for _, root := range protectedReadFileRoots {
		if clean == root || strings.HasPrefix(clean, root+string(os.PathSeparator)) {
			return true
		}
	}
	return false
}
