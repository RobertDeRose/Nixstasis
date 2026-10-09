package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPathsUseNixstasisDefaults(t *testing.T) {
	t.Setenv("NIXSTASIS_IDENTITY_PATH", "")
	t.Setenv("NIXSTASIS_REGISTRATION_PATH", "")
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "")

	if got := IdentityPath(); got != "/etc/nixstasis/id" {
		t.Fatalf("IdentityPath() = %q", got)
	}
	if got := RegistrationPath(); got != "/etc/nixstasis/registration" {
		t.Fatalf("RegistrationPath() = %q", got)
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

	if cfg.API.URL != "https://localhost:4000" || cfg.API.AllowLoopbackHTTP {
		t.Fatalf("insecure API defaults: %+v", cfg.API)
	}

	if cfg.Scripts.Dir != DefaultScriptsDir() {
		t.Fatalf("scripts dir = %q", cfg.Scripts.Dir)
	}
}

func TestPathsCanBeOverriddenForLocalDevelopment(t *testing.T) {
	t.Setenv("NIXSTASIS_IDENTITY_PATH", "/tmp/nixstasis/id")
	t.Setenv("NIXSTASIS_REGISTRATION_PATH", "/tmp/nixstasis/registration")
	t.Setenv("NIXSTASIS_FRPC_CONFIG_PATH", "/tmp/nixstasis/frpc.toml")
	t.Setenv("NIXSTASIS_FRPC_BINARY_PATH", "/tmp/nixstasis/frpc")

	if got := IdentityPath(); got != "/tmp/nixstasis/id" {
		t.Fatalf("IdentityPath() = %q", got)
	}
	if got := RegistrationPath(); got != "/tmp/nixstasis/registration" {
		t.Fatalf("RegistrationPath() = %q", got)
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
	if !ok || len(bootstrap.Routes) != 1 || bootstrap.Routes[0].LocalAddr != "127.0.0.1:8080" ||
		bootstrap.Routes[0].HostHeaderRewrite == nil || *bootstrap.Routes[0].HostHeaderRewrite != "localhost" {
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
          host_header_rewrite: "localhost"
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
	if !ok || len(profile.Routes) != 1 || profile.Routes[0].LocalAddr != "127.0.0.1:8080" ||
		profile.Routes[0].HostHeaderRewrite == nil || *profile.Routes[0].HostHeaderRewrite != "localhost" {
		t.Fatalf("loaded profiles = %+v", cfg.FRP.Profiles)
	}
}

func TestLoadLoopbackHTTPOptIn(t *testing.T) {
	configFile := filepath.Join(t.TempDir(), "client.yaml")
	if err := os.WriteFile(configFile, []byte("api:\n  url: http://127.0.0.1:4000\n  allow_loopback_http: true\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NIXSTASIS_CONFIG_FILE", configFile)
	t.Setenv("NIXSTASIS_API_URL", "")
	t.Setenv("NIXSTASIS_API_ALLOW_LOOPBACK_HTTP", "")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.API.AllowLoopbackHTTP {
		t.Fatal("YAML loopback opt-in was not loaded")
	}
	t.Setenv("NIXSTASIS_API_ALLOW_LOOPBACK_HTTP", "false")
	cfg, err = Load()
	if err != nil || cfg.API.AllowLoopbackHTTP {
		t.Fatalf("environment override failed: config=%+v, error=%v", cfg, err)
	}
	t.Setenv("NIXSTASIS_API_ALLOW_LOOPBACK_HTTP", "true")
	cfg, err = Load()
	if err != nil || !cfg.API.AllowLoopbackHTTP {
		t.Fatalf("environment opt-in failed: config=%+v, error=%v", cfg, err)
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

func TestLoadReadsLocalScriptArgumentAndFileCapabilities(t *testing.T) {
	configFile := filepath.Join(t.TempDir(), "client.yaml")
	contents := `runtime:
  exec_commands:
    uname: /usr/bin/uname
  exec_command_args:
    /usr/bin/uname:
      - ["-srmo"]
  read_files:
    - /proc/loadavg
`
	if err := os.WriteFile(configFile, []byte(contents), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Setenv("NIXSTASIS_CONFIG_FILE", configFile)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got := cfg.Runtime.ExecCommandArgs["/usr/bin/uname"]; len(got) != 1 || len(got[0]) != 1 || got[0][0] != "-srmo" {
		t.Fatalf("exec command args = %#v", got)
	}
	if len(cfg.Runtime.ReadFiles) != 1 || cfg.Runtime.ReadFiles[0] != "/proc/loadavg" {
		t.Fatalf("read files = %#v", cfg.Runtime.ReadFiles)
	}
}
