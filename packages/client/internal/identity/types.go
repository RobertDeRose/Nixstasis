package identity

// DeviceIdentity represents the core identity of the device.
type DeviceIdentity struct {
	UUID       string `json:"uuid"`
	MACAddress string `json:"mac_address"`
	IPAddress  string `json:"ip_address"`
	Name       string `json:"name"`
}
