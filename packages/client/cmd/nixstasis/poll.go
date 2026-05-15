package main

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"os"
	"os/signal"
	"sync"
	"syscall"
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
	RunE: func(cmd *cobra.Command, _ []string) error {
		cfg, err := commandConfig(cmd)
		if err != nil {
			return err
		}
		return runPoll(cfg)
	},
}

func init() {
	rootCmd.AddCommand(pollCmd)
}

func runPoll(cfg *config.Config) error {
	startTime := time.Now()
	slog.Info("Starting polling service")

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// 1. Load Identity
	store := identity.NewStore(config.IdentityPath())
	credentials, err := store.Load()
	if err != nil {
		return fmt.Errorf("no device identity found, please run 'nixstasis register' first: %w", err)
	}
	if credentials.UUID == "" || credentials.Token == "" {
		return fmt.Errorf("device credentials are incomplete, please run 'nixstasis register' after approval")
	}
	uuid := credentials.UUID
	slog.Info("Device identity loaded", "uuid", uuid)

	// 2. Setup Components
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

	var consecutiveFailures int
	interval := pollInterval(cfg)

	// Run immediately once
	if err := pollOnce(ctx, cfg, client, executor, frpManager, cmdHandler, uuid, credentials.Token, startTime); err != nil {
		slog.Error("Initial poll failed", "error", err)
		consecutiveFailures++
	}
	nextDelay := nextPollDelay(consecutiveFailures, interval)
	timer := time.NewTimer(nextDelay)
	defer timer.Stop()

	for {
		select {
		case <-ctx.Done():
			slog.Info("Shutting down polling service", "reason", ctx.Err())
			return nil
		case <-timer.C:
			if err := pollOnce(ctx, cfg, client, executor, frpManager, cmdHandler, uuid, credentials.Token, startTime); err != nil {
				consecutiveFailures++
				slog.Error("Poll failed", "error", err, "consecutive_failures", consecutiveFailures)
			} else {
				consecutiveFailures = 0
			}
			nextDelay = nextPollDelay(consecutiveFailures, interval)
			if consecutiveFailures > 0 {
				slog.Info("Backing off before next poll", "delay", nextDelay, "consecutive_failures", consecutiveFailures)
			}
			timer.Reset(nextDelay)
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

const maxBackoff = 5 * time.Minute

func nextPollDelay(failures int, base time.Duration) time.Duration {
	if failures <= 0 {
		return base
	}
	return backoffDelay(failures, base)
}

// backoffDelay returns the full delay with jitter based on the number of
// consecutive poll failures.
func backoffDelay(failures int, base time.Duration) time.Duration {
	if failures <= 0 {
		return base
	}

	// Exponential: base * 2^(failures-1), capped at maxBackoff.
	delay := base
	for i := 1; i < failures && delay < maxBackoff; i++ {
		delay *= 2
	}
	if delay > maxBackoff {
		delay = maxBackoff
	}

	jitterWindow := delay / 2
	if jitterWindow <= 1 {
		return delay
	}

	// Add jitter: +/- 25% of delay, clamped so the result is always positive.
	jitter := time.Duration(rand.Int64N(int64(jitterWindow))) - delay/4
	d := delay + jitter
	if d <= 0 {
		d = 1
	}
	return d
}

func pollOnce(ctx context.Context, cfg *config.Config, client *transport.Client, executor *script.Executor, frpManager *frp.Manager, cmdHandler *commands.Handler, uuid string, frpAuthToken string, startTime time.Time) error {
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

	scripts, err := script.DiscoverScripts(cfg.Scripts.Dir)
	if err != nil {
		slog.Warn("Error discovering scripts", "error", err)
	}
	scriptReports, scriptErrors := runScripts(ctx, executor, scripts)

	// Get FRP Status
	frpStatus := frpManager.GetStatus()

	// Construct Payload
	payload := telemetry.Payload{
		Device: telemetry.DeviceStatus{
			Identity: id,
			Uptime:   uptimeSeconds(startTime),
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

	// Re-read FRP status right before acting to avoid TOCTOU race with
	// the status snapshot sent in the telemetry payload above.
	currentFRPStatus := frpManager.GetStatus()

	if resp.RemoteAccessRequested {
		if !currentFRPStatus.Active {
			slog.Info("Server requested remote access, starting FRP")
			configPath := config.FRPCConfigPath()
			frpConfig := runtimeFRPConfig(cfg.FRP, mac, frpAuthToken)
			if err := frpManager.Start(configPath, frpConfig); err != nil {
				slog.Error("Failed to start FRP", "error", err)
			}
		}
	} else {
		if currentFRPStatus.Active {
			slog.Info("Server disabled remote access, stopping FRP")
			if err := frpManager.Stop(); err != nil {
				slog.Error("Failed to stop FRP", "error", err)
			}
		}
	}

	return nil
}

func runtimeFRPConfig(base config.FRPConfig, mac string, authToken string) config.FRPConfig {
	frpConfig := base
	if frpConfig.AuthToken == "" {
		frpConfig.AuthToken = authToken
	}
	if frpConfig.Name == "" {
		frpConfig.Name = identity.GenerateDeviceName(mac)
	}
	return frpConfig
}

func runScripts(ctx context.Context, executor *script.Executor, scripts []script.ScriptInfo) (reports map[string]telemetry.Report, errors []string) {
	scripts = script.SelectLatestScripts(scripts)

	scriptStart := time.Now()
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

	type payloadHydrationResult struct {
		index   int
		cmd     transport.CommandRequest
		failure *transport.CommandResult
	}

	const maxConcurrentPayloadFetches = 8

	results := make([]payloadHydrationResult, len(cmds))
	jobs := make(chan int, len(cmds))
	workerCount := min(maxConcurrentPayloadFetches, len(cmds))
	var wg sync.WaitGroup

	for range workerCount {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for idx := range jobs {
				cmd := cmds[idx]
				result := payloadHydrationResult{index: idx, cmd: cmd}

				if cmd.PayloadRef == "" || cmd.Payload != nil {
					results[idx] = result
					continue
				}

				if err := transport.ValidatePayloadRef(cmd.PayloadRef); err != nil {
					result.failure = &transport.CommandResult{
						CommandID: cmd.CommandID,
						Status:    transport.CommandStatusFailed,
						Error:     "invalid_payload_ref: " + err.Error(),
					}
					results[idx] = result
					continue
				}

				fetchCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
				payload, err := fetcher.FetchCommandPayload(fetchCtx, uuid, cmd.PayloadRef)
				cancel()
				if err != nil {
					result.failure = &transport.CommandResult{
						CommandID: cmd.CommandID,
						Status:    transport.CommandStatusFailed,
						Error:     "payload_fetch_failed: " + err.Error(),
					}
					results[idx] = result
					continue
				}

				cmd.Payload = payload
				result.cmd = cmd
				results[idx] = result
			}
		}()
	}

	for idx := range cmds {
		jobs <- idx
	}
	close(jobs)
	wg.Wait()

	ready := make([]transport.CommandRequest, 0, len(cmds))
	failures := make([]transport.CommandResult, 0)
	for _, result := range results {
		if result.failure != nil {
			failures = append(failures, *result.failure)
			continue
		}
		ready = append(ready, result.cmd)
	}

	return ready, failures
}

func uptimeSeconds(startTime time.Time) int64 {
	return int64(time.Since(startTime).Seconds())
}
