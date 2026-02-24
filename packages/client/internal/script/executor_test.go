package script

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestGivenValidScript_WhenExecuteScripts_ThenReturnsValidatedOutput(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ok.stary")
	content := `---
name: ok
schema:
  type: object
  properties:
    value:
      type: string
  required: [value]
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

	res, ok := results["ok"]
	if !ok {
		t.Fatalf("expected result for ok")
	}
	if res.Status != StatusSuccess {
		t.Fatalf("expected success, got %s", res.Status)
	}
	if res.ValidationStatus != ValidationValid {
		t.Fatalf("expected validation valid, got %s", res.ValidationStatus)
	}
	if res.Output["value"] != "hello" {
		t.Fatalf("unexpected output: %v", res.Output)
	}
}

func TestGivenCanceledContext_WhenExecuteScripts_ThenReturnsTimeoutStatus(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ok.stary")
	content := `---
name: ok
schema:
  type: object
  properties:
    value:
      type: string
  required: [value]
---

def main():
    return {"value": "hello"}
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write stary: %v", err)
	}

	executor := NewExecutor(RuntimeConfig{Timeout: 5 * time.Second})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	results, err := executor.ExecuteScripts(ctx, []ScriptInfo{{Path: path}})
	if err != nil {
		t.Fatalf("execute scripts: %v", err)
	}

	res := results["ok"]
	if res.Status != StatusTimeout {
		t.Fatalf("expected timeout, got %s", res.Status)
	}
	if res.Error == nil || res.Error.Type != ErrorTimeout {
		t.Fatalf("expected timeout error, got %v", res.Error)
	}
}

func TestGivenSlowScript_WhenExecuteScripts_ThenAddsWarning(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "slow.stary")
	content := `---
name: slow
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
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write stary: %v", err)
	}

	executor := NewExecutor(RuntimeConfig{Timeout: 5 * time.Second, WarnAfter: time.Nanosecond})
	results, err := executor.ExecuteScripts(context.Background(), []ScriptInfo{{Path: path}})
	if err != nil {
		t.Fatalf("execute scripts: %v", err)
	}

	res := results["slow"]
	if len(res.Warnings) == 0 {
		t.Fatalf("expected warning for slow execution")
	}
}
