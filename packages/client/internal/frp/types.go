package frp

import "time"

// ConnectionStatus represents the state of the remote access tunnel.
type ConnectionStatus struct {
	Active           bool      `json:"active"`
	ConnectionString string    `json:"connection_string"`
	PID              int       `json:"pid"`
	StartTime        time.Time `json:"start_time"`
}
