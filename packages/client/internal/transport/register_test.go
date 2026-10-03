package transport

import (
	"context"
	"encoding/json/v2"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
)

func TestRegisterDevice(t *testing.T) {
	expectedDeviceID := "550e8400-e29b-41d4-a716-446655440000"
	testDevice := identity.DeviceIdentity{
		MACAddress: "00:11:22:33:44:55",
		IPAddress:  "192.168.1.10",
		Name:       "atom-001122334455",
	}

	tests := []struct {
		name      string
		handler   http.HandlerFunc
		device    identity.DeviceIdentity
		wantID    string
		expectErr bool
	}{
		{
			name: "Success",
			handler: func(w http.ResponseWriter, r *http.Request) {
				var payload map[string]any
				if err := json.UnmarshalRead(r.Body, &payload); err != nil {
					t.Fatalf("failed to decode register payload: %v", err)
				}
				schemaDefinition, ok := payload["schema_definition"].(map[string]any)
				if !ok {
					t.Fatalf("expected schema_definition map, got %T", payload["schema_definition"])
				}
				if got, _ := schemaDefinition["product"].(string); got != testDevice.Name {
					t.Fatalf("expected schema product %q, got %q", testDevice.Name, got)
				}

				if r.Method != http.MethodPost {
					http.Error(w, "Expected POST", http.StatusBadRequest)
					return
				}
				if r.URL.Path != "/api/v1/devices/register" {
					http.Error(w, "Invalid path", http.StatusBadRequest)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				respBytes, _ := json.Marshal(map[string]any{
					"data": map[string]string{
						"id": expectedDeviceID,
					},
				})
				_, _ = w.Write(respBytes)
			},
			device:    testDevice,
			wantID:    expectedDeviceID,
			expectErr: false,
		},
		{
			name: "Server Error",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusInternalServerError)
			},
			device:    testDevice,
			wantID:    "",
			expectErr: true,
		},
		{
			name: "Invalid Response Body",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusCreated)
				_, _ = w.Write([]byte(`{invalid-json`))
			},
			device:    testDevice,
			wantID:    "",
			expectErr: true,
		},
		{
			name: "Empty ID Response",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusCreated)
				respBytes, _ := json.Marshal(map[string]any{
					"data": map[string]string{
						"id": "",
					},
				})
				_, _ = w.Write(respBytes)
			},
			device:    testDevice,
			wantID:    "",
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(tt.handler)
			defer server.Close()

			cfg := config.APIConfig{
				URL: server.URL,
			}
			client := NewClient(cfg)

			deviceID, err := client.RegisterDevice(context.Background(), tt.device)

			if (err != nil) != tt.expectErr {
				t.Errorf("RegisterDevice() error = %v, expectErr %v", err, tt.expectErr)
				return
			}
			if deviceID != tt.wantID {
				t.Errorf("RegisterDevice() id = %v, want %v", deviceID, tt.wantID)
			}
		})
	}
}

func TestRegisterDeviceCredentialsUsesEnrollmentProof(t *testing.T) {
	const (
		deviceID          = "550e8400-e29b-41d4-a716-446655440000"
		registrationToken = "registration-proof"
		runtimeToken      = "runtime-token"
	)

	requestCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		var payload map[string]any
		if err := json.UnmarshalRead(r.Body, &payload); err != nil {
			t.Fatalf("decode registration payload: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		if requestCount == 1 {
			if _, ok := payload["registration_token"]; ok {
				t.Fatal("initial registration unexpectedly sent a registration token")
			}
			respBytes, _ := json.Marshal(map[string]any{
				"data": map[string]string{
					"id":                 deviceID,
					"registration_token": registrationToken,
				},
			})
			_, _ = w.Write(respBytes)
			return
		}

		if got, _ := payload["registration_token"].(string); got != registrationToken {
			t.Fatalf("registration_token = %q, want %q", got, registrationToken)
		}
		respBytes, _ := json.Marshal(map[string]any{
			"data": map[string]string{
				"id":        deviceID,
				"api_token": runtimeToken,
			},
		})
		_, _ = w.Write(respBytes)
	}))
	defer server.Close()

	client := NewClient(config.APIConfig{URL: server.URL})
	device := identity.DeviceIdentity{MACAddress: "00:11:22:33:44:55", Name: "atom-001122334455"}

	pending, err := client.RegisterDeviceCredentials(context.Background(), device)
	if !errors.Is(err, ErrDevicePendingApproval) {
		t.Fatalf("first registration error = %v, want ErrDevicePendingApproval", err)
	}
	if pending.UUID != deviceID || pending.RegistrationToken != registrationToken {
		t.Fatalf("pending credentials = %+v", pending)
	}

	credentials, err := client.RegisterDeviceCredentials(context.Background(), device, pending.RegistrationToken)
	if err != nil {
		t.Fatalf("approved registration error = %v", err)
	}
	if credentials.UUID != deviceID || credentials.Token != runtimeToken {
		t.Fatalf("runtime credentials = %+v", credentials)
	}
}
