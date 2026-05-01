package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGivenValidScript_WhenTestScriptRuns_ThenYAMLOutputPrinted(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "example.stary")
	content := `---
name: example
schema:
  type: object
  properties:
    hello:
      type: string
  required: [hello]
---

def main():
    return {"hello": "world"}
`

	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write test script: %v", err)
	}

	cmd := testScriptCmd
	out := &bytes.Buffer{}
	cmd.SetOut(out)

	if err := runTestScript(cmd, path); err != nil {
		t.Fatalf("expected success, got error: %v", err)
	}

	if !strings.Contains(out.String(), "hello: world") {
		t.Fatalf("expected YAML output to include hello: world, got: %s", out.String())
	}
}

func TestGivenInvalidScript_WhenTestScriptRuns_ThenExitNonZeroAndNoYAMLOutput(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "invalid.stary")
	content := `---
name: invalid
schema:
  type: object
---

def not_main():
    return {}
`

	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write test script: %v", err)
	}

	cmd := testScriptCmd
	out := &bytes.Buffer{}
	cmd.SetOut(out)

	if err := runTestScript(cmd, path); err == nil {
		t.Fatalf("expected error for invalid script")
	} else if !strings.Contains(err.Error(), "script failed") {
		t.Fatalf("expected script failed error, got: %v", err)
	}

	if out.Len() != 0 {
		t.Fatalf("expected no YAML output on failure, got: %s", out.String())
	}
}
