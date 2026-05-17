package e2e

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const (
	logSchemaV1          = "e2e_log.v1"
	responseTypeJSON     = "json_response"
	responseTypeHTML     = "html_response"
	responsePreviewBytes = 500
	redactedValue        = "[REDACTED]"

	errCodeAssertionFailed       = "ASSERTION_FAILED"
	errCodeHTTPRequestFailed     = "HTTP_REQUEST_FAILED"
	errCodeHTTPStatusUnexpected  = "HTTP_STATUS_UNEXPECTED"
	errCodeResponseParseFailed   = "RESPONSE_PARSE_FAILED"
	errCodeTimeout               = "TIMEOUT"
	errCodeResponseTypeViolation = "RESPONSE_TYPE_VIOLATION"
	errCodeExpectationInvalid    = "EXPECTATION_INVALID"
)

var responseTypeByAction = map[string]string{
	actionRegisterDevice:        responseTypeJSON,
	actionFetchDashboard:        responseTypeHTML,
	actionCreateRecord:          responseTypeJSON,
	actionUpdateRecord:          responseTypeJSON,
	actionLogout:                responseTypeJSON,
	actionRuntimeRegisterDevice: responseTypeJSON,
}

var sensitiveKeyTokens = []string{
	"authorization",
	"cookie",
	"token",
	"password",
	"secret",
	"api_key",
	"apikey",
	"access_key",
	"private_key",
	"bearer",
}

type journeyExecutor struct {
	baseURL string
	client  *http.Client
	log     *journeyLog
	cfg     Config
}

type runLogContext struct {
	RunID            string `json:"run_id"`
	SuiteID          string `json:"suite_id"`
	EnvironmentLabel string `json:"environment_label"`
	TriggerSource    string `json:"trigger_source"`
	ProtocolVersion  string `json:"protocol_version"`
}

type journeyLog struct {
	buf       bytes.Buffer
	journeyID string
	run       runLogContext
}

type journeyLogEntry struct {
	Schema          string         `json:"schema"`
	Timestamp       string         `json:"timestamp"`
	Level           string         `json:"level"`
	Event           string         `json:"event,omitempty"`
	Status          string         `json:"status"`
	JourneyID       string         `json:"journey_id,omitempty"`
	Run             *runLogContext `json:"run,omitempty"`
	StepID          string         `json:"step_id,omitempty"`
	Action          string         `json:"action,omitempty"`
	Expect          string         `json:"expect,omitempty"`
	DurationMs      int64          `json:"duration_ms,omitempty"`
	HTTPStatus      *int           `json:"http_status,omitempty"`
	ResponseType    string         `json:"response_type,omitempty"`
	Bytes           *int           `json:"bytes,omitempty"`
	Truncated       *bool          `json:"truncated,omitempty"`
	ActionData      map[string]any `json:"action_data,omitempty"`
	ErrorCode       string         `json:"error_code,omitempty"`
	AssertionFailed string         `json:"assertion_failed,omitempty"`
	ErrorMessage    string         `json:"error_message,omitempty"`
	Expected        any            `json:"expected,omitempty"`
	Actual          any            `json:"actual,omitempty"`
	StepsRun        int            `json:"steps_run,omitempty"`
	StepsPassed     int            `json:"steps_passed,omitempty"`
	StepsFailed     int            `json:"steps_failed,omitempty"`
	FailureStep     string         `json:"failure_step,omitempty"`
	FailureCode     string         `json:"failure_code,omitempty"`
}

type stepOutcome struct {
	HTTPStatus   *int
	ResponseType string
	Bytes        *int
	Truncated    *bool
	ActionData   map[string]any
}

type stepError struct {
	Code            string
	AssertionFailed string
	Message         string
	Expected        any
	Actual          any
}

func (f *stepError) Error() string {
	if f == nil {
		return "step failed"
	}
	if strings.TrimSpace(f.Message) != "" {
		return f.Message
	}
	if strings.TrimSpace(f.AssertionFailed) != "" {
		return f.AssertionFailed
	}
	return "step failed"
}

type deviceResponse struct {
	Data struct {
		ID         string `json:"id"`
		MacAddress string `json:"mac_address"`
	} `json:"data"`
}

type jsonAPIResponse struct {
	Data struct {
		ID string `json:"id"`
	} `json:"data"`
	Errors []struct {
		Title  string `json:"title"`
		Detail string `json:"detail"`
	} `json:"errors"`
}

func newJourneyExecutor(cfg Config, log *journeyLog) *journeyExecutor {
	return &journeyExecutor{
		baseURL: strings.TrimRight(cfg.APIURL, "/"),
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		log: log,
		cfg: cfg,
	}
}

func newJourneyLog(journeyID string, run runLogContext) *journeyLog {
	return &journeyLog{journeyID: journeyID, run: run}
}

func (r *Runner) executeJourney(ctx context.Context, run runData, journeyID string, sequence int) (JourneyResult, resultPayload) {
	start := time.Now()
	log := newJourneyLog(
		journeyID,
		runLogContext{
			RunID:            run.ID,
			SuiteID:          firstNonBlank(run.SuiteID, r.cfg.Suite),
			EnvironmentLabel: firstNonBlank(run.EnvironmentLabel, r.cfg.Environment),
			TriggerSource:    firstNonBlank(run.TriggerSource, r.cfg.Trigger),
			ProtocolVersion:  firstNonBlank(run.ProtocolVersion, r.cfg.ProtocolVersion),
		},
	)
	log.logJourneyStarted()

	spec, err := loadJourneySpec(journeyID)
	if err != nil {
		failure := classifyStepFailure(err, "load journey spec")
		failureStep := "load_journey"

		log.logStep(
			journeyStep{Action: failureStep},
			statusFailed,
			0,
			stepOutcome{},
			failure,
		)
		log.logJourneyCompleted(statusFailed, time.Since(start).Milliseconds(), 1, 0, 1, failureStep, failure.Code)

		return r.finishJourney(journeyID, statusFailed, failureStep, failure.Error(), log, run.ID, start, sequence)
	}

	executor := newJourneyExecutor(r.cfg, log)
	state := &journeyState{}
	stepsRun := 0
	stepsPassed := 0
	stepsFailed := 0

	for _, step := range spec.Steps {
		stepStart := time.Now()
		outcome, err := executor.executeStep(ctx, state, step)
		stepDuration := time.Since(stepStart).Milliseconds()
		stepsRun++
		stepID := step.effectiveStepID()

		if err == nil {
			if responseTypeErr := validateResponseTypeContract(step.Action, outcome.ResponseType); responseTypeErr != nil {
				err = responseTypeErr
			}
		}

		if err != nil {
			failure := classifyStepFailure(err, fmt.Sprintf("step %s failed", step.Action))
			stepsFailed++

			log.logStep(step, statusFailed, stepDuration, outcome, failure)
			log.logJourneyCompleted(
				statusFailed,
				time.Since(start).Milliseconds(),
				stepsRun,
				stepsPassed,
				stepsFailed,
				stepID,
				failure.Code,
			)

			return r.finishJourney(journeyID, statusFailed, stepID, failure.Error(), log, run.ID, start, sequence)
		}

		stepsPassed++
		log.logStep(step, statusPassed, stepDuration, outcome, nil)
	}

	log.logJourneyCompleted(statusPassed, time.Since(start).Milliseconds(), stepsRun, stepsPassed, stepsFailed, "", "")
	return r.finishJourney(journeyID, statusPassed, "", "", log, run.ID, start, sequence)
}

func (r *Runner) finishJourney(journeyID, status, failureStep, failureReason string, log *journeyLog, runID string, start time.Time, sequence int) (JourneyResult, resultPayload) {
	duration := time.Since(start).Milliseconds()

	logRef, logErr := writeJourneyLog(r.cfg.LogDir, runID, journeyID, sequence, log.buf.String())
	if logErr != nil && status == statusPassed {
		status = statusFailed
		failureStep = "write_log"
		failureReason = logErr.Error()
	}

	result := JourneyResult{
		JourneyID:  journeyID,
		Status:     status,
		Error:      failureReason,
		DurationMs: duration,
	}

	payload := resultPayload{
		JourneyID:     journeyID,
		Status:        status,
		FailureStep:   failureStep,
		FailureReason: failureReason,
		LogRef:        logRef,
		DurationMs:    duration,
	}

	return result, payload
}

func (e *journeyExecutor) executeStep(ctx context.Context, state *journeyState, step journeyStep) (stepOutcome, error) {
	handler, ok := e.stepHandlers()[step.Action]
	if !ok {
		return stepOutcome{}, &stepError{
			Code:            errCodeExpectationInvalid,
			AssertionFailed: "action is not supported by the runner",
			Message:         fmt.Sprintf("unknown action: %s", step.Action),
			Expected:        "known action",
			Actual:          step.Action,
		}
	}

	return handler(ctx, state, step.Expect)
}

func (e *journeyExecutor) stepHandlers() map[string]func(context.Context, *journeyState, string) (stepOutcome, error) {
	return map[string]func(context.Context, *journeyState, string) (stepOutcome, error){
		actionRegisterDevice:         e.registerDevice,
		actionFetchDashboard:         wrapNoStateStep(e.fetchDashboard),
		actionCreateRecord:           e.createRecord,
		actionUpdateRecord:           e.updateRecord,
		actionLogout:                 e.logout,
		actionRuntimeRegisterDevice:  e.runtimeRegisterDevice,
		actionRuntimeCheckDomain:     e.runtimeCheckDomain,
		actionRuntimeApproveDevice:   e.runtimeApproveDevice,
		actionRuntimeCreateAlertRule: e.runtimeCreateAlertRule,
		actionRuntimeQueuePayloadRef: e.runtimeQueuePayloadRefCommand,
		actionRuntimeMissingPayload:  e.runtimeExpectMissingPayloadRef,
		actionRuntimeRejectCmdResult: e.runtimeRejectInvalidCommandResults,
		actionRuntimePollWithScripts: e.runtimePollWithScripts,
		actionRuntimeVerifyTelemetry: e.runtimeVerifyTelemetry,
		actionRuntimeCreateReport:    e.runtimeCreateReport,
		actionRuntimeVerifyReport:    e.runtimeVerifyReport,
		actionRuntimeVerifyAlert:     e.runtimeVerifyAlert,
		actionRuntimeCleanup:         e.runtimeCleanup,
	}
}

func wrapNoStateStep(fn func(context.Context, string) (stepOutcome, error)) func(context.Context, *journeyState, string) (stepOutcome, error) {
	return func(ctx context.Context, _ *journeyState, expect string) (stepOutcome, error) {
		return fn(ctx, expect)
	}
}

func (e *journeyExecutor) registerDevice(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "uuid_returned" {
		return stepOutcome{}, expectationInvalidFailure("uuid_returned", expect)
	}

	mac := generateMac()
	account := generateAccountNumber()
	productName := "E2E Device"

	payload := map[string]any{
		"mac_address":    mac,
		"product_name":   productName,
		"account_number": account,
		"schema_definition": map[string]any{
			"product":    productName,
			"type":       "object",
			"properties": map[string]any{},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could not be encoded",
			Message:         fmt.Sprintf("marshal device payload: %v", err),
		}
	}

	respBody, status, err := e.doRequest(ctx, http.MethodPost, "/api/v1/devices/register", body, map[string]string{
		"Content-Type": "application/json",
	}, http.StatusCreated)
	if err != nil {
		return stepOutcome{}, err
	}

	var response deviceResponse
	if err := json.Unmarshal(respBody, &response); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "response JSON could not be parsed",
			Message:         fmt.Sprintf("decode device response: %v", err),
		}
	}

	if response.Data.ID == "" {
		return stepOutcome{}, assertionFailure(
			"device id must be present",
			map[string]any{"data.id_non_empty": true},
			map[string]any{"data.id": response.Data.ID},
			"expected device id but got empty",
		)
	}

	state.DeviceID = response.Data.ID
	state.DeviceMac = mac

	return responseOutcome(responseTypeJSON, status, respBody, map[string]any{"device_id": response.Data.ID}), nil
}

func (e *journeyExecutor) fetchDashboard(ctx context.Context, expect string) (stepOutcome, error) {
	if expect != "dashboard_payload" {
		return stepOutcome{}, expectationInvalidFailure("dashboard_payload", expect)
	}

	respBody, status, err := e.doRequest(ctx, http.MethodGet, "/", nil, nil, http.StatusOK)
	if err != nil {
		return stepOutcome{}, err
	}

	if len(respBody) == 0 {
		return stepOutcome{}, assertionFailure(
			"dashboard response body must be non-empty",
			map[string]any{"body_non_empty": true},
			map[string]any{"body_non_empty": false},
			"dashboard response was empty",
		)
	}

	return responseOutcome(responseTypeHTML, status, respBody, nil), nil
}

func (e *journeyExecutor) createRecord(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "record_created" {
		return stepOutcome{}, expectationInvalidFailure("record_created", expect)
	}

	name := fmt.Sprintf("E2E Report %d", time.Now().UnixNano())

	payload := map[string]any{
		"data": map[string]any{
			"type": "custom_report",
			"attributes": map[string]any{
				"name":   name,
				"config": map[string]any{"source": "e2e", "journey": "create_record"},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could not be encoded",
			Message:         fmt.Sprintf("marshal record payload: %v", err),
		}
	}

	respBody, status, err := e.doRequest(ctx, http.MethodPost, "/api/json/custom_reports", body, map[string]string{
		"Content-Type": "application/vnd.api+json",
		"Accept":       "application/vnd.api+json",
	}, http.StatusCreated, http.StatusOK)
	if err != nil {
		return stepOutcome{}, err
	}

	var response jsonAPIResponse
	if err := json.Unmarshal(respBody, &response); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "response JSON could not be parsed",
			Message:         fmt.Sprintf("decode record response: %v", err),
		}
	}
	if len(response.Errors) > 0 {
		return stepOutcome{}, assertionFailure(
			"record API errors must be empty",
			map[string]any{"errors_count": 0},
			map[string]any{"errors_count": len(response.Errors), "first_error": response.Errors[0].Detail},
			"record API error: %s",
			response.Errors[0].Detail,
		)
	}

	if response.Data.ID == "" {
		return stepOutcome{}, assertionFailure(
			"record id must be present",
			map[string]any{"data.id_non_empty": true},
			map[string]any{"data.id": response.Data.ID},
			"expected record id but got empty",
		)
	}

	state.ReportID = response.Data.ID

	return responseOutcome(responseTypeJSON, status, respBody, map[string]any{"record_id": response.Data.ID}), nil
}

func (e *journeyExecutor) updateRecord(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "record_updated" {
		return stepOutcome{}, expectationInvalidFailure("record_updated", expect)
	}

	preconditionResolved := false
	if state.ReportID == "" {
		if _, err := e.createRecord(ctx, state, "record_created"); err != nil {
			return stepOutcome{}, &stepError{
				Code:            errCodeAssertionFailed,
				AssertionFailed: "update step precondition record creation must succeed",
				Message:         fmt.Sprintf("create record for update: %v", err),
			}
		}
		preconditionResolved = true
	}

	payload := map[string]any{
		"data": map[string]any{
			"type": "custom_report",
			"id":   state.ReportID,
			"attributes": map[string]any{
				"name":   fmt.Sprintf("E2E Report %d (updated)", time.Now().UnixNano()),
				"config": map[string]any{"source": "e2e", "journey": "update_record"},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "request payload could not be encoded",
			Message:         fmt.Sprintf("marshal update payload: %v", err),
		}
	}

	respBody, status, err := e.doRequest(ctx, http.MethodPatch, fmt.Sprintf("/api/json/custom_reports/%s", state.ReportID), body, map[string]string{
		"Content-Type": "application/vnd.api+json",
		"Accept":       "application/vnd.api+json",
	}, http.StatusOK)
	if err != nil {
		return stepOutcome{}, err
	}

	var response jsonAPIResponse
	if err := json.Unmarshal(respBody, &response); err != nil {
		return stepOutcome{}, &stepError{
			Code:            errCodeResponseParseFailed,
			AssertionFailed: "response JSON could not be parsed",
			Message:         fmt.Sprintf("decode update response: %v", err),
		}
	}
	if len(response.Errors) > 0 {
		return stepOutcome{}, assertionFailure(
			"update API errors must be empty",
			map[string]any{"errors_count": 0},
			map[string]any{"errors_count": len(response.Errors), "first_error": response.Errors[0].Detail},
			"update API error: %s",
			response.Errors[0].Detail,
		)
	}

	if response.Data.ID == "" {
		return stepOutcome{}, assertionFailure(
			"updated record id must be present",
			map[string]any{"data.id_non_empty": true},
			map[string]any{"data.id": response.Data.ID},
			"expected updated record id but got empty",
		)
	}

	return responseOutcome(responseTypeJSON, status, respBody, map[string]any{
		"record_id":                response.Data.ID,
		"precondition_auto_create": preconditionResolved,
	}), nil
}

func (e *journeyExecutor) logout(ctx context.Context, state *journeyState, expect string) (stepOutcome, error) {
	if expect != "session_ended" {
		return stepOutcome{}, expectationInvalidFailure("session_ended", expect)
	}

	preconditionResolved := false
	if state.DeviceID == "" {
		if _, err := e.registerDevice(ctx, state, "uuid_returned"); err != nil {
			return stepOutcome{}, &stepError{
				Code:            errCodeAssertionFailed,
				AssertionFailed: "logout step precondition device registration must succeed",
				Message:         fmt.Sprintf("register device for logout: %v", err),
			}
		}
		preconditionResolved = true
	}

	respBody, status, err := e.doRequest(ctx, http.MethodDelete, fmt.Sprintf("/api/json/devices/%s", state.DeviceID), nil, map[string]string{
		"Accept": "application/vnd.api+json",
	}, http.StatusNoContent, http.StatusOK)
	if err != nil {
		return stepOutcome{}, err
	}

	return responseOutcome(responseTypeJSON, status, respBody, map[string]any{
		"device_id":                  state.DeviceID,
		"precondition_auto_register": preconditionResolved,
	}), nil
}

func (e *journeyExecutor) doRequest(ctx context.Context, method, path string, payload []byte, headers map[string]string, expectedStatuses ...int) (body []byte, status int, err error) {
	url := e.baseURL + path
	var bodyReader io.Reader
	if payload != nil {
		bodyReader = bytes.NewBuffer(payload)
	}

	req, err := http.NewRequestWithContext(ctx, method, url, bodyReader)
	if err != nil {
		return nil, 0, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "HTTP request could be constructed",
			Message:         fmt.Sprintf("create request: %v", err),
		}
	}

	for key, value := range headers {
		req.Header.Set(key, value)
	}

	resp, err := e.client.Do(req)
	if err != nil {
		if isTimeoutError(err) {
			return nil, 0, &stepError{
				Code:            errCodeTimeout,
				AssertionFailed: "HTTP request completed within timeout",
				Message:         fmt.Sprintf("request timed out: %v", err),
			}
		}
		return nil, 0, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "HTTP request completed successfully",
			Message:         fmt.Sprintf("request failed: %v", err),
		}
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, &stepError{
			Code:            errCodeHTTPRequestFailed,
			AssertionFailed: "HTTP response body could be read",
			Message:         fmt.Sprintf("read response: %v", err),
		}
	}

	if slices.Contains(expectedStatuses, resp.StatusCode) {
		return respBody, resp.StatusCode, nil
	}

	return respBody, resp.StatusCode, &stepError{
		Code:            errCodeHTTPStatusUnexpected,
		AssertionFailed: "HTTP status matched expected set",
		Message:         fmt.Sprintf("unexpected status %d: %s", resp.StatusCode, truncate(respBody)),
		Expected:        expectedStatuses,
		Actual: map[string]any{
			"http_status":  resp.StatusCode,
			"body_preview": truncate(respBody),
		},
	}
}

func writeJourneyLog(logDir, runID, journeyID string, sequence int, content string) (string, error) {
	root, err := moduleRoot()
	if err != nil {
		return "", err
	}

	if logDir == "" {
		logDir = filepath.Join("tmp", "e2e", "logs")
	}

	if !filepath.IsAbs(logDir) {
		logDir = filepath.Join(root, logDir)
	}

	if err := os.MkdirAll(logDir, 0o750); err != nil {
		return "", fmt.Errorf("create log dir: %w", err)
	}

	runDir := filepath.Join(logDir, runID)
	if err := os.MkdirAll(runDir, 0o750); err != nil {
		return "", fmt.Errorf("create run log dir: %w", err)
	}

	filename := fmt.Sprintf("%03d-%s.log", sequence, journeyID)
	path := filepath.Join(runDir, filename)

	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return "", fmt.Errorf("write log: %w", err)
	}

	return canonicalLogRef(path), nil
}

func canonicalLogRef(path string) string {
	containerPrefix := strings.TrimSpace(os.Getenv("E2E_CONTAINER_PATH_PREFIX"))
	hostPrefix := strings.TrimSpace(os.Getenv("E2E_HOST_PATH_PREFIX"))
	if containerPrefix == "" || hostPrefix == "" {
		return path
	}

	containerPrefix = filepath.Clean(containerPrefix)
	hostPrefix = filepath.Clean(hostPrefix)
	cleanPath := filepath.Clean(path)

	if cleanPath == containerPrefix {
		return hostPrefix
	}
	if strings.HasPrefix(cleanPath, containerPrefix+"/") {
		return hostPrefix + strings.TrimPrefix(cleanPath, containerPrefix)
	}

	return path
}

func (l *journeyLog) logJourneyStarted() {
	entry := journeyLogEntry{
		Schema:    logSchemaV1,
		Level:     "journey",
		Event:     "started",
		Status:    "running",
		JourneyID: l.journeyID,
		Run:       &l.run,
	}
	l.logEntry(entry)
}

func (l *journeyLog) logJourneyCompleted(status string, durationMs int64, stepsRun, stepsPassed, stepsFailed int, failureStep, failureCode string) {
	entry := journeyLogEntry{
		Schema:      logSchemaV1,
		Level:       "journey",
		Event:       "completed",
		Status:      status,
		JourneyID:   l.journeyID,
		DurationMs:  durationMs,
		StepsRun:    stepsRun,
		StepsPassed: stepsPassed,
		StepsFailed: stepsFailed,
		FailureStep: failureStep,
		FailureCode: failureCode,
	}
	l.logEntry(entry)
}

func (l *journeyLog) logStep(step journeyStep, status string, durationMs int64, outcome stepOutcome, failure *stepError) {
	stepID := strings.TrimSpace(step.StepID)
	if stepID == step.Action {
		stepID = ""
	}

	entry := journeyLogEntry{
		Schema:       logSchemaV1,
		Level:        "step",
		Status:       status,
		StepID:       stepID,
		Action:       step.Action,
		Expect:       step.Expect,
		DurationMs:   durationMs,
		HTTPStatus:   outcome.HTTPStatus,
		ResponseType: outcome.ResponseType,
		Bytes:        outcome.Bytes,
		Truncated:    outcome.Truncated,
		ActionData:   sanitizeActionData(outcome.ActionData),
	}

	if failure != nil {
		entry.ErrorCode = firstNonBlank(failure.Code, errCodeAssertionFailed)
		entry.AssertionFailed = firstNonBlank(failure.AssertionFailed, "step execution failed")
		entry.ErrorMessage = firstNonBlank(failure.Message, failure.AssertionFailed)
		entry.Expected = sanitizeSensitiveValue("expected", failure.Expected)
		entry.Actual = sanitizeSensitiveValue("actual", failure.Actual)
	}

	l.logEntry(entry)
}

func (l *journeyLog) logEntry(entry journeyLogEntry) {
	if entry.Schema == "" {
		entry.Schema = logSchemaV1
	}
	if entry.Timestamp == "" {
		entry.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if entry.Status == "" {
		entry.Status = "info"
	}

	encoded, err := json.Marshal(entry)
	if err != nil {
		fallback := journeyLogEntry{
			Schema:          logSchemaV1,
			Timestamp:       time.Now().UTC().Format(time.RFC3339Nano),
			Level:           "step",
			Status:          statusFailed,
			StepID:          "logging_error",
			Action:          "logging_error",
			DurationMs:      0,
			ErrorCode:       errCodeResponseParseFailed,
			AssertionFailed: "log entry could be encoded",
			ErrorMessage:    fmt.Sprintf("failed to encode log entry: %v", err),
		}

		encoded, err = json.Marshal(fallback)
		if err != nil {
			encoded = []byte(`{"schema":"e2e_log.v1","level":"step","status":"failed","step_id":"logging_error","action":"logging_error","error_code":"RESPONSE_PARSE_FAILED","assertion_failed":"failed to encode fallback log entry"}`)
		}
	}

	l.buf.Write(encoded)
	l.buf.WriteByte('\n')
}

func validateResponseTypeContract(action, responseType string) error {
	expectedType, expectsResponseType := responseTypeByAction[action]
	if !expectsResponseType {
		return nil
	}

	if responseType == "" {
		return &stepError{
			Code:            errCodeResponseTypeViolation,
			AssertionFailed: "response type was logged for action",
			Message:         fmt.Sprintf("action %s expected response type %s but no response type was logged", action, expectedType),
			Expected:        expectedType,
			Actual:          "",
		}
	}

	if responseType != expectedType {
		return &stepError{
			Code:            errCodeResponseTypeViolation,
			AssertionFailed: "response type matched action contract",
			Message:         fmt.Sprintf("action %s expected response type %s but got %s", action, expectedType, responseType),
			Expected:        expectedType,
			Actual:          responseType,
		}
	}

	return nil
}

func responseOutcome(responseType string, httpStatus int, body []byte, actionData map[string]any) stepOutcome {
	httpStatusValue := httpStatus
	bytesValue := len(body)
	preview, truncated := responsePreview(body)

	clonedActionData := cloneMap(actionData)
	if preview != "" {
		if clonedActionData == nil {
			clonedActionData = map[string]any{}
		}
		clonedActionData["body_preview"] = preview

		if responseType == responseTypeJSON && !truncated {
			var parsed any
			if err := json.Unmarshal([]byte(preview), &parsed); err == nil {
				clonedActionData["body_json"] = parsed
			}
		}
	}

	return stepOutcome{
		HTTPStatus:   &httpStatusValue,
		ResponseType: responseType,
		Bytes:        &bytesValue,
		Truncated:    &truncated,
		ActionData:   clonedActionData,
	}
}

func classifyStepFailure(err error, defaultAssertion string) *stepError {
	if err == nil {
		return &stepError{Code: errCodeAssertionFailed, AssertionFailed: defaultAssertion, Message: defaultAssertion}
	}

	var typed *stepError
	if errors.As(err, &typed) {
		if typed.Code == "" {
			typed.Code = errCodeAssertionFailed
		}
		if typed.AssertionFailed == "" {
			typed.AssertionFailed = firstNonBlank(defaultAssertion, "step execution failed")
		}
		if typed.Message == "" {
			typed.Message = typed.AssertionFailed
		}
		return typed
	}

	message := err.Error()
	code := errCodeAssertionFailed
	assertion := firstNonBlank(defaultAssertion, "step execution failed")

	switch {
	case strings.Contains(message, "unsupported expectation"):
		code = errCodeExpectationInvalid
		assertion = "expectation token is valid for action"
	case strings.Contains(message, "unexpected status"):
		code = errCodeHTTPStatusUnexpected
		assertion = "HTTP status matched expected set"
	case strings.Contains(message, "decode") || strings.Contains(message, "unmarshal") || strings.Contains(message, "parse"):
		code = errCodeResponseParseFailed
		assertion = "response payload could be parsed"
	case strings.Contains(strings.ToLower(message), "timeout"):
		code = errCodeTimeout
		assertion = "step completed within timeout"
	case strings.Contains(message, "request failed") || strings.Contains(message, "create request") || strings.Contains(message, "read response"):
		code = errCodeHTTPRequestFailed
		assertion = "HTTP request completed successfully"
	}

	return &stepError{
		Code:            code,
		AssertionFailed: assertion,
		Message:         message,
	}
}

func expectationInvalidFailure(expected, actual string) *stepError {
	return &stepError{
		Code:            errCodeExpectationInvalid,
		AssertionFailed: "expectation token is valid for action",
		Message:         fmt.Sprintf("unsupported expectation: %s", actual),
		Expected:        expected,
		Actual:          actual,
	}
}

func assertionFailure(assertion string, expected, actual any, messageFmt string, args ...any) *stepError {
	message := fmt.Sprintf(messageFmt, args...)
	return &stepError{
		Code:            errCodeAssertionFailed,
		AssertionFailed: assertion,
		Message:         message,
		Expected:        expected,
		Actual:          actual,
	}
}

func responsePreview(body []byte) (string, bool) {
	if len(body) == 0 {
		return "", false
	}

	truncated := len(body) > responsePreviewBytes
	previewBytes := body
	if truncated {
		previewBytes = body[:responsePreviewBytes]
	}

	return strings.TrimSpace(string(previewBytes)), truncated
}

func truncate(data []byte) string {
	if len(data) == 0 {
		return ""
	}

	const limit = 300

	preview := data
	suffix := ""
	if len(data) > limit {
		preview = data[:limit]
		suffix = fmt.Sprintf("...(%d bytes)", len(data))
	}

	return strings.TrimSpace(string(preview)) + suffix
}

func sanitizeActionData(data map[string]any) map[string]any {
	if len(data) == 0 {
		return nil
	}

	result := make(map[string]any, len(data))
	for key, value := range data {
		result[key] = sanitizeSensitiveValue(key, value)
	}
	return result
}

func sanitizeSensitiveValue(key string, value any) any {
	if isSensitiveKey(key) {
		return redactedValue
	}

	switch typed := value.(type) {
	case map[string]any:
		nested := make(map[string]any, len(typed))
		for nestedKey, nestedValue := range typed {
			nested[nestedKey] = sanitizeSensitiveValue(nestedKey, nestedValue)
		}
		return nested
	case []any:
		items := make([]any, len(typed))
		for i, item := range typed {
			items[i] = sanitizeSensitiveValue(key, item)
		}
		return items
	default:
		return typed
	}
}

func isSensitiveKey(key string) bool {
	normalized := strings.ToLower(strings.TrimSpace(key))
	if normalized == "" {
		return false
	}

	for _, token := range sensitiveKeyTokens {
		if strings.Contains(normalized, token) {
			return true
		}
	}
	return false
}

func firstNonBlank(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func cloneMap(value map[string]any) map[string]any {
	if len(value) == 0 {
		return nil
	}

	cloned := make(map[string]any, len(value))
	maps.Copy(cloned, value)
	return cloned
}

func isTimeoutError(err error) bool {
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}

	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func generateMac() string {
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		now := time.Now().UnixNano()
		for i := range b {
			b[i] = byte(now >> (i * 8))
		}
	}
	b[0] = (b[0] | 2) & 0xfe
	return fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X", b[0], b[1], b[2], b[3], b[4], b[5])
}

func generateAccountNumber() string {
	var raw [8]byte
	if _, err := rand.Read(raw[:]); err != nil {
		value := time.Now().UnixNano() % 900000
		return fmt.Sprintf("%d", value+100000)
	}
	value := binary.BigEndian.Uint64(raw[:]) % 900000
	return fmt.Sprintf("%d", value+100000)
}
