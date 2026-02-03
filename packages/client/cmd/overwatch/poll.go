package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/sfero-nixstasis/client/internal/frp"
	"github.com/sfero-nixstasis/client/internal/identity"
	"github.com/sfero-nixstasis/client/internal/plugin"
	"github.com/sfero-nixstasis/client/internal/transport"
	"github.com/spf13/cobra"
)

var pollCmd = &cobra.Command{
	Use:   "poll",
	Short: "Start the telemetry polling loop",
	Run: func(_ *cobra.Command, _ []string) {
		runPoll()
	},
}

func init() {
	rootCmd.AddCommand(pollCmd)
}

var startTime = time.Now()

func runPoll() {
	slog.Info("Starting polling service")

	// 1. Load Identity
	store := identity.NewStore("/etc/nixstasis/id") // TODO: Config
	uuid, err := store.LoadUUID()
	if err != nil {
		slog.Warn("No device identity found. Please run 'nixstasis register' first.", "error", err)
		// We exit here because without a UUID we cannot report telemetry.
		// In a production daemon, we might want to trigger registration or wait.
		os.Exit(1)
	}
	slog.Info("Device identity loaded", "uuid", uuid)

	// 2. Setup Components
	if cfg == nil {
		slog.Error("Config not loaded")
		os.Exit(1)
	}
	client := transport.NewClient(cfg.API)
	executor := plugin.NewExecutor()
	frpManager := frp.NewManager()

	// 3. Discover Plugins
	// We currently don't expose a custom plugin dir in config, so we use defaults.
	discoveredPlugins, err := plugin.DiscoverPlugins("")
	if err != nil {
		slog.Warn("Error discovering plugins", "error", err)
	}
	slog.Info("Discovered plugins", "count", len(discoveredPlugins))

	// 4. Polling Loop
	interval := 30 * time.Second
	// TODO: Configurable interval
	// if cfg.PollInterval > 0 { interval = cfg.PollInterval }

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	// Run immediately once
	if err := pollOnce(client, executor, frpManager, discoveredPlugins, uuid); err != nil {
		slog.Error("Initial poll failed", "error", err)
	}

	for range ticker.C {
		if err := pollOnce(client, executor, frpManager, discoveredPlugins, uuid); err != nil {
			slog.Error("Poll failed", "error", err)
		}
	}
}

func pollOnce(client *transport.Client, executor *plugin.Executor, frpManager *frp.Manager, plugins []string, uuid string) error {
	pollStart := time.Now()

	// Re-detect dynamic identity details (IP might change)
	mac, err := identity.GetPrimaryMAC()
	if err != nil {
		slog.Warn("Failed to get primary MAC", "error", err)
	}
	ip, err := identity.GetPrimaryIP()
	if err != nil {
		slog.Warn("Failed to get primary IP", "error", err)
	}
	id := identity.DeviceIdentity{
		UUID:       uuid,
		MACAddress: mac,
		IPAddress:  ip,
		Name:       identity.GenerateDeviceName(mac),
	}

	// Execute Plugins
	ctx := context.Background() // TODO: Timeout for whole poll?
	pluginResults, err := executor.ExecutePlugins(ctx, plugins)
	if err != nil {
		slog.Error("Error executing plugins", "error", err)
		// We continue to send what we have (or empty) + device status
	}

	// Get FRP Status
	frpStatus := frpManager.GetStatus()

	// Construct Payload
	payload := plugin.TelemetryPayload{
		Device: plugin.DeviceStatus{
			Identity: id,
			Uptime:   getUptime(),
		},
		Plugins: pluginResults,
		Meta: plugin.PollMeta{
			Timestamp: time.Now(),
			Duration:  time.Since(pollStart).String(),
		},
	}

	slog.Debug("Sending telemetry", "plugins", len(payload.Plugins), "uptime", payload.Device.Uptime)
	resp, err := client.Poll(ctx, uuid, payload, frpStatus)
	if err != nil {
		return err
	}

	if resp.RemoteAccessRequested {
		if !frpStatus.Active {
			slog.Info("Server requested remote access, starting FRP")
			// Assuming default config location for now
			configPath := "/etc/nixstasis/frpc.toml"
			// Check if config exists, if not, maybe we can't start?
			// Or we assume it's there.
			if err := frpManager.Start(ctx, configPath); err != nil {
				slog.Error("Failed to start FRP", "error", err)
			}
		}
	} else {
		if frpStatus.Active {
			slog.Info("Server disabled remote access, stopping FRP")
			if err := frpManager.Stop(); err != nil {
				slog.Error("Failed to stop FRP", "error", err)
			}
		}
	}

	return nil
}

func getUptime() int64 {
	// Simple process uptime for now
	return int64(time.Since(startTime).Seconds())
}
