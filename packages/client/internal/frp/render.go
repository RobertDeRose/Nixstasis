package frp

import (
	"fmt"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const renderedFRPConfigName = "frpc.toml"

func renderConfig(frpConfig config.FRPConfig, profile config.FRPRouteProfile) (string, error) {
	config.NormalizeFRPConfig(&frpConfig)
	if err := validateRenderConfig(frpConfig, profile); err != nil {
		return "", err
	}

	var builder strings.Builder
	writeLine := func(format string, args ...any) {
		_, _ = fmt.Fprintf(&builder, format+"\n", args...)
	}

	writeLine("serverAddr = %s", strconv.Quote("{{ .Envs.FRPS_SERVER_ADDR }}"))
	writeLine("serverPort = {{ .Envs.FRPS_SERVER_PORT }}")
	writeLine("auth.method = \"token\"")
	writeLine("auth.token = %s", strconv.Quote("{{ .Envs.FRPS_AUTH_TOKEN }}"))
	writeLine("webServer.addr = %s", strconv.Quote("{{ .Envs.FRPC_WEB_SERVER_ADDR }}"))
	writeLine("webServer.port = {{ .Envs.FRPC_WEB_SERVER_PORT }}")
	writeLine("log.to = \"console\"")

	for _, route := range profile.Routes {
		proxyName := routeProxyName(frpConfig.Name, route.Name)
		writeLine("")
		writeLine("[[proxies]]")
		writeLine("name = %s", strconv.Quote(proxyName))

		switch route.Kind {
		case config.RouteKindHTTP2HTTPS:
			writeLine("type = \"http\"")
			writeLine("subdomain = %s", strconv.Quote(proxyName))
			writeLine("")
			writeLine("[proxies.plugin]")
			writeLine("type = \"http2https\"")
			writeLine("localAddr = %s", strconv.Quote(route.LocalAddr))
		case config.RouteKindHTTP:
			host, port, err := net.SplitHostPort(route.LocalAddr)
			if err != nil {
				return "", fmt.Errorf("route %q has invalid local address: %w", route.Name, err)
			}
			writeLine("type = \"http\"")
			writeLine("subdomain = %s", strconv.Quote(proxyName))
			writeLine("localIP = %s", strconv.Quote(host))
			writeLine("localPort = %s", port)
			if route.HostHeaderRewrite != nil {
				writeLine("hostHeaderRewrite = %s", strconv.Quote(*route.HostHeaderRewrite))
			}
		case config.RouteKindTCPMux:
			writeLine("type = \"tcpmux\"")
			writeLine("multiplexer = \"httpconnect\"")
			writeLine("customDomains = [%s]", strconv.Quote(proxyName))
			writeLine("localIP = \"127.0.0.1\"")
			writeLine("localPort = %d", route.LocalPort)
		}
	}

	return builder.String(), nil
}

func validateRenderConfig(frpConfig config.FRPConfig, profile config.FRPRouteProfile) error {
	if err := config.ValidateRouteProfile(profile, frpConfig.AllowedPluginKinds); err != nil {
		return err
	}
	if frpConfig.Name == "" {
		return fmt.Errorf("frpc config requires a non-empty name")
	}
	if err := config.ValidateProxyName(frpConfig.Name); err != nil {
		return fmt.Errorf("frpc proxy name: %w", err)
	}
	if frpConfig.ServerAddr == "" {
		return fmt.Errorf("frpc config requires a non-empty server_addr")
	}
	if frpConfig.ServerPort < 1 || frpConfig.ServerPort > 65535 {
		return fmt.Errorf("frpc server_port must be between 1 and 65535, got %d", frpConfig.ServerPort)
	}
	if frpConfig.WebServerAddr == "" || frpConfig.WebServerPort < 1 || frpConfig.WebServerPort > 65535 {
		return fmt.Errorf("frpc web server address and port are invalid")
	}
	if !loopbackAddr(frpConfig.WebServerAddr) {
		return fmt.Errorf("frp web_server_addr must be a loopback address")
	}

	for _, route := range profile.Routes {
		if err := config.ValidateProxyName(routeProxyName(frpConfig.Name, route.Name)); err != nil {
			return fmt.Errorf("route %q proxy name: %w", route.Name, err)
		}
	}

	return nil
}

func writeRenderedConfig(frpConfig config.FRPConfig, profile config.FRPRouteProfile) (string, error) {
	contents, err := renderConfig(frpConfig, profile)
	if err != nil {
		return "", err
	}

	if err := os.MkdirAll(frpRuntimeDir, 0o750); err != nil {
		return "", fmt.Errorf("failed to create FRP runtime directory: %w", err)
	}
	path := filepath.Join(frpRuntimeDir, renderedFRPConfigName)
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		return "", fmt.Errorf("failed to write rendered FRP config: %w", err)
	}
	return path, nil
}

func removeRenderedConfig() {
	removeFRPFile(filepath.Join(frpRuntimeDir, renderedFRPConfigName), "rendered FRP config")
}

func removeFRPFile(path, description string) {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		slog.Error("failed to remove FRP file", "description", description, "error", err)
	}
}

func routeProxyName(deviceName, routeName string) string {
	if routeName == "web" {
		return deviceName
	}
	return deviceName + "-" + routeName
}
