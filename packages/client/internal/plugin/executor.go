package plugin

import (
	"context"
	json "encoding/json/v2"
	"log/slog"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

// Executor handles the execution of plugins.
type Executor struct {
	Merger *Merger
}

// NewExecutor creates a new Executor.
func NewExecutor() *Executor {
	return &Executor{
		Merger: NewMerger(),
	}
}

// ExecutionResult contains the result of a single plugin execution.
type ExecutionResult struct {
	PluginName string
	Manifest   *Manifest
	Output     map[string]any
	Error      error
}

// ExecutePlugins runs the given plugins in parallel and aggregates their output.
// It enforces a timeout per plugin.
func (e *Executor) ExecutePlugins(ctx context.Context, plugins []string) (map[string]Report, error) {
	results := make(chan ExecutionResult, len(plugins))
	var wg sync.WaitGroup

	// timeout := 10 * time.Second // Global timeout cap or per-plugin? Spec SC-004 says "timeout (e.g. 5s)"

	for _, pluginDir := range plugins {
		wg.Add(1)
		go func(dir string) {
			defer wg.Done()

			// Load Manifest first
			manifestPath := filepath.Join(dir, "manifest.json")
			manifest, err := LoadManifest(manifestPath)
			if err != nil {
				slog.Error("Failed to load plugin manifest", "dir", dir, "error", err)
				return
			}

			// Execute each binary defined in manifest (sequentially per plugin, or parallel?)
			// Usually a plugin has one entry point or we run them all.
			// Let's run all executables and merge their output into this plugin's payload.

			pluginPayload := make(map[string]any)

			for _, binName := range manifest.Executables {
				outputMap, err := e.executeBinary(ctx, dir, binName, manifest.Name)
				if err != nil {
					// We continue to next executable, but maybe log this one failed
					continue
				}

				// Merge into plugin payload
				pluginPayload, err = e.Merger.Merge(pluginPayload, outputMap)
				if err != nil {
					slog.Error("Failed to merge plugin output", "plugin", manifest.Name, "error", err)
				}
			}

			results <- ExecutionResult{
				PluginName: manifest.Name,
				Manifest:   manifest,
				Output:     pluginPayload,
				Error:      nil,
			}
		}(pluginDir)
	}

	wg.Wait()
	close(results)

	// Aggregate all plugin results into one "plugins" map
	// The requirement is "merge JSON output... into the final telemetry payload".
	// Data Model says: `plugins map[string]object`.
	// So we key it by Plugin Name?
	// e.g. plugins: { "system_stats": { ... }, "postgres_monitor": { ... } }
	// This avoids collisions between plugins.

	finalPluginsMap := make(map[string]Report)

	for res := range results {
		if res.Error != nil {
			continue
		}
		if len(res.Output) > 0 {
			finalPluginsMap[res.PluginName] = Report{
				Data: res.Output,
				Meta: res.Manifest,
			}
		}
	}

	return finalPluginsMap, nil
}

func (e *Executor) executeBinary(ctx context.Context, dir, binName, pluginName string) (map[string]any, error) {
	binPath := filepath.Join(dir, binName)

	// Run with timeout
	c, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	// G204: Subprocess launched with variable.
	// We trust the manifest content as it is part of the installed plugin.
	// #nosec G204
	cmd := exec.CommandContext(c, binPath)
	outputBytes, err := cmd.Output()

	if err != nil {
		slog.Warn("Plugin executable failed", "plugin", pluginName, "bin", binName, "error", err)
		return nil, err
	}

	var outputMap map[string]any
	if err := json.Unmarshal(outputBytes, &outputMap); err != nil {
		slog.Warn("Plugin output invalid JSON", "plugin", pluginName, "bin", binName, "error", err)
		return nil, err
	}

	return outputMap, nil
}
