package plugin

import (
	"time"

	"github.com/sfero-nixstasis/client/internal/identity"
)

// Manifest represents the metadata loaded from manifest.json.
type Manifest struct {
	Name        string   `json:"name"`
	Version     string   `json:"version"`
	UpdateURL   string   `json:"update_url,omitempty"`
	SchemaURL   string   `json:"schema_url,omitempty"`
	Executables []string `json:"executables"`
}

// DeviceStatus represents dynamic status information about the device.
type DeviceStatus struct {
	Identity identity.DeviceIdentity `json:"identity"`
	Uptime   int64                   `json:"uptime_seconds"`
	// TunnelStatus will be added in US3
}

// Report represents the data and metadata for a single plugin execution.
type Report struct {
	Data any       `json:"data"`
	Meta *Manifest `json:"meta,omitempty"`
}

// TelemetryPayload represents the aggregated payload sent to the API.
type TelemetryPayload struct {
	Device  DeviceStatus      `json:"device"`
	Plugins map[string]Report `json:"plugins"`
	Meta    PollMeta          `json:"meta"`
}

// PollMeta contains metadata about the polling operation.
type PollMeta struct {
	Timestamp time.Time `json:"timestamp"`
	Duration  string    `json:"duration"` // ISO 8601 duration or simple string
	Errors    []string  `json:"errors,omitempty"`
}
