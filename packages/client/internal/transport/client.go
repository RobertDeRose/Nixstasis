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
	"net/url"
	"regexp"
	"slices"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
)

// ErrDevicePendingApproval indicates registration succeeded but no runtime token has been issued yet.
var ErrDevicePendingApproval = errors.New("device pending approval")

// Client handles API requests.
type Client struct {
	baseURL    string
	httpClient *http.Client
	apiKey     string
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

// SetAPIKey configures the per-device API key used for runtime endpoints.
// It is called once during startup after registration completes, before the
// poll loop begins.  The single-writer lifecycle means no mutex is needed.
func (c *Client) SetAPIKey(apiKey string) {
	c.apiKey = apiKey
}

func (c *Client) doJSON(ctx context.Context, method, endpoint string, reqBody, respBody any, expectedStatuses ...int) error {
	var bodyReader io.Reader
	if reqBody != nil {
		b, err := json.Marshal(reqBody)
		if err != nil {
			return fmt.Errorf("failed to marshal request: %w", err)
		}
		bodyReader = bytes.NewBuffer(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, endpoint, bodyReader)
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

func (c *Client) deviceURL(path string) string {
	u, err := url.Parse(c.baseURL + path)
	if err != nil || c.apiKey == "" {
		return c.baseURL + path
	}
	q := u.Query()
	q.Set("api_key", c.apiKey)
	u.RawQuery = q.Encode()
	return u.String()
}

// DeviceCredentials are issued once the server has approved a device.
type DeviceCredentials struct {
	UUID  string
	Token string
}

// RegisterDevice registers the device with the Nixstasis API.
// It returns the assigned UUID or an error.
func (c *Client) RegisterDevice(ctx context.Context, id identity.DeviceIdentity) (string, error) {
	credentials, err := c.RegisterDeviceCredentials(ctx, id)
	if err != nil && !errors.Is(err, ErrDevicePendingApproval) {
		return "", err
	}
	return credentials.UUID, nil
}

// RegisterDeviceCredentials registers the device and returns approved runtime credentials when available.
func (c *Client) RegisterDeviceCredentials(ctx context.Context, id identity.DeviceIdentity) (DeviceCredentials, error) {
	endpoint := fmt.Sprintf("%s/api/v1/devices/register", c.baseURL)
	reqBody := map[string]any{
		"mac_address": id.MACAddress,
	}

	if id.Name != "" {
		reqBody["product_name"] = id.Name
		reqBody["schema_definition"] = id.RegistrationSchema()
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
			ID       string `json:"id"`
			APIToken string `json:"api_token"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, endpoint, reqBody, &response, http.StatusCreated); err != nil {
		return DeviceCredentials{}, err
	}

	if response.Data.ID == "" {
		return DeviceCredentials{}, fmt.Errorf("API returned empty device id")
	}
	if response.Data.APIToken == "" {
		return DeviceCredentials{UUID: response.Data.ID}, ErrDevicePendingApproval
	}

	return DeviceCredentials{UUID: response.Data.ID, Token: response.Data.APIToken}, nil
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
	PublicKey  string          `json:"public_key,omitempty"`
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
	endpoint := c.deviceURL(fmt.Sprintf("/api/v1/devices/%s/heartbeat", uuid))

	reqBody := PollRequest{
		Telemetry:        payload,
		ConnectionStatus: frpStatus,
	}

	var response struct {
		Data PollResponse `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, endpoint, reqBody, &response, http.StatusOK, http.StatusAccepted); err != nil {
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
	endpoint := c.deviceURL(fmt.Sprintf("/api/v1/devices/%s/command_results", uuid))
	reqBody := CommandResultsRequest{Results: results}

	return c.doJSON(ctx, http.MethodPost, endpoint, reqBody, nil, http.StatusOK, http.StatusAccepted)
}

var payloadRefPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]*$`)

// ValidatePayloadRef checks that a payload reference is safe for URL interpolation.
func ValidatePayloadRef(ref string) error {
	if ref == "" {
		return fmt.Errorf("empty payload ref")
	}
	if !payloadRefPattern.MatchString(ref) {
		return fmt.Errorf("invalid payload ref %q", ref)
	}
	return nil
}

// FetchCommandPayload retrieves a payload by reference.
func (c *Client) FetchCommandPayload(ctx context.Context, uuid, ref string) (*CommandPayload, error) {
	endpoint := c.deviceURL(fmt.Sprintf("/api/v1/devices/%s/command_payloads/%s", uuid, ref))

	var payload CommandPayload
	if err := c.doJSON(ctx, http.MethodGet, endpoint, nil, &payload, http.StatusOK); err != nil {
		return nil, err
	}

	return &payload, nil
}
