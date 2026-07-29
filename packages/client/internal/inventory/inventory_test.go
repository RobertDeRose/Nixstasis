package inventory

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

func TestCollectBuildsBoundedInventoryFromProbe(t *testing.T) {
	restore := stubEnvironment(t)
	defer restore()

	root := t.TempDir()
	osReleasePath = filepath.Join(root, "os-release")
	if err := os.WriteFile(osReleasePath, []byte("ID=ubuntu\nID_LIKE=debian\nMALFORMED\nVERSION_ID=24.04\nPRETTY_NAME=\"Ubuntu 24.04 LTS\"\nSECRET=ignored\n"), 0o600); err != nil {
		t.Fatalf("write os-release: %v", err)
	}
	dfPath := filepath.Join(root, "df")
	if err := os.WriteFile(dfPath, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("write df: %v", err)
	}

	lookPath = func(name string) (string, error) {
		switch name {
		case "apt":
			return "/usr/bin/apt", nil
		case "df":
			return dfPath, nil
		default:
			return "", os.ErrNotExist
		}
	}
	packageProbe = func(_ context.Context, manager, name string) bool {
		return manager == "apt" && name == "coreutils"
	}
	now = func() time.Time { return time.Date(2026, 7, 29, 1, 2, 3, 900, time.UTC) }

	probe := &transport.CommandInventoryProbe{
		CatalogVersion: " catalog-v1 ",
		PackageNames:   []string{"coreutils", "coreutils", "client-only", "-option"},
		CommandProbes: []transport.CommandProbe{
			{Name: "df", CommandPath: dfPath},
			{Name: "df", CommandPath: "/ignored"},
			{Name: "missing", CommandPath: "/missing"},
		},
	}

	got := Collect(context.Background(), probe)
	if got == nil {
		t.Fatalf("expected inventory")
	}
	if got.SchemaVersion != schemaVersion || got.ProbeCatalogVersion != "catalog-v1" {
		t.Fatalf("unexpected metadata: %#v", got)
	}
	if got.ObservedAt != now().UTC().Truncate(time.Second) {
		t.Fatalf("observed_at = %s", got.ObservedAt)
	}
	if got.PackageManager != "apt" {
		t.Fatalf("package manager = %q", got.PackageManager)
	}
	if got.Architecture == "" {
		t.Fatalf("architecture empty")
	}
	if got.OSRelease["ID"] != "ubuntu" || got.OSRelease["PRETTY_NAME"] != "Ubuntu 24.04 LTS" {
		t.Fatalf("os-release = %#v", got.OSRelease)
	}
	if _, ok := got.OSRelease["SECRET"]; ok {
		t.Fatalf("untrusted os-release key leaked: %#v", got.OSRelease)
	}
	if _, ok := got.Packages["-option"]; ok {
		t.Fatalf("option-like package should not be reported: %#v", got.Packages)
	}
	if !got.Packages["coreutils"].Installed || got.Packages["client-only"].Installed {
		t.Fatalf("packages = %#v", got.Packages)
	}
	if got.Commands["df"].Path != dfPath {
		t.Fatalf("commands = %#v", got.Commands)
	}
	if _, ok := got.Commands["missing"]; ok {
		t.Fatalf("missing command should not be reported: %#v", got.Commands)
	}
}

func TestCollectBoundsEvidenceAndIgnoresMalformedInputs(t *testing.T) {
	restore := stubEnvironment(t)
	defer restore()

	osReleasePath = filepath.Join(t.TempDir(), "missing-os-release")
	packageProbe = func(_ context.Context, _ string, _ string) bool { return true }
	lookPath = func(name string) (string, error) {
		if name == "apt" {
			return "/usr/bin/apt", nil
		}
		return "relative", nil
	}

	packages := make([]string, 0, maxEvidenceEntries+20)
	commands := make([]transport.CommandProbe, 0, maxEvidenceEntries+20)
	for i := range maxEvidenceEntries + 20 {
		name := "pkg-" + string(rune('a'+(i%26))) + string(rune('a'+((i/26)%26)))
		packages = append(packages, name)
		commands = append(commands, transport.CommandProbe{Name: name, CommandPath: "relative"})
	}

	got := Collect(context.Background(), &transport.CommandInventoryProbe{CatalogVersion: "catalog-v1", PackageNames: packages, CommandProbes: commands})
	if got == nil {
		t.Fatalf("expected inventory")
	}
	if len(got.Packages) != maxEvidenceEntries {
		t.Fatalf("package evidence not bounded: %d", len(got.Packages))
	}
	if len(got.Commands) != 0 {
		t.Fatalf("relative command paths must not be reported: %#v", got.Commands)
	}
	if len(got.OSRelease) != 0 {
		t.Fatalf("missing os-release should produce empty map: %#v", got.OSRelease)
	}
}

func TestDetectPackageManagerUsesKnownBinaries(t *testing.T) {
	restore := stubEnvironment(t)
	defer restore()

	cases := []struct {
		name    string
		paths   map[string]bool
		manager string
	}{
		{name: "apt", paths: map[string]bool{"apt": true}, manager: "apt"},
		{name: "dnf", paths: map[string]bool{"dnf": true}, manager: "dnf"},
		{name: "rpm", paths: map[string]bool{"rpm": true}, manager: "rpm"},
		{name: "nix", paths: map[string]bool{"nix-env": true}, manager: "nix"},
		{name: "unknown", paths: map[string]bool{}, manager: "unknown"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			lookPath = func(name string) (string, error) {
				if tc.paths[name] {
					return "/usr/bin/" + name, nil
				}
				return "", os.ErrNotExist
			}
			if got := detectPackageManager(); got != tc.manager {
				t.Fatalf("detectPackageManager() = %q, want %q", got, tc.manager)
			}
		})
	}
}

func TestCollectReturnsNilWithoutProbeVersion(t *testing.T) {
	if got := Collect(context.Background(), nil); got != nil {
		t.Fatalf("nil probe inventory = %#v", got)
	}
	if got := Collect(context.Background(), &transport.CommandInventoryProbe{}); got != nil {
		t.Fatalf("empty version inventory = %#v", got)
	}
}

func TestNormalizeArchitecture(t *testing.T) {
	cases := map[string]string{
		"amd64":   "x86_64",
		"x86_64":  "x86_64",
		"arm64":   "aarch64",
		"aarch64": "aarch64",
		"386":     "x86",
		"custom":  "custom",
	}
	for input, want := range cases {
		if got := normalizeArchitecture(input); got != want {
			t.Fatalf("normalizeArchitecture(%q) = %q, want %q", input, got, want)
		}
	}
	if normalizeArchitecture(runtime.GOARCH) == "" {
		t.Fatalf("runtime architecture normalized to empty")
	}
}

func stubEnvironment(t *testing.T) func() {
	t.Helper()
	oldOSReleasePath := osReleasePath
	oldLookPath := lookPath
	oldStatPath := statPath
	oldPackageProbe := packageProbe
	oldNow := now

	statPath = os.Stat
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	packageProbe = func(context.Context, string, string) bool { return false }
	now = time.Now

	return func() {
		osReleasePath = oldOSReleasePath
		lookPath = oldLookPath
		statPath = oldStatPath
		packageProbe = oldPackageProbe
		now = oldNow
	}
}
