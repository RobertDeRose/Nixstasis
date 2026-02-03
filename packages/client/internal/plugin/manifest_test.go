package plugin

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseManifest(t *testing.T) {
	// 1. Create temporary manifest file
	tmpDir := t.TempDir()
	manifestContent := `{
		"name": "test-plugin",
		"version": "1.0.0",
		"update_url": "https://example.com/update",
		"schema_url": "https://example.com/schema",
		"executables": ["bin/collect"]
	}`
	manifestPath := filepath.Join(tmpDir, "manifest.json")
	if err := os.WriteFile(manifestPath, []byte(manifestContent), 0644); err != nil {
		t.Fatalf("Failed to write temp manifest: %v", err)
	}

	// 2. Call LoadManifest (not yet implemented)
	// We are TDD-ing, so we expect this to fail compilation if we don't stub it,
	// or fail runtime if we do stub it but don't implement it.
	// Since we need to write the test first, we assume LoadManifest exists in the package.

	manifest, err := LoadManifest(manifestPath)
	if err != nil {
		t.Fatalf("LoadManifest failed: %v", err)
	}

	// 3. Assertions
	if manifest.Name != "test-plugin" {
		t.Errorf("Expected name 'test-plugin', got '%s'", manifest.Name)
	}
	if len(manifest.Executables) != 1 || manifest.Executables[0] != "bin/collect" {
		t.Errorf("Executables mismatch: %v", manifest.Executables)
	}
}

func TestParseManifest_InvalidJSON(t *testing.T) {
	tmpDir := t.TempDir()
	manifestPath := filepath.Join(tmpDir, "manifest.json")
	if err := os.WriteFile(manifestPath, []byte("{invalid-json"), 0644); err != nil {
		t.Fatalf("Failed to write temp manifest: %v", err)
	}

	_, err := LoadManifest(manifestPath)
	if err == nil {
		t.Error("Expected error for invalid JSON, got nil")
	}
}

func TestParseManifest_MissingFile(t *testing.T) {
	_, err := LoadManifest("/non/existent/path/manifest.json")
	if err == nil {
		t.Error("Expected error for missing file, got nil")
	}
}
