package config

import "testing"

func TestPathsUseNixstasisDefaults(t *testing.T) {
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
