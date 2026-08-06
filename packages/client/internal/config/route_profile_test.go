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

func containsError(err error, fragment string) bool {
	return err != nil && len(fragment) > 0 && strings.Contains(err.Error(), fragment)
}
