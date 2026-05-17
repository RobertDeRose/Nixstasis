package identity

// DeviceIdentity represents the core identity of the device.
type DeviceIdentity struct {
	UUID       string `json:"uuid"`
	MACAddress string `json:"mac_address"`
	IPAddress  string `json:"ip_address"`
	Name       string `json:"name"`
}

// RegistrationSchema returns the minimal public registration schema expected by the server.
func (d DeviceIdentity) RegistrationSchema() map[string]any {
	if d.Name == "" {
		return nil
	}

	return map[string]any{
		"product":    d.Name,
		"type":       "object",
		"properties": map[string]any{},
	}
}
