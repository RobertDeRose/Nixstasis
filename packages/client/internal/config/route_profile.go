package config

import (
	"fmt"
	"net"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// Built-in profile names and route kinds supported by the client renderer.
const (
	DefaultFRPProfileName        = "default"
	DefaultFRPProfileVersion     = 1
	AtomixOSBootstrapProfileName = "atomixos-bootstrap"

	RouteKindHTTP2HTTPS = "http2https"
	RouteKindHTTP       = "http"
	RouteKindTCPMux     = "tcpmux"
)

var (
	profileNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_.-]{0,63}$`)
	routeNamePattern   = regexp.MustCompile(`^[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$`)
	proxyLabelPattern  = regexp.MustCompile(`(?i)^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)
)

// RouteProfileSelection is the bounded server-directed profile reference.
// It intentionally contains no FRPC configuration or local target values.
type RouteProfileSelection struct {
	Name    string `json:"name"`
	Version int    `json:"version"`
}

// FRPRouteProfile is a client-owned, versioned collection of typed routes.
type FRPRouteProfile struct {
	Version int        `mapstructure:"version"`
	Routes  []FRPRoute `mapstructure:"routes"`
}

// FRPRoute describes one client-owned local route.
type FRPRoute struct {
	Name      string `mapstructure:"name"`
	Kind      string `mapstructure:"kind"`
	LocalAddr string `mapstructure:"local_addr"`
	LocalPort int    `mapstructure:"local_port"`
}

// NormalizeFRPConfig adds the built-in compatibility profiles while preserving
// explicitly configured profiles. It does not trust or render any server data.
func NormalizeFRPConfig(cfg *FRPConfig) {
	if cfg == nil {
		return
	}

	if len(cfg.AllowedPluginKinds) == 0 {
		cfg.AllowedPluginKinds = []string{RouteKindHTTP2HTTPS}
	}
	if cfg.Profiles == nil {
		cfg.Profiles = make(map[string]FRPRouteProfile)
	}
	if _, exists := cfg.Profiles[DefaultFRPProfileName]; !exists {
		cfg.Profiles[DefaultFRPProfileName] = defaultFRPRouteProfile(*cfg)
	}
	if _, exists := cfg.Profiles[AtomixOSBootstrapProfileName]; !exists {
		cfg.Profiles[AtomixOSBootstrapProfileName] = atomixOSBootstrapRouteProfile()
	}
}

// ResolveRouteProfile resolves a server reference against client-owned
// configuration. A missing reference is the legacy token-only contract and
// selects the built-in default profile.
func ResolveRouteProfile(cfg FRPConfig, selection *RouteProfileSelection) (FRPRouteProfile, RouteProfileSelection, error) {
	NormalizeFRPConfig(&cfg)

	resolvedSelection := RouteProfileSelection{
		Name:    DefaultFRPProfileName,
		Version: DefaultFRPProfileVersion,
	}
	if selection != nil {
		resolvedSelection = *selection
	}

	if !validProfileName(resolvedSelection.Name) {
		return FRPRouteProfile{}, resolvedSelection, fmt.Errorf("invalid route profile name %q", resolvedSelection.Name)
	}
	if resolvedSelection.Version <= 0 {
		return FRPRouteProfile{}, resolvedSelection, fmt.Errorf("route profile %q has invalid version %d", resolvedSelection.Name, resolvedSelection.Version)
	}

	profile, ok := cfg.Profiles[resolvedSelection.Name]
	if !ok {
		return FRPRouteProfile{}, resolvedSelection, fmt.Errorf("unknown route profile %q", resolvedSelection.Name)
	}
	if profile.Version != resolvedSelection.Version {
		return FRPRouteProfile{}, resolvedSelection, fmt.Errorf(
			"route profile %q version %d is not supported; client has version %d",
			resolvedSelection.Name,
			resolvedSelection.Version,
			profile.Version,
		)
	}
	if err := validateRouteProfile(profile, cfg.AllowedPluginKinds); err != nil {
		return FRPRouteProfile{}, resolvedSelection, fmt.Errorf("route profile %q: %w", resolvedSelection.Name, err)
	}

	return profile, resolvedSelection, nil
}

func atomixOSBootstrapRouteProfile() FRPRouteProfile {
	return FRPRouteProfile{
		Version: DefaultFRPProfileVersion,
		Routes: []FRPRoute{{
			Name:      "provisioning",
			Kind:      RouteKindHTTP,
			LocalAddr: "127.0.0.1:8080",
		}},
	}
}

func defaultFRPRouteProfile(cfg FRPConfig) FRPRouteProfile {
	httpLocalAddr := cfg.HTTPLocalAddr
	if httpLocalAddr == "" {
		httpLocalAddr = "127.0.0.1:443"
	}
	sshLocalPort := cfg.SSHLocalPort
	if sshLocalPort == 0 {
		sshLocalPort = 22
	}

	return FRPRouteProfile{
		Version: DefaultFRPProfileVersion,
		Routes: []FRPRoute{
			{Name: "web", Kind: RouteKindHTTP2HTTPS, LocalAddr: httpLocalAddr},
			{Name: "ssh", Kind: RouteKindTCPMux, LocalPort: sshLocalPort},
			{Name: "pcp", Kind: RouteKindTCPMux, LocalPort: 44321},
		},
	}
}

// ValidateRouteProfile validates a client-owned profile before it is rendered.
func ValidateRouteProfile(profile FRPRouteProfile, allowedPluginKinds []string) error {
	if len(allowedPluginKinds) == 0 {
		allowedPluginKinds = []string{RouteKindHTTP2HTTPS}
	}
	return validateRouteProfile(profile, allowedPluginKinds)
}

func validateRouteProfile(profile FRPRouteProfile, allowedPluginKinds []string) error {
	for _, pluginKind := range allowedPluginKinds {
		if pluginKind != RouteKindHTTP2HTTPS {
			return fmt.Errorf("plugin kind %q is not supported by this client", pluginKind)
		}
	}

	if profile.Version <= 0 {
		return fmt.Errorf("invalid version %d", profile.Version)
	}
	if len(profile.Routes) == 0 {
		return fmt.Errorf("must define at least one route")
	}
	if len(profile.Routes) > 16 {
		return fmt.Errorf("has too many routes")
	}

	seenNames := make(map[string]struct{}, len(profile.Routes))
	for _, route := range profile.Routes {
		if !validRouteName(route.Name) {
			return fmt.Errorf("route name %q is invalid", route.Name)
		}
		if _, exists := seenNames[route.Name]; exists {
			return fmt.Errorf("route name %q is duplicated", route.Name)
		}
		seenNames[route.Name] = struct{}{}

		if err := validateRoute(route, allowedPluginKinds); err != nil {
			return err
		}
	}

	return nil
}

func validateRoute(route FRPRoute, allowedPluginKinds []string) error {
	switch route.Kind {
	case RouteKindHTTP2HTTPS:
		if !slices.Contains(allowedPluginKinds, RouteKindHTTP2HTTPS) {
			return fmt.Errorf("plugin kind %q is not allowed by the client", RouteKindHTTP2HTTPS)
		}
		return validateLoopbackAddr(route.LocalAddr)
	case RouteKindHTTP:
		return validateLoopbackAddr(route.LocalAddr)
	case RouteKindTCPMux:
		if err := validatePort(route.LocalPort); err != nil {
			return fmt.Errorf("tcp mux route %q: %w", route.Name, err)
		}
		return nil
	default:
		return fmt.Errorf("route kind %q is not supported by this client", route.Kind)
	}
}

func validateLoopbackAddr(value string) error {
	if value == "" {
		return fmt.Errorf("local target must be a loopback host and port")
	}

	host, port, err := net.SplitHostPort(value)
	if err != nil || !loopbackHost(host) {
		return fmt.Errorf("local target %q must use a loopback host and port", value)
	}
	if err := validatePortString(port); err != nil {
		return fmt.Errorf("local target %q: %w", value, err)
	}
	return nil
}

func validatePortString(value string) error {
	port, err := strconv.Atoi(value)
	if err != nil {
		return fmt.Errorf("invalid port %q", value)
	}
	return validatePort(port)
}

func validatePort(port int) error {
	if port < 1 || port > 65535 {
		return fmt.Errorf("port must be between 1 and 65535, got %d", port)
	}
	return nil
}

func loopbackHost(value string) bool {
	if strings.EqualFold(value, "localhost") {
		return true
	}
	ip := net.ParseIP(value)
	return ip != nil && ip.IsLoopback()
}

func validProfileName(value string) bool {
	return profileNamePattern.MatchString(value)
}

func validRouteName(value string) bool {
	return routeNamePattern.MatchString(value)
}

// ValidateProxyName validates a name rendered as an FRP subdomain or custom domain.
func ValidateProxyName(value string) error {
	if value == "" {
		return fmt.Errorf("proxy name must not be empty")
	}
	if len(value) > 63 {
		return fmt.Errorf("proxy name %q exceeds the 63-byte hostname-label limit", value)
	}
	if !proxyLabelPattern.MatchString(value) {
		return fmt.Errorf("proxy name %q contains unsafe hostname characters", value)
	}

	return nil
}
