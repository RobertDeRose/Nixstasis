package main

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
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

func (f *fakeCommandClient) SendCommandResults(_ context.Context, _ string, results []transport.CommandResult) error {
	f.called = true
	f.results = results
	return nil
}

func (f *fakePayloadFetcher) FetchCommandPayload(ctx context.Context, _ string, ref string) (*transport.CommandPayload, error) {
	current := f.inFlight.Add(1)
	defer f.inFlight.Add(-1)
	for {
		max := f.maxInFlight.Load()
		if current <= max || f.maxInFlight.CompareAndSwap(max, current) {
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

func TestRuntimeFRPConfigPreservesConfiguredValues(t *testing.T) {
	base := config.FRPConfig{
		AuthToken:     "secret-token",
		Name:          "configured-name",
		ServerAddr:    "frps.internal",
		ServerPort:    7001,
		WebServerAddr: "127.0.0.2",
		WebServerPort: 7401,
		HTTPLocalAddr: "127.0.0.1:8443",
		SSHLocalPort:  2222,
	}

	got := runtimeFRPConfig(base, "aa:bb:cc:dd:ee:ff", "identity-token")

	if got.Name != "configured-name" {
		t.Fatalf("runtimeFRPConfig() name = %q", got.Name)
	}
	if got.AuthToken != "secret-token" {
		t.Fatalf("runtimeFRPConfig() auth token = %q", got.AuthToken)
	}
	if got.ServerAddr != "frps.internal" {
		t.Fatalf("runtimeFRPConfig() server addr = %q", got.ServerAddr)
	}
	if got.ServerPort != 7001 || got.WebServerAddr != "127.0.0.2" || got.WebServerPort != 7401 || got.HTTPLocalAddr != "127.0.0.1:8443" || got.SSHLocalPort != 2222 {
		t.Fatalf("runtimeFRPConfig() did not preserve FRP settings: %+v", got)
	}
}

func TestRuntimeFRPConfigFallsBackToGeneratedDeviceNameAndIdentityToken(t *testing.T) {
	base := config.FRPConfig{}
	mac := "aa:bb:cc:dd:ee:ff"

	got := runtimeFRPConfig(base, mac, "identity-token")
	want := identity.GenerateDeviceName(mac)

	if got.Name != want {
		t.Fatalf("runtimeFRPConfig() name = %q, want %q", got.Name, want)
	}
	if got.AuthToken != "identity-token" {
		t.Fatalf("runtimeFRPConfig() auth token = %q", got.AuthToken)
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
