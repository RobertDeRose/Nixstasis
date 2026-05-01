package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
)

const testScript = `---
name: test_script
schema:
  type: object
  properties:
    value:
      type: string
  required: [value]
---

def main():
    return {"value": "ok"}
`

func TestGivenScriptFile_WhenListInstallRemove_ThenLifecycleSucceeds(t *testing.T) {
	tempDir := t.TempDir()
	t.Setenv("HOME", tempDir)

	cfg = &config.Config{Scripts: config.ScriptsConfig{Dir: tempDir}}

	sourcePath := filepath.Join(tempDir, "source.stary")
	if err := os.WriteFile(sourcePath, []byte(testScript), 0o644); err != nil {
		t.Fatalf("write source: %v", err)
	}

	if err := listScriptsCmd.RunE(listScriptsCmd, nil); err != nil {
		t.Fatalf("list scripts: %v", err)
	}

	installForce = false
	if err := installScriptCmd.RunE(nil, []string{sourcePath}); err != nil {
		t.Fatalf("install script: %v", err)
	}

	installDir := filepath.Join(tempDir, ".config", "nixstasis", "scripts")
	installedPath := filepath.Join(installDir, "test_script.stary")
	if _, err := os.Stat(installedPath); err != nil {
		t.Fatalf("expected installed script, got %v", err)
	}

	if err := removeScriptCmd.RunE(nil, []string{"test_script"}); err != nil {
		t.Fatalf("remove script: %v", err)
	}
	if _, err := os.Stat(installedPath); !os.IsNotExist(err) {
		t.Fatalf("expected script to be removed")
	}
}
