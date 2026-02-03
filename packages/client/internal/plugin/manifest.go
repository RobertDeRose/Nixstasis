package plugin

import (
	json "encoding/json/v2"
	"fmt"
	"os"
	"path/filepath"
)

// LoadManifest reads and parses a manifest.json file.
func LoadManifest(path string) (*Manifest, error) {
	// Clean path to address G304 (Potential file inclusion)
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}

	var manifest Manifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("failed to parse manifest JSON: %w", err)
	}

	// Validate required fields
	if manifest.Name == "" {
		return nil, fmt.Errorf("manifest missing 'name'")
	}
	if len(manifest.Executables) == 0 {
		return nil, fmt.Errorf("manifest missing 'executables'")
	}

	return &manifest, nil
}
