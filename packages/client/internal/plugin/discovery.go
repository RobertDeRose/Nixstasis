// Package plugin handles discovery and execution of external telemetry plugins.
package plugin

import (
	"log/slog"
	"os"
	"path/filepath"
)

// DiscoverPlugins scans the standard directories for valid plugins.
// It returns a list of paths to directories containing a valid manifest.json.
func DiscoverPlugins(customDir string) ([]string, error) {
	// 1. Define search paths
	searchPaths := []string{
		"/usr/libexec/nixstasis/plugins",         // System
		os.ExpandEnv("$HOME/.nixstasis/plugins"), // User/Dev
	}

	if customDir != "" {
		// Prepend custom dir if provided (e.g. from config)
		searchPaths = append([]string{customDir}, searchPaths...)
	}

	var validPluginDirs []string
	seen := make(map[string]bool)

	for _, path := range searchPaths {
		entries, err := os.ReadDir(path)
		if err != nil {
			if !os.IsNotExist(err) {
				slog.Debug("Failed to read plugin directory", "path", path, "error", err)
			}
			continue
		}

		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}

			pluginDir := filepath.Join(path, entry.Name())
			manifestPath := filepath.Join(pluginDir, "manifest.json")

			// Check if manifest exists
			if _, err := os.Stat(manifestPath); err == nil {
				// Deduplicate
				if !seen[pluginDir] {
					validPluginDirs = append(validPluginDirs, pluginDir)
					seen[pluginDir] = true
					slog.Debug("Discovered plugin", "path", pluginDir)
				}
			}
		}
	}

	return validPluginDirs, nil
}
