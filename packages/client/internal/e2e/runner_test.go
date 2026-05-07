package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestRunSuiteUsesConfiguredJourneys(t *testing.T) {
	var gotCreate runCreateRequest
	var gotResults resultsRequest
	var gotRunID string
	var gotProtocolHeader string

	server := newE2EServer(t, func(req runCreateRequest, protocolHeader string) {
		gotCreate = req
		gotProtocolHeader = protocolHeader
	}, func(runID string, req resultsRequest) {
		gotRunID = runID
		gotResults = req
	})
	t.Cleanup(server.Close)

	cfg := Config{
		APIURL:          server.URL,
		Suite:           "full",
		Environment:     "local",
		Trigger:         "manual",
		ProtocolVersion: "1",
		IdempotencyKey:  "run-1",
		Journeys:        []string{"auth", "dashboard"},
	}

	runner := NewRunner(cfg)
	summary, err := runner.RunSuite(context.Background(), nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(summary.Journeys) != 2 {
		t.Fatalf("expected 2 journeys, got %d", len(summary.Journeys))
	}
	if summary.RunID == "" {
		t.Fatalf("expected run id to be populated")
	}
	if gotCreate.SuiteID != "full" {
		t.Fatalf("expected suite full, got %s", gotCreate.SuiteID)
	}
	if len(gotCreate.JourneyIDs) != 2 {
		t.Fatalf("expected 2 journeys in create request, got %d", len(gotCreate.JourneyIDs))
	}
	if gotCreate.IdempotencyKey != "run-1" {
		t.Fatalf("expected idempotency key run-1, got %s", gotCreate.IdempotencyKey)
	}
	if gotProtocolHeader != "1" {
		t.Fatalf("expected protocol header 1, got %s", gotProtocolHeader)
	}
	if gotRunID == "" {
		t.Fatalf("expected run id in results request")
	}
	if len(gotResults.Results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(gotResults.Results))
	}
	if summary.Status != "passed" {
		t.Fatalf("expected summary status passed, got %s", summary.Status)
	}
}

func TestRunSuiteOverridesJourneys(t *testing.T) {
	var gotCreate runCreateRequest
	var gotResults resultsRequest

	server := newE2EServer(t, func(req runCreateRequest, _ string) {
		gotCreate = req
	}, func(_ string, req resultsRequest) {
		gotResults = req
	})
	t.Cleanup(server.Close)

	cfg := Config{
		APIURL:          server.URL,
		Suite:           "full",
		Environment:     "local",
		Trigger:         "manual",
		ProtocolVersion: "1",
		Journeys:        []string{"auth"},
	}

	runner := NewRunner(cfg)
	summary, err := runner.RunSuite(context.Background(), []string{journeyLogout})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(summary.Journeys) != 1 {
		t.Fatalf("expected 1 journey, got %d", len(summary.Journeys))
	}
	if summary.Journeys[0].JourneyID != journeyLogout {
		t.Fatalf("expected journey logout, got %s", summary.Journeys[0].JourneyID)
	}
	if len(gotCreate.JourneyIDs) != 1 || gotCreate.JourneyIDs[0] != journeyLogout {
		t.Fatalf("expected create request to use override journey")
	}
	if len(gotResults.Results) != 1 || gotResults.Results[0].JourneyID != journeyLogout {
		t.Fatalf("expected results request to use override journey")
	}
}

func TestRunSuiteWritesV1JourneyLogs(t *testing.T) {
	var gotResults resultsRequest

	server := newE2EServer(t, nil, func(_ string, req resultsRequest) {
		gotResults = req
	})
	t.Cleanup(server.Close)

	logDir := t.TempDir()
	cfg := Config{
		APIURL:          server.URL,
		Suite:           "full",
		Environment:     "local",
		Trigger:         "manual",
		ProtocolVersion: "1",
		Journeys:        []string{"auth"},
		LogDir:          logDir,
	}

	runner := NewRunner(cfg)
	_, err := runner.RunSuite(context.Background(), nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if len(gotResults.Results) != 1 {
		t.Fatalf("expected exactly one journey result, got %d", len(gotResults.Results))
	}

	logRef := gotResults.Results[0].LogRef
	if logRef == "" {
		t.Fatalf("expected log_ref in result payload")
	}

	content, err := os.ReadFile(logRef)
	if err != nil {
		t.Fatalf("expected log to be readable: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(content)), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 JSONL records (start/step/complete), got %d", len(lines))
	}

	start := decodeLogLine(t, lines[0])
	step := decodeLogLine(t, lines[1])
	complete := decodeLogLine(t, lines[2])

	if start["schema"] != "e2e_log.v1" {
		t.Fatalf("expected schema e2e_log.v1, got %v", start["schema"])
	}
	if start["level"] != "journey" || start["event"] != "started" {
		t.Fatalf("expected first record to be journey start, got level=%v event=%v", start["level"], start["event"])
	}
	if _, ok := start["run"]; !ok {
		t.Fatalf("expected journey start record to include run context")
	}

	if step["level"] != "step" || step["status"] != "passed" {
		t.Fatalf("expected second record to be passed step, got level=%v status=%v", step["level"], step["status"])
	}
	if _, hasStepID := step["step_id"]; hasStepID {
		t.Fatalf("expected step_id to be omitted when equal to action, got %v", step["step_id"])
	}
	if step["action"] != "register_device" {
		t.Fatalf("expected action register_device, got %v", step["action"])
	}
	if _, hasLegacy := step["test_phase"]; hasLegacy {
		t.Fatalf("expected v1 step record to omit legacy test_phase field")
	}

	if complete["level"] != "journey" || complete["event"] != "completed" || complete["status"] != "passed" {
		t.Fatalf("expected third record to be journey completion, got level=%v event=%v status=%v", complete["level"], complete["event"], complete["status"])
	}
	if complete["steps_run"] != float64(1) || complete["steps_passed"] != float64(1) {
		t.Fatalf("expected completion summary steps run/passed (1/1), got run=%v passed=%v", complete["steps_run"], complete["steps_passed"])
	}

	if failed, ok := complete["steps_failed"]; ok && failed != float64(0) {
		t.Fatalf("expected steps_failed to be 0 when present, got %v", failed)
	}
}

func TestRuntimePayloadRefUsesDeviceAPIKey(t *testing.T) {
	var approvedDeviceID string
	const issuedToken = "runtime-token-123"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/e2e/runs":
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(`{"data":{"id":"run-123","suite_id":"runtime","journey_ids":["runtime_transport_negative"],"environment_label":"local","trigger_source":"manual","protocol_version":"1","status":"queued"}}`))
		case r.Method == http.MethodPost && r.URL.Path == "/e2e/runs/run-123/results":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{}`))
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/devices/register":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode register payload: %v", err)
			}
			mac, _ := payload["mac_address"].(string)
			productName, _ := payload["product_name"].(string)
			approved := approvedDeviceID != ""
			response := fmt.Sprintf(`{"data":{"id":"device-1","mac_address":"%s","product_name":"%s","approval_status":"%s"`, mac, productName, map[bool]string{true: "approved", false: "pending"}[approved])
			if approved {
				response += fmt.Sprintf(`,"api_token":"%s"`, issuedToken)
			}
			response += `}}`
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(response))
		case r.Method == http.MethodPatch && r.URL.Path == "/api/json/devices/device-1":
			approvedDeviceID = "device-1"
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"data":{"id":"device-1"}}`))
		case r.Method == http.MethodPost && r.URL.Path == "/api/json/pending_commands":
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte(`{"data":{"id":"cmd-1"}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/api/v1/devices/device-1/command_payloads/runtime-install-script":
			if got := r.URL.Query().Get("api_key"); got != issuedToken {
				t.Fatalf("expected payload fetch api_key %q, got %q", issuedToken, got)
			}
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"content_type":"text/plain","name":"alpha","data":"hello"}`))
		default:
			t.Fatalf("unexpected request %s %s?%s", r.Method, r.URL.Path, r.URL.RawQuery)
		}
	}))
	t.Cleanup(server.Close)

	executor := newJourneyExecutor(Config{APIURL: server.URL}, newJourneyLog("runtime_transport_negative", runLogContext{}))
	state := &journeyState{DeviceID: "device-1", DeviceMac: "00:11:22:33:44:55", ProductName: "runtime-product"}

	if _, err := executor.runtimeApproveDevice(context.Background(), state, "device_approved"); err != nil {
		t.Fatalf("runtimeApproveDevice() error = %v", err)
	}
	if state.DeviceToken != issuedToken {
		t.Fatalf("expected device token %q, got %q", issuedToken, state.DeviceToken)
	}

	state.CommandRef = "runtime-install-script"
	if _, err := executor.runtimeQueuePayloadRefCommand(context.Background(), state, "command_payload_available"); err != nil {
		t.Fatalf("runtimeQueuePayloadRefCommand() error = %v", err)
	}
}

func decodeLogLine(t *testing.T, line string) map[string]any {
	t.Helper()

	var decoded map[string]any
	if err := json.Unmarshal([]byte(line), &decoded); err != nil {
		t.Fatalf("expected valid JSONL line, got error %v for line %q", err, line)
	}
	return decoded
}

func newE2EServer(t *testing.T, onCreate func(runCreateRequest, string), onResults func(string, resultsRequest)) *httptest.Server {
	t.Helper()

	var deviceCounter int
	var reportCounter int

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/e2e/runs":
			var payload runCreateRequest
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("failed to decode create request: %v", err)
			}
			protocolHeader := r.Header.Get("X-E2E-Protocol-Version")
			if onCreate != nil {
				onCreate(payload, protocolHeader)
			}

			response := runResponse{
				Data: runData{
					ID:               "run-123",
					SuiteID:          payload.SuiteID,
					JourneyIDs:       payload.JourneyIDs,
					EnvironmentLabel: payload.EnvironmentLabel,
					TriggerSource:    payload.TriggerSource,
					ProtocolVersion:  protocolHeader,
					Status:           "queued",
				},
			}

			w.WriteHeader(http.StatusCreated)
			if err := json.NewEncoder(w).Encode(response); err != nil {
				t.Fatalf("failed to encode create response: %v", err)
			}
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/devices/register":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("failed to decode device register payload: %v", err)
			}
			deviceCounter++
			mac, _ := payload["mac_address"].(string)
			response := deviceResponse{}
			response.Data.ID = fmt.Sprintf("device-%d", deviceCounter)
			response.Data.MacAddress = mac

			w.WriteHeader(http.StatusCreated)
			if err := json.NewEncoder(w).Encode(response); err != nil {
				t.Fatalf("failed to encode device response: %v", err)
			}
		case r.Method == http.MethodGet && r.URL.Path == "/":
			w.WriteHeader(http.StatusOK)
			if _, err := w.Write([]byte("Dashboard")); err != nil {
				t.Fatalf("failed to write dashboard response: %v", err)
			}
		case r.Method == http.MethodPost && r.URL.Path == "/api/json/custom_reports":
			reportCounter++
			response := jsonAPIResponse{}
			response.Data.ID = fmt.Sprintf("%d", reportCounter)

			w.WriteHeader(http.StatusCreated)
			if err := json.NewEncoder(w).Encode(response); err != nil {
				t.Fatalf("failed to encode report response: %v", err)
			}
		case r.Method == http.MethodPatch && strings.HasPrefix(r.URL.Path, "/api/json/custom_reports/"):
			response := jsonAPIResponse{}
			response.Data.ID = strings.TrimPrefix(r.URL.Path, "/api/json/custom_reports/")
			w.WriteHeader(http.StatusOK)
			if err := json.NewEncoder(w).Encode(response); err != nil {
				t.Fatalf("failed to encode report update response: %v", err)
			}
		case r.Method == http.MethodDelete && strings.HasPrefix(r.URL.Path, "/api/json/devices/"):
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/e2e/runs/") && strings.HasSuffix(r.URL.Path, "/results"):
			runID := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/e2e/runs/"), "/results")
			var payload resultsRequest
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("failed to decode results request: %v", err)
			}
			if onResults != nil {
				onResults(runID, payload)
			}
			w.WriteHeader(http.StatusOK)
			if _, err := w.Write([]byte(`{}`)); err != nil {
				t.Fatalf("failed to write results response: %v", err)
			}
		default:
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.Path)
		}
	})

	return httptest.NewServer(handler)
}
