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

	if got := FRPCConfigPath(); got != "/etc/nixstasis/frpc.toml" {
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
