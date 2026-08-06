package frp

import (
	"strings"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

func TestRenderConfigSupportsHTTPSAndPlainHTTPProfiles(t *testing.T) {
	cfg := config.FRPConfig{
		Name:          "atom-device",
		ServerAddr:    "frps.internal",
		ServerPort:    7000,
		WebServerAddr: "127.0.0.1",
		WebServerPort: 7400,
		AuthToken:     "secret-token",
	}
	profile := config.FRPRouteProfile{
		Version: 1,
		Routes: []config.FRPRoute{
			{Name: "secure", Kind: config.RouteKindHTTP2HTTPS, LocalAddr: "127.0.0.1:443"},
			{Name: "provisioning", Kind: config.RouteKindHTTP, LocalAddr: "127.0.0.1:8080"},
			{Name: "ssh", Kind: config.RouteKindTCPMux, LocalPort: 22},
		},
	}

	rendered, err := renderConfig(cfg, profile)
	if err != nil {
		t.Fatalf("renderConfig() error = %v", err)
	}

	for _, fragment := range []string{
		`serverAddr = "{{ .Envs.FRPS_SERVER_ADDR }}"`,
		`type = "http"`,
		`type = "http2https"`,
		`localAddr = "127.0.0.1:443"`,
		`subdomain = "atom-device-secure"`,
		`subdomain = "atom-device-provisioning"`,
		`localIP = "127.0.0.1"`,
		`localPort = 8080`,
		`type = "tcpmux"`,
		`customDomains = ["atom-device-ssh"]`,
		`localPort = 22`,
	} {
		if !strings.Contains(rendered, fragment) {
			t.Errorf("rendered config missing %q:\n%s", fragment, rendered)
		}
	}
	if strings.Contains(rendered, "secret-token") {
		t.Fatal("rendered config must not contain the auth token")
	}
}

func TestRenderConfigRejectsInvalidProfile(t *testing.T) {
	cfg := config.FRPConfig{Name: "atom-device", ServerAddr: "frps.internal", ServerPort: 7000}
	profile := config.FRPRouteProfile{
		Version: 1,
		Routes:  []config.FRPRoute{{Name: "api", Kind: config.RouteKindHTTP, LocalAddr: "192.168.1.10:8080"}},
	}

	if _, err := renderConfig(cfg, profile); err == nil || !strings.Contains(err.Error(), "loopback") {
		t.Fatalf("renderConfig() error = %v, want loopback validation", err)
	}
}
