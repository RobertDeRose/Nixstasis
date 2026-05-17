// Package main is the entry point for the Nixstasis client.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"runtime/trace"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/logging"
)

type configContextKey struct{}

var rootCmd = &cobra.Command{
	Use:           "nixstasis",
	Short:         "Nixstasis client for IoT monitoring",
	SilenceErrors: true,
	PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
		var err error
		var defaultCfg *config.Config
		var cfg *config.Config

		defaultCfg, err = config.GetDefaultConfig()
		if err != nil {
			return fmt.Errorf("failed to get default config: %w", err)
		}
		logging.Setup(defaultCfg.Log.Level, defaultCfg.Log.Format)

		if shouldSkipConfig(cmd) {
			cmd.SetContext(context.WithValue(cmd.Context(), configContextKey{}, defaultCfg))
			return nil
		}

		cfg, err = config.Load()
		if err != nil {
			return fmt.Errorf("failed to load configuration: %w", err)
		}
		slog.Debug("Configuration loaded", "config", cfg)
		cmd.SetContext(context.WithValue(cmd.Context(), configContextKey{}, cfg))

		return nil
	},
}

func main() {
	os.Exit(runMain())
}

func runMain() int {
	// Go 1.26 Flight Recorder
	// Capture execution traces in a ring buffer
	rec := trace.NewFlightRecorder(trace.FlightRecorderConfig{})

	if err := rec.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "failed to start flight recorder: %v\n", err)
	}

	// Ensure we stop the recorder
	defer rec.Stop()

	if err := run(); err != nil {
		if shouldWriteFlightRecorderTrace() {
			writeFlightRecorderTrace(rec)
		}
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	return 0
}

func run() error {
	return rootCmd.Execute()
}

func commandConfig(cmd *cobra.Command) (*config.Config, error) {
	if cmd == nil {
		return nil, fmt.Errorf("command is nil")
	}
	cfg, ok := cmd.Context().Value(configContextKey{}).(*config.Config)
	if !ok || cfg == nil {
		return nil, fmt.Errorf("config not loaded")
	}
	return cfg, nil
}

func shouldWriteFlightRecorderTrace() bool {
	return os.Getenv("NIXSTASIS_WRITE_TRACE_ON_ERROR") == "true"
}

func writeFlightRecorderTrace(rec *trace.FlightRecorder) {
	dir := filepath.Join(os.TempDir(), "nixstasis")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create trace directory: %v\n", err)
		return
	}

	f, err := os.CreateTemp(dir, "trace-*.out")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create trace file: %v\n", err)
		return
	}
	success := false
	defer func() {
		if !success {
			_ = os.Remove(f.Name())
		}
	}()
	defer f.Close()

	if _, err := rec.WriteTo(f); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write flight recorder trace: %v\n", err)
		return
	}
	success = true
	fmt.Fprintf(os.Stderr, "flight recorder trace written to %s\n", f.Name())
}

func shouldSkipConfig(cmd *cobra.Command) bool {
	if cmd == nil {
		return false
	}
	name := cmd.Name()
	if name != "test" && name != "repl" {
		return false
	}
	for parent := cmd.Parent(); parent != nil; parent = parent.Parent() {
		if parent.Name() == "script" {
			return true
		}
	}
	return false
}
