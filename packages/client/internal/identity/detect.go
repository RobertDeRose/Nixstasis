// Package identity handles device identity detection and management.
package identity

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"strings"
	"time"
)

// GetPrimaryMAC returns the MAC address of the primary network interface (e.g. eth0).
// It prioritizes "eth0" but falls back to the first non-loopback, non-virtual interface found.
func GetPrimaryMAC() (string, error) {
	interfaces, err := net.Interfaces()
	fallback := ""

	if err != nil {
		return "", err
	}

	// 1. Try to find "eth0" specifically (per spec)
	for _, iface := range interfaces {
		if iface.Name == "eth0" {
			if mac := iface.HardwareAddr.String(); mac != "" {
				return mac, nil
			}
		}
		if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
			continue
		}
		// 2. Fallback: Find first valid interface (up, not loopback, has MAC)
		if fallback == "" && len(iface.HardwareAddr) > 0 {
			fallback = iface.HardwareAddr.String()
		}
	}

	if fallback != "" {
		return fallback, nil
	}

	return "", errors.New("no valid MAC address found")
}

// GetPrimaryIP returns the IPv4 address of the primary network interface.
func GetPrimaryIP(ctx context.Context) (string, error) {
	// We can reuse the interface logic or just dial out to see preferred outbound IP
	// Dialing UDP is a common trick to find the outbound IP without sending packets.
	// Use DialContext for compliance
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	var d net.Dialer
	conn, err := d.DialContext(ctx, "udp", "8.8.8.8:80")
	if err != nil {
		// Fallback to interface iteration if no route to internet
		return getIPFromInterfaces()
	}
	defer func() {
		if err := conn.Close(); err != nil {
			slog.Error("failed to close connection", "error", err)
		}
	}()
	localAddr, ok := conn.LocalAddr().(*net.UDPAddr)
	if !ok {
		return "", errors.New("failed to cast local address to UDPAddr")
	}
	return localAddr.IP.String(), nil
}

func getIPFromInterfaces() (string, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ip = ip.To4()
			if ip == nil {
				continue // not an ipv4 address
			}
			return ip.String(), nil
		}
	}
	return "", errors.New("no valid IP address found")
}

// GenerateDeviceName creates the atom-<mac> name.
func GenerateDeviceName(mac string) string {
	stripped := strings.ReplaceAll(mac, ":", "")
	return "atom-" + strings.ToLower(stripped)
}
