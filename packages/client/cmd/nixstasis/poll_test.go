package main

import (
	"context"
	"fmt"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/commandpolicy"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

type fakeCommandHandler struct {
	called  bool
	results []transport.CommandResult
}

func TestPollIntervalUsesConfiguredValue(t *testing.T) {
	configured := &config.Config{Poll: config.PollConfig{Interval: 45 * time.Second}}
	if got := pollInterval(configured); got != 45*time.Second {
		t.Fatalf("pollInterval() = %s", got)
	}

	if got := pollInterval(&config.Config{}); got != 30*time.Second {
		t.Fatalf("pollInterval() fallback = %s", got)
	}
}

func TestInitialCommandPolicyUsesPersistedServerPolicyBeforeLocalConfig(t *testing.T) {
	store := commandpolicy.NewStore(filepath.Join(t.TempDir(), "command-policy.json"))
	if err := store.Save(commandpolicy.State{Version: "server-v1", Revision: 7, Commands: map[string]string{"safe": "/bin/echo"}}); err != nil {
		t.Fatalf("store.Save() error = %v", err)
	}
	cfg := &config.Config{Runtime: config.RuntimeConfig{ExecCommands: map[string]string{"local": "/bin/true"}}}
	commands, version, revision := initialCommandPolicy(cfg, store)
	if version != "server-v1" {
		t.Fatalf("initialCommandPolicy() version = %q", version)
	}
	if revision != 7 {
		t.Fatalf("initialCommandPolicy() revision = %d", revision)
	}
	if _, ok := commands["local"]; ok {
		t.Fatalf("initialCommandPolicy() leaked local fallback when persisted server policy exists: %+v", commands)
	}
	if commands["safe"] != "/bin/echo" {
		t.Fatalf("initialCommandPolicy() commands = %+v", commands)
	}
}

func (f *fakeCommandHandler) ExecuteBatch(_ context.Context, _ []transport.CommandRequest) []transport.CommandResult {
	f.called = true
	return f.results
}

type fakeCommandClient struct {
	called  bool
	results []transport.CommandResult
}

type fakePayloadFetcher struct {
	delay       time.Duration
	inFlight    atomic.Int64
	maxInFlight atomic.Int64
}

type fakePollClient struct {
	response *transport.PollResponse
}

type fakeFRPController struct {
	status         frp.ConnectionStatus
	startCalls     int
	stopCalls      int
	startedConfig  config.FRPConfig
	startedCfgPath string
}

func (f *fakeCommandClient) SendCommandResults(_ context.Context, _ string, results []transport.CommandResult) error {
	f.called = true
	f.results = results
	return nil
}

func (f *fakePayloadFetcher) FetchCommandPayload(ctx context.Context, _ string, ref string) (*transport.CommandPayload, error) {
	current := f.inFlight.Add(1)
	defer f.inFlight.Add(-1)
	for {
		maxInFlight := f.maxInFlight.Load()
		if current <= maxInFlight || f.maxInFlight.CompareAndSwap(maxInFlight, current) {
			break
		}
	}

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(f.delay):
		return &transport.CommandPayload{Data: ref}, nil
	}
}

func (f *fakePollClient) Poll(_ context.Context, _ string, _ telemetry.Payload, _ frp.ConnectionStatus) (*transport.PollResponse, error) {
	return f.response, nil
}

func (f *fakePollClient) SendCommandResults(_ context.Context, _ string, _ []transport.CommandResult) error {
	return nil
}

func (f *fakePollClient) FetchCommandPayload(_ context.Context, _, _ string) (*transport.CommandPayload, error) {
	return nil, nil
}

func (f *fakeFRPController) Start(configPath string, frpConfig config.FRPConfig) error {
	f.startCalls++
	f.startedConfig = frpConfig
	f.startedCfgPath = configPath
	return nil
}

func (f *fakeFRPController) Stop() error {
	f.stopCalls++
	return nil
}

func (f *fakeFRPController) GetStatus() frp.ConnectionStatus {
	return f.status
}

func TestGivenCommands_WhenHandleCommandResponses_ThenResultsSent(t *testing.T) {
	handler := &fakeCommandHandler{
		results: []transport.CommandResult{
			{CommandID: "cmd-1", Status: transport.CommandStatusOK},
		},
	}
	client := &fakeCommandClient{}
	commands := []transport.CommandRequest{{CommandID: "cmd-1", Type: "list_scripts"}}

	if err := handleCommandResponses(context.Background(), client, nil, handler, "device-1", commands); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !handler.called {
		t.Fatalf("expected handler to be called")
	}
	if !client.called {
		t.Fatalf("expected client to be called")
	}
	if len(client.results) != 1 || client.results[0].CommandID != "cmd-1" {
		t.Fatalf("unexpected results: %+v", client.results)
	}
}

func TestRuntimeFRPConfigPreservesConfiguredValuesExceptAuthToken(t *testing.T) {
	base := config.FRPConfig{
		AuthToken:     "local-token",
		Name:          "configured-name",
		ServerAddr:    "frps.internal",
		ServerPort:    7001,
		WebServerAddr: "127.0.0.2",
		WebServerPort: 7401,
		HTTPLocalAddr: "127.0.0.1:8443",
		SSHLocalPort:  2222,
	}

	got := runtimeFRPConfig(base, "11111111-2222-3333-4444-555555555555")

	if got.Name != "configured-name" {
		t.Fatalf("runtimeFRPConfig() name = %q", got.Name)
	}
	if got.AuthToken != "" {
		t.Fatalf("runtimeFRPConfig() auth token = %q", got.AuthToken)
	}
	if got.ServerAddr != "frps.internal" {
		t.Fatalf("runtimeFRPConfig() server addr = %q", got.ServerAddr)
	}
	if got.ServerPort != 7001 || got.WebServerAddr != "127.0.0.2" || got.WebServerPort != 7401 || got.HTTPLocalAddr != "127.0.0.1:8443" || got.SSHLocalPort != 2222 {
		t.Fatalf("runtimeFRPConfig() did not preserve FRP settings: %+v", got)
	}
}

func TestPollResponseTokenOverridesRuntimeFRPAuthToken(t *testing.T) {
	frpConfig := runtimeFRPConfig(config.FRPConfig{AuthToken: ""}, "11111111-2222-3333-4444-555555555555")
	frpConfig.AuthToken = "heartbeat-token"

	if frpConfig.AuthToken != "heartbeat-token" {
		t.Fatalf("expected heartbeat token to become FRP auth token, got %q", frpConfig.AuthToken)
	}
}

func TestPollOnceStartsFRPWithRemoteAccessToken(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{RemoteAccessToken: "heartbeat-token"}}
	frpManager := &fakeFRPController{}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{AuthToken: "local-token", ServerAddr: "frps.example"}}
	runtimeCfg := script.RuntimeConfig{}

	state := &remoteAccessPollState{}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.startCalls != 1 {
		t.Fatalf("expected one start call, got %d", frpManager.startCalls)
	}
	if frpManager.stopCalls != 0 {
		t.Fatalf("expected no stop calls, got %d", frpManager.stopCalls)
	}
	if frpManager.startedConfig.AuthToken != "heartbeat-token" {
		t.Fatalf("started auth token = %q", frpManager.startedConfig.AuthToken)
	}
	if frpManager.startedConfig.AuthToken == "local-token" {
		t.Fatalf("local auth token leaked into started FRP config")
	}
	if state.tokenHash == "" {
		t.Fatalf("expected active token hash to be tracked")
	}
}

func TestPollOnceStopsFRPWhenRemoteAccessTokenAbsent(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}}

	runtimeCfg := script.RuntimeConfig{}

	state := &remoteAccessPollState{tokenHash: tokenHash("previous-token")}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.stopCalls != 1 {
		t.Fatalf("expected one stop call, got %d", frpManager.stopCalls)
	}
	if frpManager.startCalls != 0 {
		t.Fatalf("expected no start calls, got %d", frpManager.startCalls)
	}
	if state.tokenHash != "" {
		t.Fatalf("expected active token hash to be cleared")
	}
}

func TestPollOnceDoesNothingWhenTokenAbsentAndFRPInactive(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{}}
	frpManager := &fakeFRPController{}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}}

	runtimeCfg := script.RuntimeConfig{}

	state := &remoteAccessPollState{tokenHash: tokenHash("previous-token")}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.startCalls != 0 || frpManager.stopCalls != 0 {
		t.Fatalf("expected no FRP calls, got start=%d stop=%d", frpManager.startCalls, frpManager.stopCalls)
	}
	if state.tokenHash != "" {
		t.Fatalf("expected active token hash to be cleared")
	}
}

func TestPollOnceKeepsActiveFRPWhenTokenPresent(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{RemoteAccessToken: "heartbeat-token"}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{AuthToken: "local-token"}}

	runtimeCfg := script.RuntimeConfig{}

	state := &remoteAccessPollState{tokenHash: tokenHash("heartbeat-token")}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.startCalls != 0 || frpManager.stopCalls != 0 {
		t.Fatalf("expected no FRP calls, got start=%d stop=%d", frpManager.startCalls, frpManager.stopCalls)
	}
}

func TestPollOnceRestartsActiveFRPWhenTokenChanges(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{RemoteAccessToken: "new-token"}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{AuthToken: "local-token"}}

	runtimeCfg := script.RuntimeConfig{}
	state := &remoteAccessPollState{tokenHash: tokenHash("old-token")}

	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.stopCalls != 1 {
		t.Fatalf("expected one stop call, got %d", frpManager.stopCalls)
	}
	if frpManager.startCalls != 1 {
		t.Fatalf("expected one start call, got %d", frpManager.startCalls)
	}
	if frpManager.startedConfig.AuthToken != "new-token" {
		t.Fatalf("started auth token = %q", frpManager.startedConfig.AuthToken)
	}
	if state.tokenHash != tokenHash("new-token") {
		t.Fatalf("expected active token hash to be updated")
	}
}

func TestPollOnceRestartsActiveFRPWhenTokenStateUnknown(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{RemoteAccessToken: "heartbeat-token"}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{AuthToken: "local-token"}}

	runtimeCfg := script.RuntimeConfig{}
	state := &remoteAccessPollState{}

	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.stopCalls != 1 {
		t.Fatalf("expected one stop call, got %d", frpManager.stopCalls)
	}
	if frpManager.startCalls != 1 {
		t.Fatalf("expected one start call, got %d", frpManager.startCalls)
	}
	if frpManager.startedConfig.AuthToken != "heartbeat-token" {
		t.Fatalf("started auth token = %q", frpManager.startedConfig.AuthToken)
	}
	if state.tokenHash != tokenHash("heartbeat-token") {
		t.Fatalf("expected active token hash to be updated")
	}
}

func TestRuntimeFRPConfigFallsBackToGeneratedDeviceIDNameOnly(t *testing.T) {
	base := config.FRPConfig{}
	uuid := "11111111-2222-3333-4444-555555555555"

	got := runtimeFRPConfig(base, uuid)
	want := identity.GenerateDeviceName(uuid)

	if got.Name != want {
		t.Fatalf("runtimeFRPConfig() name = %q, want %q", got.Name, want)
	}
	if got.AuthToken != "" {
		t.Fatalf("runtimeFRPConfig() should not default auth token, got %q", got.AuthToken)
	}
	// ServerAddr is not defaulted here; Viper provides that default at config
	// load time. runtimeFRPConfig only derives Name from MAC.
	if got.ServerAddr != "" {
		t.Fatalf("runtimeFRPConfig() should not default server addr, got %q", got.ServerAddr)
	}
}

func TestHydrateCommandPayloadsUsesBoundedParallelism(t *testing.T) {
	fetcher := &fakePayloadFetcher{delay: 20 * time.Millisecond}
	cmds := make([]transport.CommandRequest, 12)
	for i := range cmds {
		cmds[i] = transport.CommandRequest{
			CommandID:  fmt.Sprintf("cmd-%d", i),
			PayloadRef: fmt.Sprintf("payload-%d", i),
		}
	}

	ready, failures := hydrateCommandPayloads(context.Background(), fetcher, "device-1", cmds)
	if len(failures) != 0 {
		t.Fatalf("expected no failures, got %+v", failures)
	}
	if len(ready) != len(cmds) {
		t.Fatalf("expected %d ready commands, got %d", len(cmds), len(ready))
	}
	if got := fetcher.maxInFlight.Load(); got < 2 || got > 8 {
		t.Fatalf("expected bounded parallel fetches between 2 and 8, got %d", got)
	}
}
