// Package inventory collects bounded, untrusted command catalog evidence for heartbeats.
package inventory

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

const (
	schemaVersion      = 1
	maxEvidenceEntries = 128
	maxStringLength    = 256
)

var validPackageName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9+_.:@-]{0,127}$`)

var (
	osReleasePath = "/etc/os-release"
	lookPath      = exec.LookPath
	statPath      = os.Stat
	packageProbe  = packageInstalled
	now           = time.Now
)

// Collect returns bounded command/package evidence for a server-provided probe.
func Collect(ctx context.Context, probe *transport.CommandInventoryProbe) *transport.CommandInventoryEvidence {
	if probe == nil || sanitize(probe.CatalogVersion) == "" {
		return nil
	}

	osRelease := readOSRelease(osReleasePath)
	pm := detectPackageManager()
	packages := collectPackages(ctx, pm, probe.PackageNames)
	commands := collectCommands(probe.CommandProbes, osFamily(osRelease))

	return &transport.CommandInventoryEvidence{
		SchemaVersion:       schemaVersion,
		ProbeCatalogVersion: sanitize(probe.CatalogVersion),
		ObservedAt:          now().UTC().Truncate(time.Second),
		Architecture:        normalizeArchitecture(runtime.GOARCH),
		PackageManager:      pm,
		OSRelease:           osRelease,
		Packages:            packages,
		Commands:            commands,
	}
}

func readOSRelease(path string) map[string]string {
	// #nosec G304 -- production reads a fixed os-release path; tests override it.
	file, err := os.Open(path)
	if err != nil {
		return map[string]string{}
	}
	defer func() { _ = file.Close() }()

	allowed := map[string]bool{"ID": true, "ID_LIKE": true, "VERSION_ID": true, "PRETTY_NAME": true}
	values := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || !allowed[key] {
			continue
		}
		values[key] = sanitize(unquoteOSReleaseValue(value))
	}
	return values
}

func unquoteOSReleaseValue(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		quote := value[0]
		if (quote == '\'' || quote == '"') && value[len(value)-1] == quote {
			value = value[1 : len(value)-1]
		}
	}
	value = strings.ReplaceAll(value, `\"`, `"`)
	value = strings.ReplaceAll(value, `\\`, `\`)
	return value
}

func normalizeArchitecture(arch string) string {
	switch strings.ToLower(strings.TrimSpace(arch)) {
	case "amd64", "x86_64":
		return "x86_64"
	case "arm64", "aarch64":
		return "aarch64"
	case "386", "i386", "i686":
		return "x86"
	default:
		return sanitize(arch)
	}
}

func osFamily(osRelease map[string]string) string {
	ids := make([]string, 0, 3)
	for _, key := range []string{"ID", "ID_LIKE"} {
		ids = append(ids, strings.FieldsFunc(strings.ToLower(osRelease[key]), func(r rune) bool {
			return r == ' ' || r == '\t' || r == ','
		})...)
	}

	if contains(ids, "nixos") {
		return "nixos"
	}
	if containsAny(ids, "debian", "ubuntu") {
		return "debian"
	}
	if containsAny(ids, "fedora", "rhel", "centos", "rocky", "almalinux", "redhat") {
		return "fedora"
	}
	return "unsupported"
}

func contains(values []string, target string) bool {
	return slices.Contains(values, target)
}

func containsAny(values []string, targets ...string) bool {
	for _, target := range targets {
		if contains(values, target) {
			return true
		}
	}
	return false
}

func detectPackageManager() string {
	for _, candidate := range []struct {
		binary string
		name   string
	}{
		{"apt", "apt"},
		{"dnf", "dnf"},
		{"rpm", "rpm"},
		{"nix-env", "nix"},
	} {
		if _, err := lookPath(candidate.binary); err == nil {
			return candidate.name
		}
	}
	return "unknown"
}

func collectPackages(ctx context.Context, manager string, names []string) map[string]transport.PackageEvidence {
	packages := make(map[string]transport.PackageEvidence)
	for _, name := range boundedUnique(names) {
		if !validPackageName.MatchString(name) {
			continue
		}
		packages[name] = transport.PackageEvidence{Installed: packageProbe(ctx, manager, name)}
	}
	return packages
}

func collectCommands(probes []transport.CommandProbe, deviceOSFamily string) map[string]transport.CommandEvidence {
	commands := make(map[string]transport.CommandEvidence)
	for _, probe := range probes {
		if len(commands) >= maxEvidenceEntries {
			break
		}
		name := sanitize(probe.Name)
		if name == "" || !matchesOSFamily(probe.OSFamily, deviceOSFamily) {
			continue
		}
		if _, ok := commands[name]; ok {
			continue
		}
		if path := resolveCommandPath(name, sanitize(probe.CommandPath)); path != "" {
			commands[name] = transport.CommandEvidence{Path: path}
		}
	}
	return commands
}

func matchesOSFamily(probeOSFamily, deviceOSFamily string) bool {
	probeOSFamily = sanitize(probeOSFamily)
	if probeOSFamily == "" {
		return true
	}
	return deviceOSFamily != "unsupported" && probeOSFamily == deviceOSFamily
}

func resolveCommandPath(_, expectedPath string) string {
	if expectedPath == "" || !filepath.IsAbs(expectedPath) || !executable(expectedPath) {
		return ""
	}
	return expectedPath
}

func executable(path string) bool {
	info, err := statPath(path)
	if err != nil || info.IsDir() {
		return false
	}
	return info.Mode().Perm()&0o111 != 0
}

func boundedUnique(values []string) []string {
	seen := make(map[string]struct{})
	out := make([]string, 0, min(len(values), maxEvidenceEntries))
	for _, value := range values {
		value = sanitize(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
		if len(out) >= maxEvidenceEntries {
			break
		}
	}
	sort.Strings(out)
	return out
}

func sanitize(value string) string {
	value = strings.TrimSpace(value)
	if len(value) > maxStringLength {
		value = value[:maxStringLength]
	}
	return value
}

func packageInstalled(ctx context.Context, manager, name string) bool {
	if !validPackageName.MatchString(name) {
		return false
	}

	probeCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	var cmd *exec.Cmd
	switch manager {
	case "apt":
		cmd = exec.CommandContext(probeCtx, "dpkg-query", "-W", "-f=${Status}", name)
	case "dnf", "rpm":
		cmd = exec.CommandContext(probeCtx, "rpm", "-q", name)
	case "nix":
		cmd = exec.CommandContext(probeCtx, "nix-env", "-q", name)
	default:
		return false
	}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	text := string(output)
	if manager == "apt" {
		return strings.Contains(text, "install ok installed")
	}
	return strings.Contains(text, name)
}
