package script

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseStaryContent(t *testing.T) {
	input := `---
name: example
version: "1.0"
schema:
  type: object
  properties:
    ok:
      type: boolean
  required: [ok]
---

def main():
    return {"ok": True}
`

	fm, body, err := ParseStaryContent(input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if fm.Name != "example" {
		t.Fatalf("expected name example, got %s", fm.Name)
	}
	if fm.Schema == nil {
		t.Fatalf("expected schema to be parsed")
	}
	if body == "" {
		t.Fatalf("expected body to be parsed")
	}
}

func TestParseStaryContentAcceptsSourceAtLimit(t *testing.T) {
	content := staryContentOfSize(t, maxStarySourceBytes)

	if _, _, err := ParseStaryContent(content); err != nil {
		t.Fatalf("ParseStaryContent() at limit error = %v", err)
	}
}

func TestParseStaryContentRejectsOversizedSource(t *testing.T) {
	content := staryContentOfSize(t, maxStarySourceBytes+1)

	_, _, err := ParseStaryContent(content)
	if !errors.Is(err, errStarySourceTooLarge) {
		t.Fatalf("ParseStaryContent() error = %v, want errStarySourceTooLarge", err)
	}
	if !strings.Contains(err.Error(), "1048577 bytes exceeds 1048576-byte limit") {
		t.Fatalf("ParseStaryContent() error = %q, want bounded size details", err)
	}
}

func TestParseStaryFileRejectsOversizedSource(t *testing.T) {
	path := filepath.Join(t.TempDir(), "oversized.stary")
	content := staryContentOfSize(t, maxStarySourceBytes+1)
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	_, _, err := ParseStaryFile(path)
	if !errors.Is(err, errStarySourceTooLarge) {
		t.Fatalf("ParseStaryFile() error = %v, want errStarySourceTooLarge", err)
	}
}

func TestCompileSchema(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"value": map[string]any{"type": "string"},
		},
		"required": []any{"value"},
	}

	compiled, err := CompileSchema(schema)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if compiled == nil {
		t.Fatalf("expected compiled schema")
	}
}

func staryContentOfSize(t *testing.T, size int) string {
	t.Helper()

	base := "---\nname: bounded\nversion: \"1\"\nschema:\n  type: object\n---\n\ndef main():\n    return {}\n#"
	if len(base) > size {
		t.Fatalf("test fixture base size %d exceeds requested size %d", len(base), size)
	}
	return base + strings.Repeat("x", size-len(base))
}
