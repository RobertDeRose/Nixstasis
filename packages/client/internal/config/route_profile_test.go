package config

import (
	"strings"
	"testing"
)

func TestResolveRouteProfileDefaultsWhenServerSendsOnlyAToken(t *testing.T) {
	cfg := FRPConfig{
		ServerAddr:    "frps.example",
		ServerPort:    7000,
		WebServerAddr: "127.0.0.1",
		WebServerPort: 7400,
		HTTPLocalAddr: "127.0.0.1:443",
		SSHLocalPort:  22,
	}
	NormalizeFRPConfig(&cfg)

	profile, selection, err := ResolveRouteProfile(cfg, nil)
	if err != nil {
		t.Fatalf("ResolveRouteProfile() error = %v", err)
	}
	if selection.Name != DefaultFRPProfileName || selection.Version != DefaultFRPProfileVersion {
		t.Fatalf("selection = %+v", selection)
	}
	if len(profile.Routes) != 3 {
		t.Fatalf("default routes = %d, want 3", len(profile.Routes))
	}
}

func TestResolveRouteProfileProvidesAtomixOSBootstrapHostRewrite(t *testing.T) {
	cfg := FRPConfig{}

	profile, selection, err := ResolveRouteProfile(cfg, &RouteProfileSelection{
		Name:    AtomixOSBootstrapProfileName,
		Version: DefaultFRPProfileVersion,
	})
	if err != nil {
		t.Fatalf("ResolveRouteProfile() error = %v", err)
	}
	if selection.Name != AtomixOSBootstrapProfileName || selection.Version != DefaultFRPProfileVersion {
		t.Fatalf("selection = %+v", selection)
	}
	if len(profile.Routes) != 1 {
		t.Fatalf("bootstrap routes = %d, want 1", len(profile.Routes))
	}
	if profile.Routes[0].HostHeaderRewrite == nil || *profile.Routes[0].HostHeaderRewrite != "localhost" {
		t.Fatalf("bootstrap host rewrite = %v, want localhost", profile.Routes[0].HostHeaderRewrite)
	}
}

func TestResolveRouteProfileAcceptsNamedVersionedProfile(t *testing.T) {
	cfg := FRPConfig{
		AllowedPluginKinds: []string{"http2https"},
		Profiles: map[string]FRPRouteProfile{
			"bootstrap": {
				Version: 1,
				Routes: []FRPRoute{{
					Name:      "provisioning",
					Kind:      RouteKindHTTP,
					LocalAddr: "127.0.0.1:8080",
				}},
			},
		},
	}

	profile, selection, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "bootstrap", Version: 1})
	if err != nil {
		t.Fatalf("ResolveRouteProfile() error = %v", err)
	}
	if selection.Name != "bootstrap" || selection.Version != 1 {
		t.Fatalf("selection = %+v", selection)
	}
	if len(profile.Routes) != 1 || profile.Routes[0].LocalAddr != "127.0.0.1:8080" {
		t.Fatalf("profile = %+v", profile)
	}
}

func TestResolveRouteProfileRejectsUnknownOrMismatchedProfiles(t *testing.T) {
	cfg := FRPConfig{
		Profiles: map[string]FRPRouteProfile{
			"bootstrap": {Version: 2, Routes: []FRPRoute{{Name: "api", Kind: RouteKindHTTP, LocalAddr: "127.0.0.1:8080"}}},
		},
	}

	tests := []struct {
		name      string
		selection RouteProfileSelection
		want      string
	}{
		{"unknown", RouteProfileSelection{Name: "missing", Version: 1}, "unknown"},
		{"version mismatch", RouteProfileSelection{Name: "bootstrap", Version: 1}, "version"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, _, err := ResolveRouteProfile(cfg, &tt.selection)
			if err == nil || !containsError(err, tt.want) {
				t.Fatalf("error = %v, want %q", err, tt.want)
			}
		})
	}
}

func TestResolveRouteProfileRejectsUnknownAllowedPluginKinds(t *testing.T) {
	cfg := FRPConfig{
		AllowedPluginKinds: []string{"arbitrary-plugin"},
		Profiles: map[string]FRPRouteProfile{
			"test": {Version: 1, Routes: []FRPRoute{{Name: "api", Kind: RouteKindHTTP, LocalAddr: "127.0.0.1:8080"}}},
		},
	}

	_, _, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "test", Version: 1})
	if err == nil || !strings.Contains(err.Error(), "not supported") {
		t.Fatalf("error = %v, want unsupported plugin error", err)
	}
}

func TestResolveRouteProfileRejectsUnsafeTargetsAndPlugins(t *testing.T) {
	tests := []struct {
		name    string
		profile FRPRouteProfile
		want    string
	}{
		{
			name:    "non-loopback target",
			profile: FRPRouteProfile{Version: 1, Routes: []FRPRoute{{Name: "api", Kind: RouteKindHTTP, LocalAddr: "10.0.0.4:8080"}}},
			want:    "loopback",
		},
		{
			name:    "unsupported route kind",
			profile: FRPRouteProfile{Version: 1, Routes: []FRPRoute{{Name: "web", Kind: "arbitrary", LocalAddr: "127.0.0.1:443"}}},
			want:    "not supported",
		},
		{
			name: "host rewrite on tcp mux",
			profile: FRPRouteProfile{Version: 1, Routes: []FRPRoute{{
				Name:              "ssh",
				Kind:              RouteKindTCPMux,
				LocalPort:         22,
				HostHeaderRewrite: new("localhost"),
			}}},
			want: "only supported for plain HTTP",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := FRPConfig{Profiles: map[string]FRPRouteProfile{"test": tt.profile}}
			_, _, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "test", Version: 1})
			if err == nil || !containsError(err, tt.want) {
				t.Fatalf("error = %v, want %q", err, tt.want)
			}
		})
	}
}

func TestResolveRouteProfileRejectsUnsafeRouteNames(t *testing.T) {
	for _, routeName := range []string{"api_gateway", "api-", "api."} {
		t.Run(routeName, func(t *testing.T) {
			cfg := FRPConfig{Profiles: map[string]FRPRouteProfile{
				"test": {
					Version: 1,
					Routes:  []FRPRoute{{Name: routeName, Kind: RouteKindHTTP, LocalAddr: "127.0.0.1:8080"}},
				},
			}}

			_, _, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "test", Version: 1})
			if err == nil || !strings.Contains(err.Error(), "route name") {
				t.Fatalf("error = %v, want unsafe route-name error", err)
			}
		})
	}
}

func TestResolveRouteProfileRejectsUnsafeHostHeaderRewrites(t *testing.T) {
	for _, value := range []string{"", "example.com", "192.168.1.2", "localhost\ninternal"} {
		t.Run(value, func(t *testing.T) {
			cfg := FRPConfig{Profiles: map[string]FRPRouteProfile{
				"test": {
					Version: 1,
					Routes: []FRPRoute{{
						Name:              "api",
						Kind:              RouteKindHTTP,
						LocalAddr:         "127.0.0.1:8080",
						HostHeaderRewrite: new(value),
					}},
				},
			}}

			_, _, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "test", Version: 1})
			if err == nil || !strings.Contains(err.Error(), "host header rewrite") {
				t.Fatalf("error = %v, want host-header-rewrite validation", err)
			}
		})
	}
}

func TestResolveRouteProfileAcceptsLoopbackHostHeaderRewrite(t *testing.T) {
	for _, value := range []string{"127.0.0.1", "::1", "[::1]", "LOCALHOST"} {
		t.Run(value, func(t *testing.T) {
			hostHeaderRewrite := value
			cfg := FRPConfig{Profiles: map[string]FRPRouteProfile{
				"test": {
					Version: 1,
					Routes: []FRPRoute{{
						Name:              "api",
						Kind:              RouteKindHTTP,
						LocalAddr:         "127.0.0.1:8080",
						HostHeaderRewrite: &hostHeaderRewrite,
					}},
				},
			}}

			if _, _, err := ResolveRouteProfile(cfg, &RouteProfileSelection{Name: "test", Version: 1}); err != nil {
				t.Fatalf("ResolveRouteProfile() error = %v", err)
			}
		})
	}
}

func TestValidateProxyNameRejectsUnsafeHostComponents(t *testing.T) {
	for _, name := range []string{"atom_device", "atom-device-", "atom.device", strings.Repeat("a", 64)} {
		if err := ValidateProxyName(name); err == nil {
			t.Fatalf("ValidateProxyName(%q) accepted unsafe name", name)
		}
	}

	for _, name := range []string{"atom-device", "Atom-Device-1"} {
		if err := ValidateProxyName(name); err != nil {
			t.Fatalf("ValidateProxyName(%q) rejected safe name: %v", name, err)
		}
	}
}

func containsError(err error, fragment string) bool {
	return err != nil && len(fragment) > 0 && strings.Contains(err.Error(), fragment)
}
