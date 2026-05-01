// Package telemetry contains shared telemetry payload types.
package telemetry

import (
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
)

// DeviceStatus represents dynamic status information about the device.
type DeviceStatus struct {
	Identity identity.DeviceIdentity `json:"identity"`
	Uptime   int64                   `json:"uptime_seconds"`
}

// Report represents the data and metadata for a single script execution.
type Report struct {
	Data any `json:"data"`
}

// Payload represents the aggregated telemetry payload sent to the API.
type Payload struct {
	Device  DeviceStatus      `json:"device"`
	Scripts map[string]Report `json:"scripts"`
	Meta    PollMeta          `json:"meta"`
}

// PollMeta contains metadata about the polling operation.
type PollMeta struct {
	Timestamp time.Time `json:"timestamp"`
	Duration  string    `json:"duration"`
	Errors    []string  `json:"errors,omitempty"`
}
