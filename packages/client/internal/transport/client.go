// Package transport handles network communication with the Nixstasis API.
package transport

import (
	"bytes"
	"context"
	"encoding/json/v2"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"time"

	"github.com/sfero-nixstasis/client/internal/config"
	"github.com/sfero-nixstasis/client/internal/frp"
	"github.com/sfero-nixstasis/client/internal/identity"
	"github.com/sfero-nixstasis/client/internal/telemetry"
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
	url := fmt.Sprintf("%s/api/v1/devices/register", c.baseURL)
	reqBody := map[string]any{
		"mac_address": id.MACAddress,
	}

	if id.Name != "" {
		reqBody["product_name"] = id.Name
	}

	if id.IPAddress != "" || id.UUID != "" {
		metadata := map[string]any{}
		if id.IPAddress != "" {
			metadata["ip_address"] = id.IPAddress
		}
		if id.UUID != "" {
			metadata["client_uuid"] = id.UUID
		}
		reqBody["metadata"] = metadata
	}

	var response struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, url, reqBody, &response, http.StatusCreated); err != nil {
		return "", err
	}

	if response.Data.ID == "" {
		return "", fmt.Errorf("API returned empty device id")
	}

	return response.Data.ID, nil
}

// PollRequest represents the body of the poll request.
type PollRequest struct {
	Telemetry        telemetry.Payload    `json:"telemetry"`
	ConnectionStatus frp.ConnectionStatus `json:"connection_status"`
	// SchemaURLs to be added in Refinement
}

// CommandStatus represents the outcome of a server-issued command.
type CommandStatus string

const (
	// CommandStatusOK indicates a successful command execution.
	CommandStatusOK CommandStatus = "OK"
	// CommandStatusFailed indicates a failed command execution.
	CommandStatusFailed CommandStatus = "FAILED"
)

// CommandRequest represents a server-issued command returned with the poll response.
type CommandRequest struct {
	CommandID  string          `json:"command_id"`
	Type       string          `json:"type"`
	Args       []string        `json:"args,omitempty"`
	Payload    *CommandPayload `json:"payload,omitempty"`
	PayloadRef string          `json:"payload_ref,omitempty"`
}

// CommandPayload describes the payload attached to a command.
type CommandPayload struct {
	ContentType string `json:"content_type"`
	Name        string `json:"name"`
	Data        string `json:"data"`
}

// CommandResult represents the client response for a single command.
type CommandResult struct {
	CommandID string        `json:"command_id"`
	Status    CommandStatus `json:"status"`
	Output    any           `json:"output,omitempty"`
	Error     string        `json:"error,omitempty"`
}

// PollResponse represents the response from the poll endpoint.
type PollResponse struct {
	RemoteAccessRequested bool             `json:"remote_access_requested"`
	Commands              []CommandRequest `json:"commands,omitempty"`
}

// Poll sends the collected telemetry payload to the Nixstasis API.
func (c *Client) Poll(ctx context.Context, uuid string, payload telemetry.Payload, frpStatus frp.ConnectionStatus) (*PollResponse, error) {
	url := fmt.Sprintf("%s/api/v1/devices/%s/heartbeat", c.baseURL, uuid)

	reqBody := PollRequest{
		Telemetry:        payload,
		ConnectionStatus: frpStatus,
	}

	var response struct {
		Data PollResponse `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, url, reqBody, &response, http.StatusOK, http.StatusAccepted); err != nil {
		return nil, err
	}

	return &response.Data, nil
}

// CommandResultsRequest represents the body sent when returning command results.
type CommandResultsRequest struct {
	Results []CommandResult `json:"results"`
}

// SendCommandResults posts aggregated command results to the API.
func (c *Client) SendCommandResults(ctx context.Context, uuid string, results []CommandResult) error {
	url := fmt.Sprintf("%s/api/v1/devices/%s/command_results", c.baseURL, uuid)
	reqBody := CommandResultsRequest{Results: results}

	return c.doJSON(ctx, http.MethodPost, url, reqBody, nil, http.StatusOK, http.StatusAccepted)
}

// FetchCommandPayload retrieves a payload by reference.
func (c *Client) FetchCommandPayload(ctx context.Context, uuid, ref string) (*CommandPayload, error) {
	url := fmt.Sprintf("%s/api/v1/devices/%s/command_payloads/%s", c.baseURL, uuid, ref)

	var payload CommandPayload
	if err := c.doJSON(ctx, http.MethodGet, url, nil, &payload, http.StatusOK); err != nil {
		return nil, err
	}

	return &payload, nil
}
