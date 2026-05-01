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
		_, _ = w.Write([]byte(`{"data":{"remote_access_requested":false,"commands":[{"command_id":"c1","type":"list_scripts","args":[]}]}}`))
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
