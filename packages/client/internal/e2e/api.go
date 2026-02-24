package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type apiClient struct {
	baseURL    string
	httpClient *http.Client
}

type runCreateRequest struct {
	SuiteID          string         `json:"suite_id"`
	JourneyIDs       []string       `json:"journey_ids,omitempty"`
	EnvironmentLabel string         `json:"environment_label"`
	TriggerSource    string         `json:"trigger_source"`
	IdempotencyKey   string         `json:"idempotency_key,omitempty"`
	Metadata         map[string]any `json:"metadata,omitempty"`
	ProtocolVersion  string         `json:"-"`
}

type runData struct {
	ID               string   `json:"id"`
	SuiteID          string   `json:"suite_id"`
	JourneyIDs       []string `json:"journey_ids"`
	EnvironmentLabel string   `json:"environment_label"`
	TriggerSource    string   `json:"trigger_source"`
	ProtocolVersion  string   `json:"protocol_version"`
	Status           string   `json:"status"`
}

type runResponse struct {
	Data runData `json:"data"`
}

type resultPayload struct {
	JourneyID     string `json:"journey_id"`
	Status        string `json:"status"`
	FailureStep   string `json:"failure_step,omitempty"`
	FailureReason string `json:"failure_reason,omitempty"`
	LogRef        string `json:"log_ref,omitempty"`
	DurationMs    int64  `json:"duration_ms,omitempty"`
}

type resultsRequest struct {
	Results []resultPayload `json:"results"`
}

func newAPIClient(baseURL string) *apiClient {
	return &apiClient{
		baseURL:    strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *apiClient) createRun(ctx context.Context, req runCreateRequest) (runData, error) {
	url := fmt.Sprintf("%s/e2e/runs", c.baseURL)
	body, err := json.Marshal(req)
	if err != nil {
		return runData{}, fmt.Errorf("marshal request: %w", err)
	}

	headers := map[string]string{
		"X-E2E-Protocol-Version": req.ProtocolVersion,
	}

	respBody, err := c.doJSON(ctx, http.MethodPost, url, body, headers, http.StatusCreated)
	if err != nil {
		return runData{}, err
	}

	var response runResponse
	if err := json.Unmarshal(respBody, &response); err != nil {
		return runData{}, fmt.Errorf("decode response: %w", err)
	}

	if response.Data.ID == "" {
		return runData{}, fmt.Errorf("API returned empty run id")
	}

	return response.Data, nil
}

func (c *apiClient) submitResults(ctx context.Context, runID string, results []resultPayload) error {
	url := fmt.Sprintf("%s/e2e/runs/%s/results", c.baseURL, runID)
	payload := resultsRequest{Results: results}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal results: %w", err)
	}

	_, err = c.doJSON(ctx, http.MethodPost, url, body, nil, http.StatusOK, http.StatusAccepted)
	return err
}

func (c *apiClient) doJSON(ctx context.Context, method, url string, payload []byte, headers map[string]string, expectedStatuses ...int) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, bytes.NewBuffer(payload))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	for key, value := range headers {
		if strings.TrimSpace(key) != "" && strings.TrimSpace(value) != "" {
			req.Header.Set(key, value)
		}
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	for _, status := range expectedStatuses {
		if resp.StatusCode == status {
			data, err := ioReadAll(resp)
			if err != nil {
				return nil, err
			}
			return data, nil
		}
	}

	data, err := ioReadAll(resp)
	if err != nil {
		return nil, err
	}
	return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(data))
}

func ioReadAll(resp *http.Response) ([]byte, error) {
	buf := new(bytes.Buffer)
	if _, err := buf.ReadFrom(resp.Body); err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	return buf.Bytes(), nil
}
