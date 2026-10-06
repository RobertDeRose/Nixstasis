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

func TestRuntimeRejectsOversizedBodyBeforeStarlarkParsing(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	body := strings.Repeat("x", maxStarySourceBytes+1)

	_, err := runtime.Execute(t.Context(), "oversized.star", body)
	if !errors.Is(err, errStarySourceTooLarge) {
		t.Fatalf("Execute() error = %v, want errStarySourceTooLarge", err)
	}
}

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
	// Isolate the wall-clock timeout behavior from the independent step budget.
	runtime.maxExecutionSteps = ^uint64(0)

	_, err := runtime.Execute(context.Background(), "test.star", "def main():\n    for _ in range(1000000000):\n        pass\n    return {}\n")
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}

func TestRuntimeDefaultsExecutionStepLimit(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{})
	if runtime.maxExecutionSteps != defaultMaxStarlarkExecutionSteps {
		t.Fatalf("unexpected execution step limit: got %d want %d", runtime.maxExecutionSteps, defaultMaxStarlarkExecutionSteps)
	}
}

func TestRuntimeRejectsExecutionStepLimit(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	runtime.maxExecutionSteps = 1_000

	_, err := runtime.Execute(t.Context(), "test.star", `
def main():
    values = []
    for i in range(1000000):
        values.append(i)
    return {"values": values}
`)
	if !errors.Is(err, ErrExecutionLimit) {
		t.Fatalf("expected ErrExecutionLimit, got %v", err)
	}

	mapped := mapError(err)
	if mapped == nil || mapped.Type != ErrorExecution {
		t.Fatalf("expected execution error mapping, got %#v", mapped)
	}
}

func TestRuntimeExecutionStepLimitAllowsNormalScript(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	runtime.maxExecutionSteps = 10_000

	got, err := runtime.Execute(t.Context(), "test.star", `
def main():
    values = [i * i for i in range(100)]
    return {"count": len(values), "last": values[-1]}
`)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	want := map[string]any{"count": int64(100), "last": int64(9801)}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected result: got %#v want %#v", got, want)
	}
}

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

func TestStarlarkValueToGoRejectsOversizedString(t *testing.T) {
	value := starlark.String(strings.Repeat("x", maxStarlarkConversionStringBytes+1))

	_, err := starlarkValueToGo(t.Context(), value)
	if err == nil || !strings.Contains(err.Error(), "string exceeds size limit") {
		t.Fatalf("expected string size error, got %v", err)
	}
}

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

func TestStarlarkValueToGoChecksCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()

	_, err := starlarkValueToGo(ctx, starlark.NewList([]starlark.Value{starlark.None}))
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("expected ErrTimeout, got %v", err)
	}
}
