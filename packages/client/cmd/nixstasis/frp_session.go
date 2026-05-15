package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const defaultSessionTimeout = 1 * time.Hour

// execCommand allows test injection for the frpc child process.
var execCommand = exec.CommandContext

var frpSessionCmd = &cobra.Command{
	Use:    "frp-session",
	Short:  "Run an FRP tunnel session with timeout (used by systemd transient unit)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, _ []string) error {
		cfg, err := commandConfig(cmd)
		if err != nil {
			return err
		}
		return runFRPSession(cfg)
	},
}

func init() {
	rootCmd.AddCommand(frpSessionCmd)
}

func runFRPSession(cfg *config.Config) error {
	configPath := config.FRPCConfigPath()
	frpcBinary := config.FRPCBinaryPath()
	timeout := defaultSessionTimeout

	if _, err := os.Stat(configPath); err != nil {
		return fmt.Errorf("frpc config not found: %w", err)
	}
	if _, err := os.Stat(frpcBinary); err != nil {
		return fmt.Errorf("frpc binary not found: %w", err)
	}

	_ = cfg // reserved for future use (e.g., configurable timeout)

	slog.Info("Starting FRP session", "config", configPath, "timeout", timeout)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	// Also handle SIGTERM/SIGINT for graceful shutdown when systemd stops the unit
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		select {
		case sig := <-sigCh:
			slog.Info("Received signal, stopping FRP session", "signal", sig)
			cancel()
		case <-ctx.Done():
		}
	}()

	cmd := execCommand(ctx, frpcBinary, "-c", configPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	// Inherit environment — systemd-run --setenv passes the template vars
	// directly to this process, and frpc reads them via {{ .Envs.* }}.

	if err := cmd.Run(); err != nil {
		// Context cancellation (timeout or signal) is a normal exit path.
		if ctx.Err() != nil {
			slog.Info("FRP session ended", "reason", ctx.Err())
			return nil
		}
		return fmt.Errorf("frpc exited with error: %w", err)
	}

	slog.Info("FRP session ended normally")
	return nil
}
