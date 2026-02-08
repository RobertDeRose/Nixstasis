package script

import "testing"

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
