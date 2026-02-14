package transport

import (
	"context"
	"encoding/json/v2"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/identity"
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
