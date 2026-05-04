package script

import (
	"context"
	"errors"
	"testing"
	"time"
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
