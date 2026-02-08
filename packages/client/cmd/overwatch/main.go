// Package main is the entry point for the Nixstasis client.
package main

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"runtime/trace"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/logging"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfg *config.Config

var rootCmd = &cobra.Command{
	Use:           "nixstasis",
	Short:         "Nixstasis Client for IoT Monitoring",
	SilenceErrors: true,
	PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
		var err error
		var defaultCfg *config.Config

		defaultCfg, err = config.GetDefaultConfig()
		if err != nil {
			return fmt.Errorf("failed to get default config: %w", err)
		}
		logging.Setup(defaultCfg.Log.Level, defaultCfg.Log.Format)

		if shouldSkipConfig(cmd) {
			cfg = defaultCfg
			return nil
		}

		cfg, err = config.Load()
		if err != nil {
			var configFileNotFoundErr viper.ConfigFileNotFoundError
			if errors.As(err, &configFileNotFoundErr) {
				slog.Warn("No configuration file found, using defaults")
				cfg = defaultCfg
			} else {
				return fmt.Errorf("failed to load configuration: %w", err)
			}
		} else {
			slog.Debug("Configuration loaded", "config", cfg)
		}

		return nil
	},
}

func main() {
	os.Exit(runMain())
}

func runMain() int {
	// Go 1.25 Flight Recorder
	// Capture execution traces in a ring buffer
	rec := trace.NewFlightRecorder(trace.FlightRecorderConfig{})

	if err := rec.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "failed to start flight recorder: %v\n", err)
	}

	// Ensure we stop the recorder
	defer rec.Stop()

	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	return 0
}

func run() error {
	return rootCmd.Execute()
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
