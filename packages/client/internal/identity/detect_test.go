package identity

import (
	"context"
	"errors"
	"net"
	"net/url"
	"testing"
	"testing/synctest"
	"time"
)

func TestGetPrimaryIP(t *testing.T) {
	ip, err := GetPrimaryIP(context.Background())
	if err == nil {
		t.Logf("Detected IP: %s", ip)
	} else {
		t.Logf("Could not detect IP: %v", err)
	}

	if err == nil && len(ip) == 0 {
		t.Error("Returned nil error but empty IP address")
	}
}

// stubInterfaces replaces interface enumeration and address lookup with
// fixtures and restores both functions when the test ends.
func stubInterfaces(t *testing.T, interfaces []net.Interface, addrs map[string][]net.Addr) {
	t.Helper()
	originalList, originalAddrs := listInterfaces, interfaceAddrs
	listInterfaces = func() ([]net.Interface, error) { return interfaces, nil }
	interfaceAddrs = func(iface net.Interface) ([]net.Addr, error) { return addrs[iface.Name], nil }
	t.Cleanup(func() { listInterfaces, interfaceAddrs = originalList, originalAddrs })
}

var (
	lanMAC = net.HardwareAddr{0x02, 0, 0, 0, 0, 0x01}
	wanMAC = net.HardwareAddr{0x02, 0, 0, 0, 0, 0x02}
	// lan enumerates first and is up; wan is down, as when its link has not come up yet.
	testInterfaces = []net.Interface{
		{Name: "lo", Flags: net.FlagUp | net.FlagLoopback},
		{Name: "eth0", Flags: net.FlagUp},
		{Name: "lan", Flags: net.FlagUp, HardwareAddr: lanMAC},
		{Name: "wan", HardwareAddr: wanMAC},
	}
)

// TestGetPrimaryMACUsesOnlyTheNamedInterface verifies that an explicit
// interface works even when down and invalid names never trigger fallback.
func TestGetPrimaryMACUsesOnlyTheNamedInterface(t *testing.T) {
	stubInterfaces(t, testInterfaces, nil)

	mac, err := GetPrimaryMAC("wan")
	if err != nil || mac != wanMAC.String() {
		t.Fatalf("GetPrimaryMAC(wan) = %q, %v; want %q", mac, err, wanMAC)
	}

	for _, name := range []string{"", "eth0", "eth1"} {
		if mac, err := GetPrimaryMAC(name); err == nil {
			t.Fatalf("GetPrimaryMAC(%q) = %q; want error without fallback", name, mac)
		}
	}
}

// stubRoutes replaces DNS, route lookup, and proxy selection with fixtures,
// records attempted destinations, and restores the originals after the test.
func stubRoutes(t *testing.T, hostIPs []net.IP, routes map[string]net.IP) *[]string {
	t.Helper()
	var dialed []string
	originalLookup, originalRoute, originalProxy := lookupIP, routeLocalIP, proxyForURL
	proxyForURL = func(*url.URL) (*url.URL, error) { return nil, nil }
	lookupIP = func(context.Context, string, string) ([]net.IP, error) { return hostIPs, nil }
	routeLocalIP = func(_ context.Context, address string) (net.IP, error) {
		dialed = append(dialed, address)
		if local, ok := routes[address]; ok {
			return local, nil
		}
		return nil, errors.New("network is unreachable")
	}
	t.Cleanup(func() { lookupIP, routeLocalIP, proxyForURL = originalLookup, originalRoute, originalProxy })
	return &dialed
}

var routedAddrs = map[string][]net.Addr{
	"lan": {&net.IPNet{IP: net.IPv4(10, 0, 0, 2), Mask: net.CIDRMask(24, 32)}},
	"wan": {&net.IPNet{IP: net.IPv4(203, 0, 113, 7), Mask: net.CIDRMask(24, 32)}},
}

// TestDetectServerInterfaceFollowsTheServerRoute verifies that an intranet
// server selects its LAN route rather than the default WAN route.
func TestDetectServerInterfaceFollowsTheServerRoute(t *testing.T) {
	stubInterfaces(t, testInterfaces, routedAddrs)
	// The default route uses wan, but this server sits on the lan intranet.
	dialed := stubRoutes(t, []net.IP{net.IPv4(10, 0, 0, 50)}, map[string]net.IP{
		"10.0.0.50:8443": net.IPv4(10, 0, 0, 2),
	})

	name, err := DetectServerInterface(context.Background(), "https://nixstasis.internal:8443")
	if err != nil || name != "lan" {
		t.Fatalf("DetectServerInterface() = %q, %v; want lan", name, err)
	}
	if len(*dialed) != 1 || (*dialed)[0] != "10.0.0.50:8443" {
		t.Fatalf("route lookups = %v; want only the server address", *dialed)
	}
}

// TestDetectServerInterfaceTriesEachServerAddress verifies that detection
// falls back to a reachable IPv4 route when the IPv6 route is unavailable.
func TestDetectServerInterfaceTriesEachServerAddress(t *testing.T) {
	stubInterfaces(t, testInterfaces, routedAddrs)
	stubRoutes(t, []net.IP{net.ParseIP("2001:db8::10"), net.IPv4(198, 51, 100, 10)}, map[string]net.IP{
		"198.51.100.10:443": net.IPv4(203, 0, 113, 7),
	})

	name, err := DetectServerInterface(context.Background(), "https://nixstasis.example.com")
	if err != nil || name != "wan" {
		t.Fatalf("DetectServerInterface() = %q, %v; want wan", name, err)
	}
}

// TestResolveInterfaceRejectsLoopbackServerWithoutRetry verifies that a
// loopback server causes an immediate error instead of detection retries.
func TestResolveInterfaceRejectsLoopbackServerWithoutRetry(t *testing.T) {
	stubInterfaces(t, testInterfaces, routedAddrs)
	stubRoutes(t, []net.IP{net.IPv4(127, 0, 0, 1)}, nil)

	if _, err := ResolveInterface(context.Background(), "", "http://localhost:4000"); !errors.Is(err, errLoopbackServer) {
		t.Fatalf("ResolveInterface() error = %v; want loopback error", err)
	}
}

// TestResolveInterfacePrefersConfiguredName verifies that a configured
// interface bypasses route detection.
func TestResolveInterfacePrefersConfiguredName(t *testing.T) {
	originalDetect := detectInterface
	detectInterface = func(context.Context, string) (string, error) {
		t.Fatal("detection must not run when an interface is configured")
		return "", nil
	}
	t.Cleanup(func() { detectInterface = originalDetect })

	name, err := ResolveInterface(context.Background(), "wan", "https://nixstasis.example.com")
	if err != nil || name != "wan" {
		t.Fatalf("ResolveInterface(wan) = %q, %v", name, err)
	}
}

// TestResolveInterfaceRetriesUntilDetected verifies that transient failures
// retry after one, two, and four seconds before detection succeeds.
func TestResolveInterfaceRetriesUntilDetected(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		attempts := 0
		originalDetect := detectInterface
		detectInterface = func(context.Context, string) (string, error) {
			attempts++
			if attempts < 4 {
				return "", errors.New("no route")
			}
			return "wan", nil
		}
		t.Cleanup(func() { detectInterface = originalDetect })

		start := time.Now()
		name, err := ResolveInterface(context.Background(), "", "https://nixstasis.example.com")
		if err != nil || name != "wan" {
			t.Fatalf("ResolveInterface() = %q, %v; want wan", name, err)
		}
		// Three failures wait 1s, 2s, then 4s.
		if elapsed := time.Since(start); elapsed != 7*time.Second {
			t.Fatalf("backoff waited %v; want 7s", elapsed)
		}
	})
}

// TestResolveInterfaceStopsWhenContextEnds verifies that retries stop with
// the context deadline error when no route becomes available.
func TestResolveInterfaceStopsWhenContextEnds(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		originalDetect := detectInterface
		detectInterface = func(context.Context, string) (string, error) { return "", errors.New("no route") }
		t.Cleanup(func() { detectInterface = originalDetect })

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()
		if _, err := ResolveInterface(ctx, "", "https://nixstasis.example.com"); !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("ResolveInterface() error = %v; want deadline exceeded", err)
		}
	})
}

// TestResolveMACPrefersConfiguredThenSavedMAC verifies that a configured
// interface takes precedence over a saved MAC, which takes precedence over detection.
func TestResolveMACPrefersConfiguredThenSavedMAC(t *testing.T) {
	stubInterfaces(t, testInterfaces, routedAddrs)
	originalDetect := detectInterface
	detectInterface = func(context.Context, string) (string, error) { return "lan", nil }
	t.Cleanup(func() { detectInterface = originalDetect })
	const saved = "02:00:00:00:00:99"

	cases := []struct{ configured, saved, want string }{
		{"wan", saved, wanMAC.String()}, // an explicit interface overrides the saved MAC
		{"", saved, saved},              // a saved MAC skips detection
		{"", "", lanMAC.String()},       // otherwise detect
	}
	for _, c := range cases {
		mac, err := ResolveMAC(context.Background(), c.configured, c.saved, "https://nixstasis.example.com")
		if err != nil || mac != c.want {
			t.Fatalf("ResolveMAC(%q, %q) = %q, %v; want %q", c.configured, c.saved, mac, err, c.want)
		}
	}
}

// TestDetectServerInterfaceRoutesToTheHTTPSProxy verifies that detection
// resolves and routes to the proxy even when the origin cannot be resolved.
func TestDetectServerInterfaceRoutesToTheHTTPSProxy(t *testing.T) {
	stubInterfaces(t, testInterfaces, routedAddrs)
	originalProxy := proxyForURL
	proxyForURL = func(*url.URL) (*url.URL, error) { return url.Parse("http://proxy.internal:3128") }
	t.Cleanup(func() { proxyForURL = originalProxy })
	// Only the proxy resolves; the device cannot resolve the origin itself.
	originalLookup := lookupIP
	lookupIP = func(_ context.Context, _ string, host string) ([]net.IP, error) {
		if host != "proxy.internal" {
			return nil, errors.New("no such host")
		}
		return []net.IP{net.IPv4(10, 0, 0, 3)}, nil
	}
	t.Cleanup(func() { lookupIP = originalLookup })
	originalRoute := routeLocalIP
	routeLocalIP = func(_ context.Context, address string) (net.IP, error) {
		if address != "10.0.0.3:3128" {
			t.Fatalf("route lookup to %s; want the proxy", address)
		}
		return net.IPv4(10, 0, 0, 2), nil
	}
	t.Cleanup(func() { routeLocalIP = originalRoute })

	name, err := DetectServerInterface(context.Background(), "https://nixstasis.example.com")
	if err != nil || name != "lan" {
		t.Fatalf("DetectServerInterface() = %q, %v; want lan", name, err)
	}
}
