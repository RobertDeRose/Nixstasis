package script

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestGivenInvalidFrontMatter_WhenExecuteScripts_ThenReturnsError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.stary")
	content := `---
name: ""
---

def main():
    return {"value": "hello"}
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write stary: %v", err)
	}

	executor := NewExecutor(RuntimeConfig{Timeout: 5 * time.Second})
	results, err := executor.ExecuteScripts(context.Background(), []ScriptInfo{{Path: path}})
	if err != nil {
		t.Fatalf("execute scripts: %v", err)
	}

	res := results[filepath.Base(path)]
	if res.Status != StatusError {
		t.Fatalf("expected error status, got %s", res.Status)
	}
}

func TestGivenSchemaMismatch_WhenExecuteScripts_ThenReturnsValidationError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.stary")
	content := `---
name: mismatch
schema:
  type: object
  properties:
    value:
      type: number
  required: [value]
---

def main():
    return {"value": "not-a-number"}
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write stary: %v", err)
	}

	executor := NewExecutor(RuntimeConfig{Timeout: 5 * time.Second})
	results, err := executor.ExecuteScripts(context.Background(), []ScriptInfo{{Path: path}})
	if err != nil {
		t.Fatalf("execute scripts: %v", err)
	}

	res := results["mismatch"]
	if res.Status != StatusError {
		t.Fatalf("expected error status, got %s", res.Status)
	}
	if res.ValidationStatus != ValidationInvalid {
		t.Fatalf("expected validation invalid, got %s", res.ValidationStatus)
	}
	if res.Error == nil || res.Error.Type != ErrorValidation {
		t.Fatalf("expected validation error, got %v", res.Error)
	}
}
