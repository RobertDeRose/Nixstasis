package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/commands"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

func (e *journeyExecutor) runtimeRegisterDevice(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "runtime_device_registered" {
		return stepOutcome{}, expectationInvalidFailure("runtime_device_registered", expect)
	}

	mac := generateMac()
	account := generateAccountNumber()
	productName := fmt.Sprintf("runtime-linux-e2e-%d", time.Now().UnixNano())

	apiClient := transport.NewClient(config.APIConfig{URL: e.cfg.APIURL})
	deviceID, err := apiClient.RegisterDevice(ctx, identity.DeviceIdentity{
		MACAddress: mac,
		Name:       productName,
	})
	if err != nil {
		return stepOutcome{}, err
	}

	if deviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime register response includes a device id",
			map[string]any{"data.id_non_empty": true},
			map[string]any{"data.id": deviceID},
			"runtime register returned empty device id",
		)
	}

	updatePayload := map[string]any{
		"data": map[string]any{
			"type": "device",
			"id":   deviceID,
			"attributes": map[string]any{
				"product_name":   productName,
				"account_number": account,
				"metadata": map[string]any{
					"source": "runtime-e2e",
				},
			},
		},
	}

	updateBody, err := json.Marshal(updatePayload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "device update payload could be encoded",
			Message:         fmt.Sprintf("marshal runtime device update payload: %v", err),
		}
	}
	if _, _, err := e.doRequest(
		ctx,
		"PATCH",
		fmt.Sprintf("/api/json/devices/%s", deviceID),
		updateBody,
		jsonAPIHeaders(),
		200,
	); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "runtime device details were updated after register",
			Message:         fmt.Sprintf("runtime register post-update failed: %v", err),
		}
	}

	state.DeviceID = deviceID
	state.DeviceMac = mac
	state.ProductName = productName

	return stepOutcome{
		ResponseType: responseTypeJSON,
		ActionData: map[string]any{
			"device_id":    deviceID,
			"transport":    "register_device",
			"post_updated": true,
			"account":      account,
			"product_name": productName,
		},
	}, nil
}

func (e *journeyExecutor) runtimeCheckDomain(ctx context.Context, _ *journeyState, expect string) (stepOutcome, error) {
	if expect != "tls_domain_allowed" {
		return stepOutcome{}, expectationInvalidFailure("tls_domain_allowed", expect)
	}

	checkDomain := fmt.Sprintf("auth.%s", strings.TrimPrefix(e.cfg.BaseDomain, "."))
	path := fmt.Sprintf("/api/v1/check_domain?domain=%s", url.QueryEscape(checkDomain))

	_, _, err := e.doRequest(
		ctx,
		"GET",
		path,
		nil,
		nil,
		204,
	)
	if err != nil {
		return stepOutcome{}, err
	}

	return stepOutcome{}, nil
}

func (e *journeyExecutor) runtimeApproveDevice(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "device_approved" {
		return stepOutcome{}, expectationInvalidFailure("device_approved", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime approval has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for approval",
		)
	}

	payload := map[string]any{
		"data": map[string]any{
			"type": "device",
			"id":   state.DeviceID,
			"attributes": map[string]any{
				"approval_status": "approved",
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could be encoded",
			Message:         fmt.Sprintf("marshal runtime approve payload: %v", err),
		}
	}
	_, _, err = e.doRequest(ctx, "PATCH", fmt.Sprintf("/api/json/devices/%s", state.DeviceID), body, jsonAPIHeaders(), 200)
	if err != nil {
		return stepOutcome{}, err
	}

	apiClient := transport.NewClient(config.APIConfig{URL: e.cfg.APIURL})
	credentials, err := apiClient.RegisterDeviceCredentials(ctx, identity.DeviceIdentity{
		MACAddress: state.DeviceMac,
		Name:       state.ProductName,
	})
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "approved runtime device can obtain API token",
			Message:         fmt.Sprintf("runtime credential refresh failed: %v", err),
		}
	}
	if credentials.Token == "" {
		return stepOutcome{}, assertionFailure(
			"approved runtime device receives an API token",
			map[string]any{"api_token_non_empty": true},
			map[string]any{"api_token_non_empty": false},
			"runtime credential refresh returned no API token",
		)
	}
	if credentials.UUID == "" {
		return stepOutcome{}, assertionFailure(
			"approved runtime device credential refresh returns a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"runtime credential refresh returned no device id",
		)
	}
	state.DeviceID = credentials.UUID
	state.DeviceToken = credentials.Token

	return stepOutcome{ActionData: map[string]any{"device_id": state.DeviceID, "api_token_present": true}}, nil
}

func (e *journeyExecutor) runtimeCreateAlertRule(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "alert_rule_created" {
		return stepOutcome{}, expectationInvalidFailure("alert_rule_created", expect)
	}
	if state.ProductName == "" {
		return stepOutcome{}, assertionFailure(
			"runtime alert rule has a product name",
			map[string]any{"product_name_non_empty": true},
			map[string]any{"product_name_non_empty": false},
			"product name missing for alert rule creation",
		)
	}

	payload := map[string]any{
		"data": map[string]any{
			"type": "alert_rule",
			"attributes": map[string]any{
				"product_name":    state.ProductName,
				"condition_field": "scripts.mem_linux.data.output.memory_used_percent",
				"operator":        ">",
				"threshold_value": "0",
			},
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could be encoded",
			Message:         fmt.Sprintf("marshal runtime alert rule payload: %v", err),
		}
	}
	respBody, _, err := e.doRequest(ctx, "POST", "/api/json/alert_rules", body, jsonAPIHeaders(), 201)
	if err != nil {
		return stepOutcome{}, err
	}

	id, err := parseJSONAPIResourceID(respBody)
	if err != nil {
		return stepOutcome{}, err
	}
	state.AlertRuleID = id
	return stepOutcome{ActionData: map[string]any{"alert_rule_id": id}}, nil
}

func (e *journeyExecutor) runtimeQueuePayloadRefCommand(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "command_payload_available" {
		return stepOutcome{}, expectationInvalidFailure("command_payload_available", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime command queue has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for command queue",
		)
	}

	state.CommandRef = "runtime-install-script"
	commandScript := `---
name: payload_installed_script
version: "1.0.1"
schema:
  type: object
  required: [message]
  properties:
    message: {type: string}
---
def main():
  return {"message": "installed from payload"}
`

	payload := map[string]any{
		"data": map[string]any{
			"type": "pending_command",
			"attributes": map[string]any{
				"device_id": state.DeviceID,
				"command_payload": map[string]any{
					"type":        "install_script",
					"payload_ref": state.CommandRef,
					"payload": map[string]any{
						"content_type": "text/plain",
						"name":         "payload_script",
						"data":         commandScript,
					},
				},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could be encoded",
			Message:         fmt.Sprintf("marshal runtime queue command payload: %v", err),
		}
	}
	if _, _, err := e.doRequest(ctx, "POST", "/api/json/pending_commands", body, jsonAPIHeaders(), 201); err != nil {
		return stepOutcome{}, err
	}

	refPath := fmt.Sprintf("/api/v1/devices/%s/command_payloads/%s", state.DeviceID, state.CommandRef)
	if _, _, err := e.doRequest(ctx, "GET", withAPIKey(refPath, state.DeviceToken), nil, nil, 200); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeAssertionFailed,
			AssertionFailed: "queued command payload is retrievable by payload_ref",
			Message:         fmt.Sprintf("command payload ref not retrievable: %v", err),
		}
	}

	return stepOutcome{ActionData: map[string]any{"payload_ref": state.CommandRef}}, nil
}

func (e *journeyExecutor) runtimeExpectMissingPayloadRef(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "command_payload_missing" {
		return stepOutcome{}, expectationInvalidFailure("command_payload_missing", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime missing payload check has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for missing payload check",
		)
	}

	missingRef := fmt.Sprintf("missing-%d", time.Now().UnixNano())
	path := fmt.Sprintf("/api/v1/devices/%s/command_payloads/%s", state.DeviceID, missingRef)
	_, _, err := e.doRequest(ctx, "GET", withAPIKey(path, state.DeviceToken), nil, nil, 404)
	if err != nil {
		return stepOutcome{}, err
	}

	return stepOutcome{
		ActionData: map[string]any{
			"missing_payload_ref": missingRef,
			"expected_status":     404,
		},
	}, nil
}

func (e *journeyExecutor) runtimeRejectInvalidCommandResults(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "command_results_rejected" {
		return stepOutcome{}, expectationInvalidFailure("command_results_rejected", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime command result rejection has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for command result rejection check",
		)
	}

	invalidPayload := map[string]any{
		"results": map[string]any{
			"invalid": "shape",
		},
	}

	body, err := json.Marshal(invalidPayload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "invalid command result payload could be encoded",
			Message:         fmt.Sprintf("marshal invalid command_results payload: %v", err),
		}
	}

	path := withAPIKey(fmt.Sprintf("/api/v1/devices/%s/command_results", state.DeviceID), state.DeviceToken)
	_, _, err = e.doRequest(ctx, "POST", path, body, map[string]string{"Content-Type": "application/json"}, 400)
	if err != nil {
		return stepOutcome{}, err
	}

	return stepOutcome{
		ActionData: map[string]any{
			"expected_status": 400,
			"reason":          "results must be a list",
		},
	}, nil
}

func (e *journeyExecutor) runtimePollWithScripts(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "scripts_polled_under_budget" {
		return stepOutcome{}, expectationInvalidFailure("scripts_polled_under_budget", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime polling has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for runtime polling",
		)
	}

	state.TelemetryCountBefore = -1
	state.TelemetryCountAfter = -1
	if count, err := e.telemetryEventCount(ctx); err == nil {
		state.TelemetryCountBefore = count
	}
	state.AlertCountBefore = -1
	state.AlertCountAfter = -1
	if count, err := e.alertCount(ctx); err == nil {
		state.AlertCountBefore = count
	}

	scriptDir, err := ensureRuntimeScripts(e.cfg.StaryDir)
	if err != nil {
		return stepOutcome{}, err
	}
	state.ScriptsDir = scriptDir

	pollStart := time.Now()

	apiClient := transport.NewClient(config.APIConfig{URL: e.cfg.APIURL})
	apiClient.SetAPIKey(state.DeviceToken)
	scripts, err := script.DiscoverScripts(scriptDir)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeAssertionFailed,
			AssertionFailed: "runtime scripts could be discovered",
			Message:         fmt.Sprintf("discover runtime scripts: %v", err),
		}
	}
	results, scriptErrors, err := executeScriptsForRuntime(ctx, scripts)
	if err != nil {
		return stepOutcome{}, err
	}

	payload := telemetry.Payload{
		Device: telemetry.DeviceStatus{
			Identity: identity.DeviceIdentity{
				UUID:       state.DeviceID,
				MACAddress: state.DeviceMac,
				Name:       "runtime-linux-e2e",
			},
			Uptime: 60,
		},
		Scripts: results,
		Meta: telemetry.PollMeta{
			Timestamp: time.Now(),
			Duration:  time.Since(pollStart).String(),
			Errors:    scriptErrors,
		},
	}

	pollResp, err := apiClient.Poll(ctx, state.DeviceID, payload, frp.ConnectionStatus{})
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "runtime poll request completed successfully",
			Message:         fmt.Sprintf("runtime poll failed: %v", err),
		}
	}

	if err := executeAndSubmitCommandResults(ctx, apiClient, scriptDir, state.DeviceID, pollResp.Commands); err != nil {
		return stepOutcome{}, err
	}

	if count, err := e.telemetryEventCount(ctx); err == nil {
		state.TelemetryCountAfter = count
	}
	if count, err := e.alertCount(ctx); err == nil {
		state.AlertCountAfter = count
	}

	durationMs := time.Since(pollStart).Milliseconds()
	state.PollDuration = durationMs

	if shouldEnforceRuntimeBudget() && durationMs > 5_000 {
		return stepOutcome{}, assertionFailure(
			"runtime scripts complete within 5 second budget",
			map[string]any{"duration_ms_lte": 5000},
			map[string]any{"duration_ms": durationMs},
			"runtime script execution exceeded 5s budget: %dms",
			durationMs,
		)
	}

	return stepOutcome{
		ResponseType: responseTypeJSON,
		ActionData: map[string]any{
			"script_count":            len(results),
			"duration_ms":             durationMs,
			"script_errors_count":     len(scriptErrors),
			"commands_received_count": len(pollResp.Commands),
		},
	}, nil
}

func (e *journeyExecutor) runtimeVerifyTelemetry(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "telemetry_persisted" {
		return stepOutcome{}, expectationInvalidFailure("telemetry_persisted", expect)
	}

	if state.TelemetryCountBefore >= 0 && state.TelemetryCountAfter >= 0 {
		if state.TelemetryCountAfter > state.TelemetryCountBefore {
			state.TelemetrySeen = true
			return stepOutcome{
				ActionData: map[string]any{
					"before_count": state.TelemetryCountBefore,
					"after_count":  state.TelemetryCountAfter,
					"source":       "counter",
				},
			}, nil
		}
	}

	// Probe persistence via reporting path (backed by telemetry_events).
	probeReportID, err := e.createRuntimeReport(ctx, state.DeviceID, "Runtime Telemetry Probe")
	if err != nil {
		return stepOutcome{}, err
	}
	defer func() {
		_, _, cleanupErr := e.doRequest(ctx, "DELETE", fmt.Sprintf("/api/json/custom_reports/%s", probeReportID), nil, jsonAPIHeaders(), 200, 204)
		if cleanupErr != nil {
			_ = cleanupErr
		}
	}()

	body, _, err := e.doRequest(ctx, "GET", fmt.Sprintf("/api/v1/reports/%s/results", probeReportID), nil, nil, 200)
	if err != nil {
		return stepOutcome{}, err
	}

	var response struct {
		Data struct {
			Fields []map[string]any `json:"fields"`
			Rows   []map[string]any `json:"rows"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "runtime report probe response could be decoded",
			Message:         fmt.Sprintf("decode runtime report probe response: %v", err),
		}
	}
	if len(response.Data.Rows) == 0 {
		if state.TelemetryCountBefore >= 0 && state.TelemetryCountAfter >= 0 {
			return stepOutcome{}, assertionFailure(
				"telemetry event count increases after runtime poll",
				map[string]any{"after_gt_before": true},
				map[string]any{"before": state.TelemetryCountBefore, "after": state.TelemetryCountAfter},
				"telemetry for runtime scripts was not persisted (count before=%d after=%d)",
				state.TelemetryCountBefore, state.TelemetryCountAfter,
			)
		}
		return stepOutcome{}, assertionFailure(
			"telemetry persisted and report has data",
			map[string]any{"report_has_data": true},
			map[string]any{"report_has_data": false},
			"telemetry for runtime scripts was not persisted",
		)
	}

	if !reportFieldsContain(response.Data.Fields, "mem_used_pct") {
		return stepOutcome{}, assertionFailure(
			"telemetry report includes mem_used_pct column",
			map[string]any{"has_mem_used_pct": true},
			map[string]any{"has_mem_used_pct": false},
			"telemetry report rendered without expected mem_used_pct column",
		)
	}

	state.TelemetrySeen = true
	return stepOutcome{
		ActionData: map[string]any{
			"source":       "report_probe",
			"report_id":    probeReportID,
			"before_count": state.TelemetryCountBefore,
			"after_count":  state.TelemetryCountAfter,
		},
	}, nil
}

func (e *journeyExecutor) telemetryEventCount(ctx context.Context) (int, error) {
	respBody, _, err := e.doRequest(
		ctx,
		"GET",
		"/api/json/telemetry_events?page[limit]=10000",
		nil,
		jsonAPIHeaders(),
		200,
	)
	if err != nil {
		return 0, err
	}

	var response struct {
		Data []json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(respBody, &response); err != nil {
		return 0, fmt.Errorf("decode telemetry count response: %w", err)
	}

	return len(response.Data), nil
}

func (e *journeyExecutor) alertCount(ctx context.Context) (int, error) {
	respBody, _, err := e.doRequest(
		ctx,
		"GET",
		"/api/json/alerts?page[limit]=10000",
		nil,
		jsonAPIHeaders(),
		200,
	)
	if err != nil {
		return 0, err
	}

	var response struct {
		Data []json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(respBody, &response); err != nil {
		return 0, fmt.Errorf("decode alert count response: %w", err)
	}

	return len(response.Data), nil
}

func (e *journeyExecutor) runtimeCreateReport(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "report_created" {
		return stepOutcome{}, expectationInvalidFailure("report_created", expect)
	}
	if state.DeviceID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime report creation has a device id",
			map[string]any{"device_id_non_empty": true},
			map[string]any{"device_id_non_empty": false},
			"device id missing for report creation",
		)
	}

	id, err := e.createRuntimeReport(ctx, state.DeviceID, "Runtime E2E")
	if err != nil {
		return stepOutcome{}, err
	}
	state.ReportID = id
	return stepOutcome{ActionData: map[string]any{"report_id": id}}, nil
}

func (e *journeyExecutor) createRuntimeReport(ctx context.Context, deviceID, namePrefix string) (string, error) {
	configPayload := map[string]any{
		"source": "telemetry",
		"fields": []map[string]any{
			{"path": "scripts.mem_linux.data.output.memory_used_percent", "alias": "mem_used_pct"},
			{"path": "scripts.disk_root.data.output.root_usage_percent", "alias": "disk_used_pct"},
		},
		"filters": []map[string]any{
			{"field": "device_id", "operator": "=", "value": deviceID},
		},
	}

	payload := map[string]any{
		"data": map[string]any{
			"type": "custom_report",
			"attributes": map[string]any{
				"name":   fmt.Sprintf("%s %d", namePrefix, time.Now().UnixNano()),
				"config": configPayload,
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("marshal runtime report payload: %w", err)
	}
	respBody, _, err := e.doRequest(ctx, "POST", "/api/json/custom_reports", body, jsonAPIHeaders(), 201)
	if err != nil {
		return "", err
	}

	id, err := parseJSONAPIResourceID(respBody)
	if err != nil {
		return "", err
	}

	return id, nil
}

func (e *journeyExecutor) runtimeVerifyReport(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "report_rendered" {
		return stepOutcome{}, expectationInvalidFailure("report_rendered", expect)
	}
	if state.ReportID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime report verification has a report id",
			map[string]any{"report_id_non_empty": true},
			map[string]any{"report_id_non_empty": false},
			"report id missing",
		)
	}

	body, _, err := e.doRequest(ctx, "GET", fmt.Sprintf("/api/v1/reports/%s/results", state.ReportID), nil, nil, 200)
	if err != nil {
		return stepOutcome{}, err
	}

	var response struct {
		Data struct {
			Fields []map[string]any `json:"fields"`
			Rows   []map[string]any `json:"rows"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "runtime report response could be decoded",
			Message:         fmt.Sprintf("decode runtime report response: %v", err),
		}
	}

	if len(response.Data.Rows) == 0 {
		return stepOutcome{}, assertionFailure(
			"runtime report renders data",
			map[string]any{"report_has_data": true},
			map[string]any{"report_has_data": false},
			"report rendered without data",
		)
	}
	if !reportFieldsContain(response.Data.Fields, "mem_used_pct") {
		return stepOutcome{}, assertionFailure(
			"runtime report includes mem_used_pct column",
			map[string]any{"has_mem_used_pct": true},
			map[string]any{"has_mem_used_pct": false},
			"report columns missing expected field",
		)
	}
	return stepOutcome{ActionData: map[string]any{"report_id": state.ReportID}}, nil
}

func reportFieldsContain(fields []map[string]any, key string) bool {
	for _, field := range fields {
		if alias, _ := field["alias"].(string); alias == key {
			return true
		}
		if path, _ := field["path"].(string); path == key {
			return true
		}
	}

	return false
}

func (e *journeyExecutor) runtimeVerifyAlert(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "alert_triggered" {
		return stepOutcome{}, expectationInvalidFailure("alert_triggered", expect)
	}
	if state.AlertRuleID == "" {
		return stepOutcome{}, assertionFailure(
			"runtime alert verification has an alert rule id",
			map[string]any{"alert_rule_id_non_empty": true},
			map[string]any{"alert_rule_id_non_empty": false},
			"alert rule id missing",
		)
	}

	if state.AlertCountBefore >= 0 && state.AlertCountAfter >= 0 {
		if state.AlertCountAfter > state.AlertCountBefore {
			return stepOutcome{
				ActionData: map[string]any{
					"before": state.AlertCountBefore,
					"after":  state.AlertCountAfter,
				},
			}, nil
		}
		return stepOutcome{}, assertionFailure(
			"expected alert count increase was observed",
			map[string]any{"after_gt_before": true},
			map[string]any{"before": state.AlertCountBefore, "after": state.AlertCountAfter},
			"expected alert count increase was not observed (before=%d after=%d)",
			state.AlertCountBefore, state.AlertCountAfter,
		)
	}

	if count, err := e.alertCount(ctx); err == nil && count > 0 {
		return stepOutcome{ActionData: map[string]any{"observed_count": count}}, nil
	}

	return stepOutcome{}, assertionFailure(
		"expected active alert exists",
		map[string]any{"active_alerts_gt": 0},
		map[string]any{"active_alerts_gt": 0},
		"expected active alert was not found",
	)
}

func (e *journeyExecutor) runtimeCleanup(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "runtime_resources_cleaned" {
		return stepOutcome{}, expectationInvalidFailure("runtime_resources_cleaned", expect)
	}

	warnings := make([]string, 0)

	if state.ReportID != "" {
		if _, _, err := e.doRequest(ctx, "DELETE", fmt.Sprintf("/api/json/custom_reports/%s", state.ReportID), nil, jsonAPIHeaders(), 200, 204); err != nil {
			warnings = append(warnings, fmt.Sprintf("report cleanup failed: %v", err))
		}
	}

	if state.AlertRuleID != "" {
		if _, _, err := e.doRequest(ctx, "DELETE", fmt.Sprintf("/api/json/alert_rules/%s", state.AlertRuleID), nil, jsonAPIHeaders(), 200, 204); err != nil {
			warnings = append(warnings, fmt.Sprintf("alert rule cleanup failed: %v", err))
		}
	}

	if state.DeviceID != "" {
		if _, _, err := e.doRequest(ctx, "DELETE", fmt.Sprintf("/api/json/devices/%s", state.DeviceID), nil, jsonAPIHeaders(), 200, 204); err != nil {
			warnings = append(warnings, fmt.Sprintf("device cleanup failed: %v", err))
		}
	}

	if state.ScriptsDir != "" {
		if err := os.RemoveAll(state.ScriptsDir); err != nil {
			warnings = append(warnings, fmt.Sprintf("script directory cleanup failed: %v", err))
		}
	}

	return stepOutcome{ActionData: map[string]any{"cleanup_warnings": warnings}}, nil
}

func jsonAPIHeaders() map[string]string {
	return map[string]string{
		"Content-Type": "application/vnd.api+json",
		"Accept":       "application/vnd.api+json",
	}
}

func parseJSONAPIResourceID(body []byte) (string, error) {
	var response struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return "", &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "response JSON could be parsed",
			Message:         fmt.Sprintf("decode jsonapi id: %v", err),
		}
	}
	if response.Data.ID == "" {
		return "", assertionFailure(
			"jsonapi response includes data.id",
			map[string]any{"data.id_non_empty": true},
			map[string]any{"data.id_non_empty": false},
			"jsonapi response missing data.id",
		)
	}
	return response.Data.ID, nil
}

func executeScriptsForRuntime(
	ctx context.Context,
	scripts []script.ScriptInfo,
) (reports map[string]telemetry.Report, scriptErrors []string, err error) {
	executor := script.NewExecutor(script.RuntimeConfig{
		Timeout:   5 * time.Second,
		WarnAfter: 3 * time.Second,
		ExecCommandAllowlist: map[string]string{
			"cat":   "/bin/cat",
			"df":    "/bin/df",
			"nproc": "/usr/bin/nproc",
			"stat":  "/usr/bin/stat",
			"uname": "/usr/bin/uname",
		},
	})

	scriptResults, err := executor.ExecuteScripts(ctx, scripts)
	if err != nil {
		return nil, nil, fmt.Errorf("execute runtime scripts: %w", err)
	}

	reports = make(map[string]telemetry.Report, len(scriptResults))
	scriptErrors = make([]string, 0)

	for name, result := range scriptResults {
		reports[name] = script.ToReport(result)
		if result.Status != script.StatusSuccess {
			if result.Error != nil {
				return nil, nil, fmt.Errorf("runtime script %s failed: %s", name, result.Error.Message)
			}
			return nil, nil, fmt.Errorf("runtime script %s failed", name)
		}
		if result.Error != nil {
			scriptErrors = append(scriptErrors, name+": "+result.Error.Message)
		}
	}

	return reports, scriptErrors, nil
}

func executeAndSubmitCommandResults(
	ctx context.Context,
	client *transport.Client,
	scriptsDir string,
	deviceID string,
	commandsFromServer []transport.CommandRequest,
) error {
	readyCommands, failures := hydrateCommandPayloadsRuntime(ctx, client, deviceID, commandsFromServer)

	handler := commands.NewHandler(scriptsDir)
	results := handler.ExecuteBatch(ctx, readyCommands)
	results = append(results, failures...)

	if len(results) == 0 {
		return nil
	}

	if err := client.SendCommandResults(ctx, deviceID, results); err != nil {
		return fmt.Errorf("submit command results: %w", err)
	}
	return nil
}

func hydrateCommandPayloadsRuntime(
	ctx context.Context,
	client *transport.Client,
	deviceID string,
	commandsFromServer []transport.CommandRequest,
) ([]transport.CommandRequest, []transport.CommandResult) {
	ready := make([]transport.CommandRequest, 0, len(commandsFromServer))
	failures := make([]transport.CommandResult, 0)

	for _, command := range commandsFromServer {
		if command.PayloadRef == "" || command.Payload != nil {
			ready = append(ready, command)
			continue
		}

		payload, err := client.FetchCommandPayload(ctx, deviceID, command.PayloadRef)
		if err != nil {
			failures = append(failures, transport.CommandResult{
				CommandID: command.CommandID,
				Status:    transport.CommandStatusFailed,
				Error:     "payload_fetch_failed: " + err.Error(),
			})
			continue
		}

		command.Payload = payload
		ready = append(ready, command)
	}

	return ready, failures
}

func shouldEnforceRuntimeBudget() bool {
	return runtime.GOOS == "linux" &&
		strings.EqualFold(os.Getenv("CI"), "true") &&
		strings.EqualFold(os.Getenv("E2E_RUNTIME_PERF_GATE"), "true")
}

func withAPIKey(path, token string) string {
	if token == "" {
		return path
	}

	separator := "?"
	if strings.Contains(path, "?") {
		separator = "&"
	}

	return path + separator + "api_key=" + url.QueryEscape(token)
}
