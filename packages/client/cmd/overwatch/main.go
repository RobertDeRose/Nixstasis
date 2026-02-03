// Package main is the entry point for the Nixstasis client.
package main

import (
	"fmt"
	"log/slog"
	"os"

	"runtime/trace"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/logging"
	"github.com/spf13/cobra"
)

var cfg *config.Config

var rootCmd = &cobra.Command{
	Use:   "nixstasis",
	Short: "Nixstasis Client for IoT Monitoring",
	PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
		var err error
		cfg, err = config.Load()
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}
		logging.Setup(cfg.Log.Level, cfg.Log.Format)
		slog.Debug("Configuration loaded", "config", cfg)
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
		fmt.Println(err)
		return 1
	}

	return 0
}

func run() error {
	return rootCmd.Execute()
}
