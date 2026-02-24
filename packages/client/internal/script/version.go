package script

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// ParseVersionNumber converts a version string like "v3" or "3" into an integer.
func ParseVersionNumber(version string) (int, error) {
	value := strings.TrimSpace(version)
	if value == "" {
		return 0, nil
	}
	if strings.HasPrefix(strings.ToLower(value), "v") {
		value = value[1:]
	}
	if value == "" {
		return 0, fmt.Errorf("version missing numeric value")
	}
	number, err := strconv.Atoi(value)
	if err != nil || number < 0 {
		return 0, fmt.Errorf("invalid version %q", version)
	}
	return number, nil
}

// InstallFilename returns the filename to use for an installed script.
func InstallFilename(name, version string) string {
	if strings.TrimSpace(version) == "" {
		return name + ".stary"
	}
	return fmt.Sprintf("%s_%s.stary", name, version)
}

// SelectLatestScripts returns only the newest version per script name.
func SelectLatestScripts(scripts []ScriptInfo) []ScriptInfo {
	latest := make(map[string]ScriptInfo)
	latestVersion := make(map[string]int)

	for _, info := range scripts {
		versionNumber, err := ParseVersionNumber(info.Version)
		if err != nil {
			versionNumber = 0
		}

		current, ok := latestVersion[info.Name]
		if !ok || versionNumber > current {
			latestVersion[info.Name] = versionNumber
			latest[info.Name] = info
		}
	}

	result := make([]ScriptInfo, 0, len(latest))
	for _, info := range latest {
		result = append(result, info)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].Name < result[j].Name
	})

	return result
}

// LatestScript selects the newest version for a specific script name.
func LatestScript(scripts []ScriptInfo, name string) (ScriptInfo, bool) {
	var selected ScriptInfo
	found := false
	latestVersion := -1

	for _, info := range scripts {
		if info.Name != name {
			continue
		}
		versionNumber, err := ParseVersionNumber(info.Version)
		if err != nil {
			versionNumber = 0
		}
		if !found || versionNumber > latestVersion {
			selected = info
			latestVersion = versionNumber
			found = true
		}
	}

	return selected, found
}

// MaxVersion returns the maximum version number for the named script.
func MaxVersion(scripts []ScriptInfo, name string) (int, bool) {
	maxVersion := -1
	for _, info := range scripts {
		if info.Name != name {
			continue
		}
		versionNumber, err := ParseVersionNumber(info.Version)
		if err != nil {
			versionNumber = 0
		}
		if versionNumber > maxVersion {
			maxVersion = versionNumber
		}
	}
	return maxVersion, maxVersion >= 0
}
