package transport

import (
	"context"
	"encoding/json/v2"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
)

func TestPollUsesHeartbeatContract(t *testing.T) {
	t.Parallel()

	deviceID := "d-123"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/api/v1/devices/"+deviceID+"/heartbeat" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}

		var req PollRequest
		if err := json.UnmarshalRead(r.Body, &req); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if req.Telemetry.Device.Identity.UUID != deviceID {
			t.Fatalf("unexpected uuid: %s", req.Telemetry.Device.Identity.UUID)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":{"remote_access_token":"shared-secret","commands":[{"command_id":"c1","type":"list_scripts","args":[]}]}}`))
	}))
	defer server.Close()

	client := NewClient(config.APIConfig{URL: server.URL})

	resp, err := client.Poll(
		context.Background(),
		deviceID,
		telemetry.Payload{
			Device: telemetry.DeviceStatus{
				Identity: identity.DeviceIdentity{UUID: deviceID},
				Uptime:   100,
			},
			Scripts: map[string]telemetry.Report{},
			Meta: telemetry.PollMeta{
				Timestamp: time.Now(),
				Duration:  "10ms",
			},
		},
		frp.ConnectionStatus{},
	)
	if err != nil {
		t.Fatalf("poll failed: %v", err)
	}
	if resp == nil || len(resp.Commands) != 1 || resp.Commands[0].CommandID != "c1" {
		t.Fatalf("unexpected poll response: %#v", resp)
	}
	if resp.RemoteAccessToken != "shared-secret" {
		t.Fatalf("remote access token = %q", resp.RemoteAccessToken)
	}
}

func TestPollWithInventorySendsEvidenceAndParsesProbe(t *testing.T) {
	t.Parallel()

	deviceID := "d-inventory"
	observedAt := time.Date(2026, 7, 29, 12, 0, 0, 0, time.UTC)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req PollRequest
		if err := json.UnmarshalRead(r.Body, &req); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if req.CommandInventory == nil {
			t.Fatalf("expected command_inventory in heartbeat request")
		}
		if req.CommandInventory.SchemaVersion != 1 || req.CommandInventory.ProbeCatalogVersion != "catalog-v1" {
			t.Fatalf("unexpected inventory metadata: %#v", req.CommandInventory)
		}
		if !req.CommandInventory.ObservedAt.Equal(observedAt) {
			t.Fatalf("observed_at = %s", req.CommandInventory.ObservedAt)
		}
		if !req.CommandInventory.Packages["coreutils"].Installed {
			t.Fatalf("expected coreutils package evidence: %#v", req.CommandInventory.Packages)
		}
		if req.CommandInventory.Commands["df"].Path != "/usr/bin/df" {
			t.Fatalf("expected df command evidence: %#v", req.CommandInventory.Commands)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"data":{"command_inventory_probe":{"catalog_version":"catalog-v2","package_names":["util-linux"],"command_probes":[{"name":"lsblk","command_path":"/usr/bin/lsblk"}]}}}`))
	}))
	defer server.Close()

	client := NewClient(config.APIConfig{URL: server.URL})
	resp, err := client.PollWithInventory(context.Background(), deviceID, telemetry.Payload{}, frp.ConnectionStatus{}, &CommandInventoryEvidence{
		SchemaVersion:       1,
		ProbeCatalogVersion: "catalog-v1",
		ObservedAt:          observedAt,
		Architecture:        "x86_64",
		PackageManager:      "apt",
		OSRelease:           map[string]string{"ID": "debian"},
		Packages:            map[string]PackageEvidence{"coreutils": {Installed: true}},
		Commands:            map[string]CommandEvidence{"df": {Path: "/usr/bin/df"}},
	})
	if err != nil {
		t.Fatalf("PollWithInventory failed: %v", err)
	}
	if resp.CommandInventoryProbe == nil || resp.CommandInventoryProbe.CatalogVersion != "catalog-v2" {
		t.Fatalf("unexpected inventory probe: %#v", resp.CommandInventoryProbe)
	}
	if len(resp.CommandInventoryProbe.CommandProbes) != 1 || resp.CommandInventoryProbe.CommandProbes[0].Name != "lsblk" {
		t.Fatalf("unexpected command probes: %#v", resp.CommandInventoryProbe.CommandProbes)
	}
}

func TestCommandEndpointsUseRuntimeV1Routes(t *testing.T) {
	t.Parallel()

	deviceID := "d-123"
	payloadRef := "p-1"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/devices/"+deviceID+"/command_results":
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"data":{"acknowledged_count":1}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/api/v1/devices/"+deviceID+"/command_payloads/"+payloadRef:
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"content_type":"text/plain","name":"script","data":"echo hi"}`))
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()

	client := NewClient(config.APIConfig{URL: server.URL})

	if err := client.SendCommandResults(context.Background(), deviceID, []CommandResult{{CommandID: "c1", Status: CommandStatusOK}}); err != nil {
		t.Fatalf("SendCommandResults failed: %v", err)
	}

	payload, err := client.FetchCommandPayload(context.Background(), deviceID, payloadRef)
	if err != nil {
		t.Fatalf("FetchCommandPayload failed: %v", err)
	}
	if payload == nil || payload.Data != "echo hi" {
		t.Fatalf("unexpected payload: %#v", payload)
	}
}
