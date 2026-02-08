package script

import (
	"bytes"
	"encoding/json/v2"
	"errors"
	"fmt"
	"strings"

	"github.com/santhosh-tekuri/jsonschema/v5"
)

// CompileSchema builds a JSON Schema validator from the provided schema map.
func CompileSchema(schema map[string]any) (*jsonschema.Schema, error) {
	if schema == nil {
		return nil, fmt.Errorf("schema is nil")
	}

	data, err := json.Marshal(schema)
	if err != nil {
		return nil, fmt.Errorf("marshal schema: %w", err)
	}

	compiler := jsonschema.NewCompiler()
	if err := compiler.AddResource("schema.json", bytes.NewReader(data)); err != nil {
		return nil, fmt.Errorf("load schema: %w", err)
	}

	compiled, err := compiler.Compile("schema.json")
	if err != nil {
		return nil, fmt.Errorf("compile schema: %w", err)
	}

	return compiled, nil
}

// ValidateOutput checks script output against a compiled schema.
func ValidateOutput(schema *jsonschema.Schema, output map[string]any) error {
	if schema == nil {
		return fmt.Errorf("schema is nil")
	}
	if output == nil {
		return fmt.Errorf("output is nil")
	}

	if err := schema.Validate(output); err != nil {
		var validationErr *jsonschema.ValidationError
		if errors.As(err, &validationErr) {
			issues := collectValidationIssues(validationErr)
			return &ValidationDetailsError{
				Summary: "schema validation failed",
				Simple:  formatValidationIssues(issues, false),
				Verbose: formatValidationIssues(issues, true),
			}
		}
		return fmt.Errorf("schema validation failed: %w", err)
	}

	return nil
}

// ValidationDetailsError captures a structured validation error summary.
type ValidationDetailsError struct {
	Summary string
	Simple  string
	Verbose string
}

func (v *ValidationDetailsError) Error() string {
	if v == nil {
		return ""
	}
	return v.Summary
}

func parseExpectedGot(message string) (expected, got string, ok bool) {
	trimmed := strings.TrimSpace(message)
	const prefix = "expected "
	const mid = ", but got "
	if !strings.HasPrefix(trimmed, prefix) {
		return "", "", false
	}
	rest := strings.TrimPrefix(trimmed, prefix)
	before, after, ok := strings.Cut(rest, mid)
	if !ok {
		return "", "", false
	}
	expected = strings.TrimSpace(before)
	got = strings.TrimSpace(after)
	if expected == "" || got == "" {
		return "", "", false
	}
	return expected, got, true
}

func parseMissingProperties(message string) ([]string, bool) {
	const prefix = "missing properties:"
	_, after, ok := strings.Cut(message, prefix)
	if !ok {
		return nil, false
	}
	rest := strings.TrimSpace(after)
	var props []string
	for {
		start := strings.Index(rest, "'")
		if start == -1 {
			break
		}
		rest = rest[start+1:]
		end := strings.Index(rest, "'")
		if end == -1 {
			break
		}
		props = append(props, rest[:end])
		rest = rest[end+1:]
	}
	if len(props) == 0 {
		return nil, false
	}
	return props, true
}

func displayPath(pointer string) string {
	path := pointerToPath(pointer)
	if path == "" {
		return "output"
	}
	return path
}

type validationIssue struct {
	Path            string
	KeywordLocation string
	Expected        string
	Found           string
	Message         string
}

func collectValidationIssues(err *jsonschema.ValidationError) []validationIssue {
	if err == nil {
		return nil
	}

	issues := make([]validationIssue, 0, len(err.Causes)+1)
	var walk func(*jsonschema.ValidationError)

	walk = func(current *jsonschema.ValidationError) {
		if current == nil {
			return
		}
		if len(current.Causes) == 0 {
			issues = append(issues, issueFromValidation(current)...)
			return
		}
		for _, cause := range current.Causes {
			walk(cause)
		}
	}

	walk(err)

	if len(issues) == 0 && err.Message != "" {
		issues = append(issues, issueFromValidation(err)...)
	}

	return issues
}

func issueFromValidation(err *jsonschema.ValidationError) []validationIssue {
	path := displayPath(err.InstanceLocation)

	if missing, ok := parseMissingProperties(err.Message); ok {
		issues := make([]validationIssue, 0, len(missing))
		for _, prop := range missing {
			issues = append(issues, validationIssue{
				Path:            joinPath(path, prop),
				KeywordLocation: err.KeywordLocation,
				Message:         "required field missing",
			})
		}
		return issues
	}

	expected, found, ok := parseExpectedGot(err.Message)
	if ok {
		return []validationIssue{{
			Path:            path,
			KeywordLocation: err.KeywordLocation,
			Expected:        expected,
			Found:           found,
		}}
	}

	return []validationIssue{{
		Path:            path,
		KeywordLocation: err.KeywordLocation,
		Message:         err.Message,
	}}
}

func formatValidationIssues(issues []validationIssue, verbose bool) string {
	if len(issues) == 0 {
		return ""
	}

	lines := make([]string, 0, len(issues))
	for _, issue := range issues {
		lines = append(lines, formatValidationIssue(issue, verbose))
	}

	return strings.Join(lines, "\n")
}

func formatValidationIssue(issue validationIssue, verbose bool) string {
	base := "❌ " + issue.Path + ": "
	switch {
	case issue.Message != "":
		base += issue.Message
	case issue.Expected != "" || issue.Found != "":
		base += fmt.Sprintf("expected %s, found %s", issue.Expected, issue.Found)
	default:
		base += "validation failed"
	}

	if !verbose {
		return base
	}

	keyword := normalizeKeyword(issue.KeywordLocation)
	if keyword == "" {
		return base
	}

	return fmt.Sprintf("%s (keyword: %s, schema: #%s)", base, keyword, issue.KeywordLocation)
}

func pointerToPath(pointer string) string {
	if pointer == "" || pointer == "/" {
		return ""
	}

	parts := strings.Split(pointer, "/")
	var builder strings.Builder
	for i, part := range parts {
		if i == 0 {
			continue
		}
		part = strings.ReplaceAll(part, "~1", "/")
		part = strings.ReplaceAll(part, "~0", "~")
		if part == "" {
			continue
		}
		if isDigits(part) {
			builder.WriteString("[")
			builder.WriteString(part)
			builder.WriteString("]")
			continue
		}
		if builder.Len() > 0 {
			builder.WriteString(".")
		}
		builder.WriteString(part)
	}

	return builder.String()
}

func joinPath(base, field string) string {
	if base == "" || base == "output" {
		return field
	}
	return base + "." + field
}

func isDigits(value string) bool {
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return value != ""
}

func normalizeKeyword(location string) string {
	if location == "" {
		return ""
	}
	trimmed := strings.TrimPrefix(location, "/")
	if trimmed == "" {
		return ""
	}
	if idx := strings.LastIndex(trimmed, "/"); idx != -1 {
		return trimmed[idx+1:]
	}
	return trimmed
}
