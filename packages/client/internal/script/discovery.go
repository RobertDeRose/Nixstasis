package script

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

const (
	systemScriptsDir = "/usr/libexec/nixstasis/scripts"
	userScriptsDir   = "$HOME/.nixstasis/scripts"
)

// DefaultScriptDirs returns the search paths for stary scripts.
func DefaultScriptDirs(customDir string) []string {
	dirs := []string{systemScriptsDir, os.ExpandEnv(userScriptsDir)}
	if customDir != "" {
		dirs = append([]string{customDir}, dirs...)
	}

	return dirs
}

// DefaultInstallDir returns the default installation directory for stary scripts.
func DefaultInstallDir() string {
	return os.ExpandEnv(userScriptsDir)
}

// DiscoverScripts scans script directories and returns valid stary scripts.
func DiscoverScripts(customDir string) ([]ScriptInfo, error) {
	searchPaths := DefaultScriptDirs(customDir)
	seen := make(map[string]bool)
	var scripts []ScriptInfo

	for _, dir := range searchPaths {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if !os.IsNotExist(err) {
				slog.Debug("Failed to read scripts directory", "path", dir, "error", err)
			}
			continue
		}

		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			if !strings.HasSuffix(entry.Name(), ".stary") {
				continue
			}

			path := filepath.Join(dir, entry.Name())
			if seen[path] {
				continue
			}

			fm, _, err := ParseStaryFile(path)
			if err != nil {
				slog.Warn("Skipping invalid stary file", "path", path, "error", err)
				continue
			}

			scripts = append(scripts, ScriptInfo{
				Name:    fm.Name,
				Version: fm.Version,
				Path:    path,
			})
			seen[path] = true
		}
	}

	return scripts, nil
}

// ResolveScript resolves a selector by path or script name.
func ResolveScript(selector string, scripts []ScriptInfo) (ScriptInfo, error) {
	if selector == "" {
		return ScriptInfo{}, fmt.Errorf("script selector is empty")
	}

	if _, err := os.Stat(selector); err == nil {
		fm, _, err := ParseStaryFile(selector)
		if err != nil {
			return ScriptInfo{}, err
		}
		return ScriptInfo{Name: fm.Name, Version: fm.Version, Path: selector}, nil
	}

	var matches []ScriptInfo
	for _, script := range scripts {
		if script.Name == selector {
			matches = append(matches, script)
		}
	}

	if len(matches) == 1 {
		return matches[0], nil
	}
	if len(matches) > 1 {
		if latest, ok := LatestScript(matches, selector); ok {
			return latest, nil
		}
	}

	return ScriptInfo{}, fmt.Errorf("script not found: %s", selector)
}
