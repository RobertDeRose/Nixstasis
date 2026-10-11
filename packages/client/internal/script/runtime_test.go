package script

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"go.starlark.net/starlark"
)

func TestRuntimeTimeoutOnCanceledContext(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := runtime.Execute(ctx, "test.star", "def main():\n    return {}\n")
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}

func TestRuntimeTimeoutCancelsRunawayScript(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 10 * time.Millisecond})

	_, err := runtime.Execute(context.Background(), "test.star", "def main():\n    for _ in range(1000000000):\n        pass\n    return {}\n")
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}

// TestRuntimeRejectsCyclicScriptResults verifies that direct and mutual
// container cycles fail during native result conversion.
func TestRuntimeRejectsCyclicScriptResults(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{
			name: "self-referential list",
			body: `
def main():
    value = []
    value.append(value)
    return {"value": value}
`,
		},
		{
			name: "self-referential dict",
			body: `
def main():
    value = {}
    value["self"] = value
    return {"value": value}
`,
		},
		{
			name: "mutual list and dict cycle",
			body: `
def main():
    values = []
    container = {"values": values}
    values.append(container)
    return {"value": values}
`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
			_, err := runtime.Execute(t.Context(), "test.star", tt.body)
			if err == nil || !strings.Contains(err.Error(), "cyclic") {
				t.Fatalf("expected cyclic conversion error, got %v", err)
			}
		})
	}
}

// TestRuntimeConvertsNormalNestedResult verifies native types and values for
// a valid result containing nested dictionaries, lists, tuples, and scalars.
func TestRuntimeConvertsNormalNestedResult(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	got, err := runtime.Execute(t.Context(), "test.star", `
def main():
    return {
        "status": "ok",
        "nested": {
            "items": [1, True, None, ("x", 2.5)],
        },
    }
`)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	want := map[string]any{
		"status": "ok",
		"nested": map[string]any{
			"items": []any{int64(1), true, nil, []any{"x", 2.5}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected result: got %#v want %#v", got, want)
	}
}

// TestStarlarkValueToGoRejectsExcessiveNesting verifies that conversion stops
// when a nested value exceeds the depth limit.
func TestStarlarkValueToGoRejectsExcessiveNesting(t *testing.T) {
	var value starlark.Value = starlark.None
	for range maxStarlarkConversionDepth + 1 {
		value = starlark.NewList([]starlark.Value{value})
	}

	_, err := starlarkValueToGo(t.Context(), value)
	if err == nil || !strings.Contains(err.Error(), "maximum nesting depth") {
		t.Fatalf("expected nesting depth error, got %v", err)
	}
}

// TestStarlarkValueToGoRejectsExcessiveNodes verifies that a container and its
// elements must fit together within the node budget.
func TestStarlarkValueToGoRejectsExcessiveNodes(t *testing.T) {
	values := make([]starlark.Value, maxStarlarkConversionNodes)
	for i := range values {
		values[i] = starlark.None
	}

	_, err := starlarkValueToGo(t.Context(), starlark.NewList(values))
	if err == nil || !strings.Contains(err.Error(), "node limit") {
		t.Fatalf("expected node limit error, got %v", err)
	}
}

// TestStarlarkValueToGoRejectsOversizedString verifies the per-string byte limit.
func TestStarlarkValueToGoRejectsOversizedString(t *testing.T) {
	value := starlark.String(strings.Repeat("x", maxStarlarkConversionStringBytes+1))

	_, err := starlarkValueToGo(t.Context(), value)
	if err == nil || !strings.Contains(err.Error(), "string exceeds size limit") {
		t.Fatalf("expected string size error, got %v", err)
	}
}

// TestStarlarkValueToGoRejectsExcessiveOutputSize verifies that individually
// valid strings can still exceed the aggregate output budget.
func TestStarlarkValueToGoRejectsExcessiveOutputSize(t *testing.T) {
	chunk := starlark.String(strings.Repeat("x", maxStarlarkConversionStringBytes/2))
	values := make([]starlark.Value, 9)
	for i := range values {
		values[i] = chunk
	}

	_, err := starlarkValueToGo(t.Context(), starlark.NewList(values))
	if err == nil || !strings.Contains(err.Error(), "output size limit") {
		t.Fatalf("expected output size error, got %v", err)
	}
}

// TestStarlarkValueToGoChecksCancellation verifies that a canceled context
// stops conversion with ErrTimeout.
func TestStarlarkValueToGoChecksCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()

	_, err := starlarkValueToGo(ctx, starlark.NewList([]starlark.Value{starlark.None}))
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}
