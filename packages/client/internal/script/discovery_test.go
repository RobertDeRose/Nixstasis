package script

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGivenPathSelector_WhenResolveScript_ThenReturnsMatchingScript(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "one.stary")
	content := `---
name: one
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

	info, err := ResolveScript(path, nil)
	if err != nil {
		t.Fatalf("resolve by path: %v", err)
	}
	if info.Name != "one" {
		t.Fatalf("expected name one, got %s", info.Name)
	}
}

func TestGivenNameSelector_WhenResolveScript_ThenReturnsMatchingScript(t *testing.T) {
	scripts := []ScriptInfo{{Name: "alpha", Path: "/tmp/alpha.stary"}}
	info, err := ResolveScript("alpha", scripts)
	if err != nil {
		t.Fatalf("resolve by name: %v", err)
	}
	if info.Path != "/tmp/alpha.stary" {
		t.Fatalf("unexpected path: %s", info.Path)
	}
}
