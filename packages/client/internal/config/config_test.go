package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPathsUseNixstasisDefaults(t *testing.T) {
	t.Setenv("NIXSTASIS_IDENTITY_PATH", "")
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "")

	if got := IdentityPath(); got != "/etc/nixstasis/id" {
		t.Fatalf("IdentityPath() = %q", got)
	}

	if got := FRPCConfigPath(); got != "/usr/share/nixstasis/frpc.toml" {
		t.Fatalf("FRPCConfigPath() = %q", got)
	}

	if got := FRPCBinaryPath(); got != "/usr/libexec/nixstasis/frpc" {
		t.Fatalf("FRPCBinaryPath() = %q", got)
	}

	cfg, err := GetDefaultConfig()
	if err != nil {
		t.Fatalf("GetDefaultConfig() error = %v", err)
	}

	if cfg.Scripts.Dir != DefaultScriptsDir() {
		t.Fatalf("scripts dir = %q", cfg.Scripts.Dir)
	}
}

func TestPathsCanBeOverriddenForLocalDevelopment(t *testing.T) {
	t.Setenv("NIXSTASIS_IDENTITY_PATH", "/tmp/nixstasis/id")
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "/tmp/nixstasis/frpc.toml")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/tmp/nixstasis/frpc")

	if got := IdentityPath(); got != "/tmp/nixstasis/id" {
		t.Fatalf("IdentityPath() = %q", got)
	}

	if got := FRPCConfigPath(); got != "/tmp/nixstasis/frpc.toml" {
		t.Fatalf("FRPCConfigPath() = %q", got)
	}

	if got := FRPCBinaryPath(); got != "/tmp/nixstasis/frpc" {
		t.Fatalf("FRPCBinaryPath() = %q", got)
	}
}

func TestGetDefaultConfigDeclaresBoundedFRPProfiles(t *testing.T) {
	cfg, err := GetDefaultConfig()
	if err != nil {
		t.Fatalf("GetDefaultConfig() error = %v", err)
	}

	profile, ok := cfg.FRP.Profiles[DefaultFRPProfileName]
	if !ok || profile.Version != DefaultFRPProfileVersion {
		t.Fatalf("default FRP profile = %+v", profile)
	}
	if len(profile.Routes) != 3 {
		t.Fatalf("default FRP routes = %d, want 3", len(profile.Routes))
	}
	bootstrap, ok := cfg.FRP.Profiles[AtomixOSBootstrapProfileName]
	if !ok || len(bootstrap.Routes) != 1 || bootstrap.Routes[0].LocalAddr != "127.0.0.1:8080" {
		t.Fatalf("bootstrap FRP profile = %+v", bootstrap)
	}
	if len(cfg.FRP.AllowedPluginKinds) != 1 || cfg.FRP.AllowedPluginKinds[0] != RouteKindHTTP2HTTPS {
		t.Fatalf("allowed plugin kinds = %+v", cfg.FRP.AllowedPluginKinds)
	}
}

func TestLoadReadsClientOwnedFRPProfiles(t *testing.T) {
	configFile := filepath.Join(t.TempDir(), "client.yaml")
	contents := `frp:
  server_addr: "frps.example"
  profiles:
    atomixos-bootstrap:
      version: 1
      routes:
        - name: "provisioning"
          kind: "http"
          local_addr: "127.0.0.1:8080"
`
	if err := os.WriteFile(configFile, []byte(contents), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Setenv("NIXSTASIS_CONFIG_FILE", configFile)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	profile, ok := cfg.FRP.Profiles["atomixos-bootstrap"]
	if !ok || len(profile.Routes) != 1 || profile.Routes[0].LocalAddr != "127.0.0.1:8080" {
		t.Fatalf("loaded profiles = %+v", cfg.FRP.Profiles)
	}
}

func TestLoadCanUseExplicitConfigFile(t *testing.T) {
	configFile := filepath.Join(t.TempDir(), "client.yaml")
	if err := os.WriteFile(configFile, []byte("api:\n  url: https://nixstasis.localhost\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Setenv("NIXSTASIS_CONFIG_FILE", configFile)
	t.Setenv("NIXSTASIS_API_URL", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.API.URL != "https://nixstasis.localhost" {
		t.Fatalf("api url = %q", cfg.API.URL)
	}
}
