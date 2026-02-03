// Package transport handles network communication with the Nixstasis API.
package transport

import (
	"bytes"
	"context"
	json "encoding/json/v2"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"time"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/frp"
	"github.com/sfero-nixstasis/client/internal/identity"
	"github.com/sfero-nixstasis/client/internal/plugin"
)

// Client handles API requests.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a new Client instance.
func NewClient(cfg config.APIConfig) *Client {
	return &Client{
		baseURL: cfg.URL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *Client) doJSON(ctx context.Context, method, url string, reqBody, respBody any, expectedStatuses ...int) error {
	var bodyReader io.Reader
	if reqBody != nil {
		b, err := json.Marshal(reqBody)
		if err != nil {
			return fmt.Errorf("failed to marshal request: %w", err)
		}
		bodyReader = bytes.NewBuffer(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, url, bodyReader)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	if reqBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	// Check expected statuses
	ok := slices.Contains(expectedStatuses, resp.StatusCode)
	if !ok {
		return fmt.Errorf("API returned non-success status: %d", resp.StatusCode)
	}

	if respBody == nil {
		return nil
	}

	if err := json.UnmarshalRead(resp.Body, respBody); err != nil {
		if errors.Is(err, io.EOF) {
			// Empty body is allowed; caller can inspect zero-value respBody
			return nil
		}
		return fmt.Errorf("failed to decode response: %w", err)
	}

	return nil
}

// RegisterDevice registers the device with the Nixstasis API.
// It returns the assigned UUID or an error.
func (c *Client) RegisterDevice(ctx context.Context, id identity.DeviceIdentity) (string, error) {
	url := fmt.Sprintf("%s/device/register", c.baseURL)

	var response struct {
		UUID string `json:"uuid"`
	}
	if err := c.doJSON(ctx, http.MethodPost, url, id, &response, http.StatusOK); err != nil {
		return "", err
	}

	if response.UUID == "" {
		return "", fmt.Errorf("API returned empty UUID")
	}

	return response.UUID, nil
}

// PollRequest represents the body of the poll request.
type PollRequest struct {
	Telemetry        plugin.TelemetryPayload `json:"telemetry"`
	ConnectionStatus frp.ConnectionStatus    `json:"connection_status"`
	// SchemaURLs to be added in Refinement
}

// PollResponse represents the response from the poll endpoint.
type PollResponse struct {
	RemoteAccessRequested bool `json:"remote_access_requested"`
}

// Poll sends the collected telemetry payload to the Nixstasis API.
func (c *Client) Poll(ctx context.Context, uuid string, payload plugin.TelemetryPayload, frpStatus frp.ConnectionStatus) (*PollResponse, error) {
	url := fmt.Sprintf("%s/device/%s/poll", c.baseURL, uuid)

	reqBody := PollRequest{
		Telemetry:        payload,
		ConnectionStatus: frpStatus,
	}

	var pollResp PollResponse
	if err := c.doJSON(ctx, http.MethodPost, url, reqBody, &pollResp, http.StatusOK, http.StatusAccepted); err != nil {
		return nil, err
	}

	return &pollResp, nil
}
