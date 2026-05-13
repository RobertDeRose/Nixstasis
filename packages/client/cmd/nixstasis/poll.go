package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/commands"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
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
	store := identity.NewStore(config.IdentityPath())
	credentials, err := store.Load()
	if err != nil {
		slog.Warn("No device identity found. Please run 'nixstasis register' first.", "error", err)
		// We exit here because without a UUID we cannot report telemetry.
		// In a production daemon, we might want to trigger registration or wait.
		os.Exit(1)
	}
	if credentials.UUID == "" || credentials.Token == "" {
		slog.Warn("Device credentials are incomplete. Please run 'nixstasis register' after approval.")
		os.Exit(1)
	}
	uuid := credentials.UUID
	slog.Info("Device identity loaded", "uuid", uuid)

	// 2. Setup Components
	if cfg == nil {
		slog.Error("Config not loaded")
		os.Exit(1)
	}
	client := transport.NewClient(cfg.API)
	client.SetAPIKey(credentials.Token)
	executor := script.NewExecutor(script.RuntimeConfig{
		Timeout:              5 * time.Second,
		WarnAfter:            3 * time.Second,
		MQTTBroker:           runtimeMQTTBroker(cfg.Runtime.MQTTBroker),
		ExecCommandAllowlist: cfg.Runtime.ExecCommands,
		ExecWorkDir:          cfg.Runtime.ExecWorkDir,
		ExecEnv:              cfg.Runtime.ExecEnv,
		MQTTPublishTopics:    cfg.Runtime.MQTTPublishTopics,
		MQTTSubscribeTopics:  cfg.Runtime.MQTTSubscribeTopics,
	})
	frpManager := frp.NewManager()
	cmdHandler := commands.NewHandlerWithAuthorizedKeys(cfg.Scripts.Dir, cfg.Runtime.AuthorizedKeysPath)

	ticker := time.NewTicker(pollInterval(cfg))
	defer ticker.Stop()

	// Run immediately once
	if err := pollOnce(client, executor, frpManager, cmdHandler, uuid); err != nil {
		slog.Error("Initial poll failed", "error", err)
	}

	for range ticker.C {
		if err := pollOnce(client, executor, frpManager, cmdHandler, uuid); err != nil {
			slog.Error("Poll failed", "error", err)
		}
	}
}

func runtimeMQTTBroker(configured string) string {
	if configured != "" {
		return configured
	}
	return os.Getenv("NIXSTASIS_MQTT_BROKER")
}

func pollInterval(cfg *config.Config) time.Duration {
	if cfg != nil && cfg.Poll.Interval > 0 {
		return cfg.Poll.Interval
	}
	return 30 * time.Second
}

func pollOnce(client *transport.Client, executor *script.Executor, frpManager *frp.Manager, cmdHandler *commands.Handler, uuid string) error {
	pollStart := time.Now()
	ctx := context.Background()

	// Re-detect dynamic identity details (IP might change)
	mac, err := identity.GetPrimaryMAC()
	if err != nil {
		slog.Warn("Failed to get primary MAC", "error", err)
	}
	ip, err := identity.GetPrimaryIP(ctx)
	if err != nil {
		slog.Warn("Failed to get primary IP", "error", err)
	}
	id := identity.DeviceIdentity{
		UUID:       uuid,
		MACAddress: mac,
		IPAddress:  ip,
		Name:       identity.GenerateDeviceName(mac),
	}

	scripts, err := script.DiscoverScripts(cfg.Scripts.Dir)
	if err != nil {
		slog.Warn("Error discovering scripts", "error", err)
	}
	scriptReports, scriptErrors := runScripts(executor, scripts)

	// Get FRP Status
	frpStatus := frpManager.GetStatus()

	// Construct Payload
	payload := telemetry.Payload{
		Device: telemetry.DeviceStatus{
			Identity: id,
			Uptime:   getUptime(),
		},
		Scripts: scriptReports,
		Meta: telemetry.PollMeta{
			Timestamp: time.Now(),
			Duration:  time.Since(pollStart).String(),
			Errors:    scriptErrors,
		},
	}

	slog.Debug("Sending telemetry", "scripts", len(payload.Scripts), "uptime", payload.Device.Uptime)
	resp, err := client.Poll(ctx, uuid, payload, frpStatus)
	if err != nil {
		return err
	}

	if err := handleCommandResponses(ctx, client, client, cmdHandler, uuid, resp.Commands); err != nil {
		slog.Error("Failed to handle command responses", "error", err)
	}

	if resp.RemoteAccessRequested {
		if !frpStatus.Active {
			slog.Info("Server requested remote access, starting FRP")
			// Assuming default config location for now
			configPath := config.FRPCConfigPath()
			frpConfig := runtimeFRPConfig(cfg.FRP, mac)
			// Check if config exists, if not, maybe we can't start?
			// Or we assume it's there.
			if err := frpManager.StartWithConfig(ctx, configPath, frpConfig); err != nil {
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

func runtimeFRPConfig(base config.FRPConfig, mac string) config.FRPConfig {
	frpConfig := base
	if frpConfig.Name == "" {
		frpConfig.Name = identity.GenerateDeviceName(mac)
	}
	return frpConfig
}

func runScripts(executor *script.Executor, scripts []script.ScriptInfo) (reports map[string]telemetry.Report, errors []string) {
	scripts = script.SelectLatestScripts(scripts)

	scriptStart := time.Now()
	ctx := context.Background() // TODO: Timeout for whole poll?
	scriptResults, err := executor.ExecuteScripts(ctx, scripts)
	if err != nil {
		slog.Error("Error executing scripts", "error", err)
	}
	scriptDuration := time.Since(scriptStart)
	slog.Info(fmt.Sprintf("polled using %d scripts in %d ms", len(scripts), scriptDuration.Milliseconds()))
	if scriptDuration > 5*time.Second {
		slog.Warn("script polling exceeded 5s", "duration_ms", scriptDuration.Milliseconds())
	}

	scriptReports := make(map[string]telemetry.Report)
	var scriptErrors []string
	for name, res := range scriptResults {
		scriptReports[name] = script.ToReport(res)
		if res.Status != script.StatusSuccess && res.Error != nil {
			scriptErrors = append(scriptErrors, name+": "+res.Error.Message)
		}
	}

	return scriptReports, scriptErrors
}

type commandExecutor interface {
	ExecuteBatch(ctx context.Context, commands []transport.CommandRequest) []transport.CommandResult
}

type commandResultsClient interface {
	SendCommandResults(ctx context.Context, uuid string, results []transport.CommandResult) error
}

type commandPayloadFetcher interface {
	FetchCommandPayload(ctx context.Context, uuid, ref string) (*transport.CommandPayload, error)
}

func handleCommandResponses(ctx context.Context, client commandResultsClient, fetcher commandPayloadFetcher, handler commandExecutor, uuid string, cmds []transport.CommandRequest) error {
	if len(cmds) == 0 {
		return nil
	}
	if len(cmds) > commands.MaxCommandsPerPoll {
		cmds = cmds[:commands.MaxCommandsPerPoll]
	}

	ready, preResults := hydrateCommandPayloads(ctx, fetcher, uuid, cmds)
	results := handler.ExecuteBatch(ctx, ready)
	results = append(results, preResults...)

	sendCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	return client.SendCommandResults(sendCtx, uuid, results)
}

func hydrateCommandPayloads(ctx context.Context, fetcher commandPayloadFetcher, uuid string, cmds []transport.CommandRequest) ([]transport.CommandRequest, []transport.CommandResult) {
	if fetcher == nil {
		return cmds, nil
	}

	var ready []transport.CommandRequest
	var failures []transport.CommandResult

	for _, cmd := range cmds {
		if cmd.PayloadRef == "" || cmd.Payload != nil {
			ready = append(ready, cmd)
			continue
		}

		fetchCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		payload, err := fetcher.FetchCommandPayload(fetchCtx, uuid, cmd.PayloadRef)
		cancel()
		if err != nil {
			failures = append(failures, transport.CommandResult{
				CommandID: cmd.CommandID,
				Status:    transport.CommandStatusFailed,
				Error:     "payload_fetch_failed: " + err.Error(),
			})
			continue
		}

		cmd.Payload = payload
		ready = append(ready, cmd)
	}

	return ready, failures
}

func getUptime() int64 {
	// Simple process uptime for now
	return int64(time.Since(startTime).Seconds())
}
