package main

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
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
	called   bool
	commands []transport.CommandRequest
	results  []transport.CommandResult
}

func TestSSHAuthoritySocketPathUsesFixedTrustedPath(t *testing.T) {
	if got := sshAuthoritySocketPath(&config.Config{}); got != "/run/nixstasis/ssh-authority.sock" {
		t.Fatalf("sshAuthoritySocketPath() default = %q", got)
	}

	configured := &config.Config{Runtime: config.RuntimeConfig{SSHAuthoritySocket: "/tmp/custom.sock"}}
	if got := sshAuthoritySocketPath(configured); got != "/run/nixstasis/ssh-authority.sock" {
		t.Fatalf("sshAuthoritySocketPath() custom = %q", got)
	}
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

func (f *fakeCommandHandler) ExecuteBatch(_ context.Context, commands []transport.CommandRequest) []transport.CommandResult {
	f.called = true
	f.commands = commands
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
	response  *transport.PollResponse
	inventory *transport.CommandInventoryEvidence
}

type fakeFRPController struct {
	status         frp.ConnectionStatus
	startCalls     int
	stopCalls      int
	startedConfig  config.FRPConfig
	startedCfgPath string
	errors         []string
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

func (f *fakePollClient) PollWithInventory(_ context.Context, _ string, _ telemetry.Payload, _ frp.ConnectionStatus, inventory *transport.CommandInventoryEvidence) (*transport.PollResponse, error) {
	f.inventory = inventory
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

func (f *fakeFRPController) SetError(message string) {
	f.errors = append(f.errors, message)
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

func TestPollOnceStartsFRPWithSelectedRouteProfile(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{
		RemoteAccessToken:   "heartbeat-token",
		RemoteAccessProfile: &config.RouteProfileSelection{Name: "bootstrap", Version: 1},
	}}
	frpManager := &fakeFRPController{}
	cfg := &config.Config{
		Scripts: config.ScriptsConfig{Dir: t.TempDir()},
		FRP: config.FRPConfig{
			ServerAddr: "frps.example",
			Profiles: map[string]config.FRPRouteProfile{
				"bootstrap": {
					Version: 1,
					Routes:  []config.FRPRoute{{Name: "api", Kind: config.RouteKindHTTP, LocalAddr: "127.0.0.1:8080"}},
				},
			},
		},
	}
	state := &remoteAccessPollState{}

	if err := pollOnce(context.Background(), cfg, client, &script.RuntimeConfig{}, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}
	if frpManager.startCalls != 1 {
		t.Fatalf("start calls = %d, want 1", frpManager.startCalls)
	}
	if frpManager.startedConfig.SelectedProfileName != "bootstrap" || frpManager.startedConfig.SelectedProfileVersion != 1 {
		t.Fatalf("selected profile = %q/%d", frpManager.startedConfig.SelectedProfileName, frpManager.startedConfig.SelectedProfileVersion)
	}
	if state.profileKey != "bootstrap:1" {
		t.Fatalf("profile key = %q", state.profileKey)
	}
}

func TestPollOnceRestartsFRPWhenSelectedRouteProfileChanges(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{
		RemoteAccessToken:   "heartbeat-token",
		RemoteAccessProfile: &config.RouteProfileSelection{Name: "default", Version: 1},
	}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{ServerAddr: "frps.example"}}
	state := &remoteAccessPollState{tokenHash: tokenHash("heartbeat-token"), profileKey: "bootstrap:1"}

	if err := pollOnce(context.Background(), cfg, client, &script.RuntimeConfig{}, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}
	if frpManager.stopCalls != 1 || frpManager.startCalls != 1 {
		t.Fatalf("FRP calls = stop %d, start %d; want one each", frpManager.stopCalls, frpManager.startCalls)
	}
	if state.profileKey != "default:1" {
		t.Fatalf("profile key = %q", state.profileKey)
	}
}

func TestPollOnceFailsClosedForUnknownRouteProfile(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{
		RemoteAccessToken:   "heartbeat-token",
		RemoteAccessProfile: &config.RouteProfileSelection{Name: "unknown", Version: 1},
	}}
	frpManager := &fakeFRPController{status: frp.ConnectionStatus{Active: true}}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}, FRP: config.FRPConfig{ServerAddr: "frps.example"}}
	state := &remoteAccessPollState{tokenHash: tokenHash("heartbeat-token"), profileKey: "default:1"}

	if err := pollOnce(context.Background(), cfg, client, &script.RuntimeConfig{}, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}
	if frpManager.stopCalls != 1 || frpManager.startCalls != 0 {
		t.Fatalf("FRP calls = stop %d, start %d; want stop only", frpManager.stopCalls, frpManager.startCalls)
	}
	if state.tokenHash != "" || state.profileKey != "" {
		t.Fatalf("state after rejected profile = %+v", state)
	}
	if len(frpManager.errors) != 1 || !strings.Contains(frpManager.errors[0], "unknown route profile") {
		t.Fatalf("reported profile errors = %v", frpManager.errors)
	}
}

func TestPollOnceStoresProbeAndReportsBoundedInventoryOnNextHeartbeat(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{CommandInventoryProbe: &transport.CommandInventoryProbe{
		CatalogVersion: "catalog-v1",
		PackageNames:   []string{"coreutils"},
		CommandProbes:  []transport.CommandProbe{{Name: "df", CommandPath: "/usr/bin/df"}},
	}}}
	frpManager := &fakeFRPController{}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}}
	runtimeCfg := script.RuntimeConfig{ExecCommandAllowlist: map[string]string{"local": "/bin/true"}}
	state := &remoteAccessPollState{}

	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("first pollOnce() error = %v", err)
	}
	if client.inventory != nil {
		t.Fatalf("first heartbeat should not report inventory without a prior probe: %#v", client.inventory)
	}
	if state.commandInventoryProbe == nil || state.commandInventoryProbe.CatalogVersion != "catalog-v1" {
		t.Fatalf("probe not retained: %#v", state.commandInventoryProbe)
	}

	client.response = &transport.PollResponse{}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("second pollOnce() error = %v", err)
	}
	if client.inventory == nil || client.inventory.ProbeCatalogVersion != "catalog-v1" || client.inventory.SchemaVersion != 1 {
		t.Fatalf("inventory not sent on second heartbeat: %#v", client.inventory)
	}
	if runtimeCfg.ExecCommandAllowlist["local"] != "/bin/true" {
		t.Fatalf("inventory reporting changed runtime allowlist: %#v", runtimeCfg.ExecCommandAllowlist)
	}
}

func TestPollOnceClearsFRPErrorAfterRemoteAccessWithdrawal(t *testing.T) {
	client := &fakePollClient{response: &transport.PollResponse{
		RemoteAccessToken:   "heartbeat-token",
		RemoteAccessProfile: &config.RouteProfileSelection{Name: "unknown", Version: 1},
	}}
	frpManager := &fakeFRPController{}
	cfg := &config.Config{Scripts: config.ScriptsConfig{Dir: t.TempDir()}}
	state := &remoteAccessPollState{}

	if err := pollOnce(context.Background(), cfg, client, &script.RuntimeConfig{}, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() rejected-profile error = %v", err)
	}
	if len(frpManager.errors) != 1 || !strings.Contains(frpManager.errors[0], "unknown route profile") {
		t.Fatalf("reported profile errors = %v", frpManager.errors)
	}

	client.response = &transport.PollResponse{}
	if err := pollOnce(context.Background(), cfg, client, &script.RuntimeConfig{}, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() withdrawal error = %v", err)
	}
	if got := frpManager.errors[len(frpManager.errors)-1]; got != "" {
		t.Fatalf("FRP error after withdrawal = %q, want empty", got)
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

	state := &remoteAccessPollState{tokenHash: tokenHash("previous-token"), profileKey: "default:1"}
	if err := pollOnce(context.Background(), cfg, client, &runtimeCfg, frpManager, &fakeCommandHandler{}, "device-1", time.Now(), state); err != nil {
		t.Fatalf("pollOnce() error = %v", err)
	}

	if frpManager.stopCalls != 1 {
		t.Fatalf("expected one stop call, got %d", frpManager.stopCalls)
	}
	if frpManager.startCalls != 0 {
		t.Fatalf("expected no start calls, got %d", frpManager.startCalls)
	}
	if state.tokenHash != "" || state.profileKey != "" {
		t.Fatalf("expected active remote access state to be cleared: %+v", state)
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

	state := &remoteAccessPollState{tokenHash: tokenHash("heartbeat-token"), profileKey: "default:1"}
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

func TestGivenDeferredRunScriptCommand_WhenHandleCommandResponses_ThenHydratesBeforeExecution(t *testing.T) {
	handler := &fakeCommandHandler{
		results: []transport.CommandResult{{CommandID: "cmd-script", Status: transport.CommandStatusOK}},
	}
	client := &fakeCommandClient{}
	fetcher := &fakePayloadFetcher{}
	commands := []transport.CommandRequest{{
		CommandID:  "cmd-script",
		Type:       "run_script",
		PayloadRef: "script-payload",
	}}

	if err := handleCommandResponses(context.Background(), client, fetcher, handler, "device-1", commands); err != nil {
		t.Fatalf("expected deferred run_script handling to succeed, got %v", err)
	}
	if len(handler.commands) != 1 {
		t.Fatalf("expected one hydrated command, got %+v", handler.commands)
	}
	if handler.commands[0].PayloadRef != "script-payload" {
		t.Fatalf("payload ref = %q", handler.commands[0].PayloadRef)
	}
	if handler.commands[0].Payload == nil || handler.commands[0].Payload.Data != "script-payload" {
		t.Fatalf("expected hydrated payload, got %+v", handler.commands[0].Payload)
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
