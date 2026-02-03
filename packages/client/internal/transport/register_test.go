package transport

import (
	"context"
	json "encoding/json/v2"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/identity"
)

func TestRegisterDevice(t *testing.T) {
	expectedUUID := "550e8400-e29b-41d4-a716-446655440000"
	testDevice := identity.DeviceIdentity{
		MACAddress: "00:11:22:33:44:55",
		IPAddress:  "192.168.1.10",
		Name:       "atom-001122334455",
	}

	tests := []struct {
		name      string
		handler   http.HandlerFunc
		device    identity.DeviceIdentity
		wantUUID  string
		expectErr bool
	}{
		{
			name: "Success",
			handler: func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					http.Error(w, "Expected POST", http.StatusBadRequest)
					return
				}
				if r.URL.Path != "/device/register" {
					http.Error(w, "Invalid path", http.StatusBadRequest)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				respBytes, _ := json.Marshal(map[string]string{
					"uuid": expectedUUID,
				})
				_, _ = w.Write(respBytes)
			},
			device:    testDevice,
			wantUUID:  expectedUUID,
			expectErr: false,
		},
		{
			name: "Server Error",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusInternalServerError)
			},
			device:    testDevice,
			wantUUID:  "",
			expectErr: true,
		},
		{
			name: "Invalid Response Body",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{invalid-json`))
			},
			device:    testDevice,
			wantUUID:  "",
			expectErr: true,
		},
		{
			name: "Empty UUID Response",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				respBytes, _ := json.Marshal(map[string]string{
					"uuid": "",
				})
				_, _ = w.Write(respBytes)
			},
			device:    testDevice,
			wantUUID:  "",
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

			uuid, err := client.RegisterDevice(context.Background(), tt.device)

			if (err != nil) != tt.expectErr {
				t.Errorf("RegisterDevice() error = %v, expectErr %v", err, tt.expectErr)
				return
			}
			if uuid != tt.wantUUID {
				t.Errorf("RegisterDevice() uuid = %v, want %v", uuid, tt.wantUUID)
			}
		})
	}
}
