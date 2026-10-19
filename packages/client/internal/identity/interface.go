package identity

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"time"
)

const (
	detectInitialDelay = time.Second
	detectMaxDelay     = time.Minute
)

// errLoopbackServer reports a server reached over loopback, which no physical
// interface identifies; retrying cannot fix it.
var errLoopbackServer = errors.New("server is reached over loopback; set identity.interface")

var defaultPorts = map[string]string{"http": "80", "https": "443", "socks5": "1080", "socks5h": "1080"}

// Replaceable in tests.
var (
	listInterfaces  = net.Interfaces
	interfaceAddrs  = func(iface net.Interface) ([]net.Addr, error) { return iface.Addrs() }
	lookupIP        = net.DefaultResolver.LookupIP
	proxyForURL     = func(u *url.URL) (*url.URL, error) { return http.ProxyFromEnvironment(&http.Request{URL: u}) }
	routeLocalIP    = dialRouteLocalIP
	detectInterface = DetectServerInterface
)

// ResolveInterface returns configured when it is set. Otherwise it retries
// DetectServerInterface with exponential backoff until an interface is found
// or ctx ends.
func ResolveInterface(ctx context.Context, configured, serverURL string) (string, error) {
	if configured != "" {
		return configured, nil
	}

	delay := detectInitialDelay
	for {
		name, err := detectInterface(ctx, serverURL)
		if err == nil {
			slog.Info("Detected identity interface", "interface", name)
			return name, nil
		}
		// Any loopback address stops retries, even when another address failed
		// transiently: a server host that resolves to loopback is a configuration
		// problem that waiting cannot fix.
		if errors.Is(err, errLoopbackServer) {
			return "", err
		}
		slog.Warn("No interface routes to the server yet; retrying", "error", err, "delay", delay)

		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return "", fmt.Errorf("detect identity interface: %w", ctx.Err())
		case <-timer.C:
		}
		delay = min(delay*2, detectMaxDelay)
	}
}

// ResolveMAC returns the identity MAC. A configured interface always wins and is
// read directly. Otherwise a MAC saved by an earlier registration is reused, so
// detection runs once per device rather than once per process start; only when
// none is saved does it detect the interface that routes to the server.
func ResolveMAC(ctx context.Context, configured, saved, serverURL string) (string, error) {
	if configured == "" && saved != "" {
		return saved, nil
	}
	name, err := ResolveInterface(ctx, configured, serverURL)
	if err != nil {
		return "", err
	}
	return GetPrimaryMAC(name)
}

// DetectServerInterface returns the interface the kernel routes traffic to the
// server through, or to the HTTPS proxy when one applies. It resolves that host, then connects a UDP socket to each
// address, which selects a route and local address without sending any packets.
// The interface owning that local address must have a MAC address.
func DetectServerInterface(ctx context.Context, serverURL string) (string, error) {
	u, err := url.Parse(serverURL)
	if err != nil || u.Hostname() == "" {
		return "", fmt.Errorf("invalid server URL %q", serverURL)
	}
	// HTTPS requests honor environment proxies, so traffic leaves toward the proxy.
	if u.Scheme == "https" {
		proxy, err := proxyForURL(u)
		if err != nil {
			return "", fmt.Errorf("resolve proxy for server URL: %w", err)
		}
		if proxy != nil {
			u = proxy
		}
	}
	port := u.Port()
	if port == "" {
		port = defaultPorts[u.Scheme]
	}
	if port == "" {
		return "", fmt.Errorf("no default port for scheme %q", u.Scheme)
	}

	ips, err := lookupIP(ctx, "ip", u.Hostname())
	if err != nil {
		return "", fmt.Errorf("resolve host %q: %w", u.Hostname(), err)
	}

	var errs []error
	for _, ip := range ips {
		if ip.IsLoopback() {
			errs = append(errs, errLoopbackServer)
			continue
		}
		local, err := routeLocalIP(ctx, net.JoinHostPort(ip.String(), port))
		if err != nil {
			errs = append(errs, err)
			continue
		}
		name, err := interfaceForIP(local)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		return name, nil
	}
	if len(errs) == 0 {
		return "", fmt.Errorf("server host %q has no addresses", u.Hostname())
	}
	return "", errors.Join(errs...)
}

// dialRouteLocalIP returns the local IP selected for a UDP destination
// without sending packets.
func dialRouteLocalIP(ctx context.Context, address string) (net.IP, error) {
	var d net.Dialer
	conn, err := d.DialContext(ctx, "udp", address)
	if err != nil {
		return nil, err
	}
	defer func() {
		if err := conn.Close(); err != nil {
			slog.Error("failed to close connection", "error", err)
		}
	}()
	addr, ok := conn.LocalAddr().(*net.UDPAddr)
	if !ok {
		return nil, errors.New("failed to cast local address to UDPAddr")
	}
	return addr.IP, nil
}

// interfaceForIP returns the name of the interface owning ip, or an error
// if no interface owns it or the matching interface has no MAC address.
func interfaceForIP(ip net.IP) (string, error) {
	interfaces, err := listInterfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range interfaces {
		addrs, err := interfaceAddrs(iface)
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok || !ipNet.IP.Equal(ip) {
				continue
			}
			if len(iface.HardwareAddr) == 0 {
				return "", fmt.Errorf("identity interface %q has no MAC address", iface.Name)
			}
			return iface.Name, nil
		}
	}
	return "", fmt.Errorf("no interface owns route address %s", ip)
}
