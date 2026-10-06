package main

import (
	"context"
	"encoding/json/v2"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

func TestPrepareRegistrationPrefersRecoveryCredentials(t *testing.T) {
	const uuid = "550e8400-e29b-41d4-a716-446655440000"
	dir := t.TempDir()
	runtimeStore := identity.NewStore(filepath.Join(dir, "id"))
	recoveryStore := identity.NewStore(filepath.Join(dir, "registration"))
	if err := runtimeStore.Save(identity.Credentials{UUID: uuid, Token: "stale-token"}); err != nil {
		t.Fatal(err)
	}
	// The previous format is used after a runtime identity save failure.
	if err := recoveryStore.Save(identity.Credentials{UUID: uuid, Token: "current-token"}); err != nil {
		t.Fatal(err)
	}
	enrollment, err := prepareRegistration(runtimeStore, recoveryStore)
	if err != nil {
		t.Fatal(err)
	}
	if enrollment.Token != "current-token" {
		t.Fatalf("selected proof %q, want recovery token", enrollment.Token)
	}
	if enrollment.ReplacementToken == "" {
		t.Fatal("replacement token not prepared")
	}
}

func TestPrepareRegistrationPersistsCredentialsBeforeFirstRequest(t *testing.T) {
	dir := t.TempDir()
	runtimeStore := identity.NewStore(filepath.Join(dir, "id"))
	recoveryStore := identity.NewStore(filepath.Join(dir, "registration"))
	first, err := prepareRegistration(runtimeStore, recoveryStore)
	if err != nil {
		t.Fatal(err)
	}
	if first.UUID != "" || len(first.Token) != 43 || len(first.ReplacementToken) != 43 || first.Token == first.ReplacementToken {
		t.Fatal("initial credentials were not prepared correctly")
	}
	// A restart before receiving any response must use exactly the same secrets.
	retry, err := prepareRegistration(runtimeStore, identity.NewStore(filepath.Join(dir, "registration")))
	if err != nil {
		t.Fatal(err)
	}
	if retry != first {
		t.Fatal("credentials changed after restart")
	}
}

func TestRegistrationRetryAfterLostExchangeResponse(t *testing.T) {
	const uuid = "550e8400-e29b-41d4-a716-446655440000"
	dir := t.TempDir()
	runtimeStore := identity.NewStore(filepath.Join(dir, "id"))
	recoveryStore := identity.NewStore(filepath.Join(dir, "registration"))
	first, err := prepareRegistration(runtimeStore, recoveryStore)
	if err != nil {
		t.Fatal(err)
	}
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		var payload map[string]any
		if err := json.UnmarshalRead(r.Body, &payload); err != nil {
			t.Error(err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if payload["registration_token"] != first.Token || payload["replacement_token"] != first.ReplacementToken {
			t.Error("retry changed the durably prepared credentials")
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusCreated)
		if requests == 1 {
			// The exchange committed, but no decodable body reached the client.
			return
		}
		data, _ := json.Marshal(map[string]any{"data": map[string]string{"id": uuid, "api_token": first.ReplacementToken}})
		_, _ = w.Write(data)
	}))
	defer server.Close()
	client := transport.NewClient(config.APIConfig{URL: server.URL})
	device := identity.DeviceIdentity{MACAddress: "02:00:00:10:00:01", Name: "retry-device"}
	if _, err := client.RegisterDeviceCredentials(context.Background(), device, first.Token, first.ReplacementToken); err == nil {
		t.Fatal("expected a lost-response error")
	}
	retry, err := prepareRegistration(runtimeStore, recoveryStore)
	if err != nil {
		t.Fatal(err)
	}
	credentials, err := client.RegisterDeviceCredentials(context.Background(), device, retry.Token, retry.ReplacementToken)
	if err != nil {
		t.Fatal(err)
	}
	if credentials.UUID != uuid || credentials.Token != first.ReplacementToken {
		t.Fatal("retry did not recover committed runtime credentials")
	}
}

func TestPrepareRegistrationDoesNotOverwriteUnreadableRecoveryState(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "registration")
	if err := os.WriteFile(path, []byte("interrupted-json"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := prepareRegistration(identity.NewStore(filepath.Join(dir, "id")), identity.NewStore(path))
	if err == nil {
		t.Fatal("expected invalid recovery state to stop registration")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "interrupted-json" {
		t.Fatal("invalid recovery state was replaced with an unusable new proof")
	}
}

func TestPrepareRegistrationRejectsInvalidStatePath(t *testing.T) {
	dir := t.TempDir()
	parent := filepath.Join(dir, "not-a-directory")
	if err := os.WriteFile(parent, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := prepareRegistration(identity.NewStore(filepath.Join(dir, "id")), identity.NewStore(filepath.Join(parent, "registration")))
	if err == nil {
		t.Fatal("expected invalid registration state path to stop registration")
	}
}
