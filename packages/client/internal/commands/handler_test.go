package commands

import (
	"context"
	"testing"

	"github.com/sfero-nixstasis/client/internal/transport"
)

func TestGivenDuplicateCommandID_WhenExecuteBatch_ThenLaterDuplicateFails(t *testing.T) {
	handler := NewHandler("")
	commands := []transport.CommandRequest{
		{CommandID: "cmd-1", Type: "list_scripts"},
		{CommandID: "cmd-1", Type: "list_scripts"},
	}

	results := handler.ExecuteBatch(context.Background(), commands)
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusOK {
		t.Fatalf("expected first command to succeed, got %s", results[0].Status)
	}
	if results[1].Status != transport.CommandStatusFailed || results[1].Error != "duplicate_command_id" {
		t.Fatalf("expected duplicate to fail with duplicate_command_id, got status=%s error=%s", results[1].Status, results[1].Error)
	}
}

func TestGivenExpiredContext_WhenExecuteBatch_ThenTimeoutReported(t *testing.T) {
	handler := NewHandler("")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	commands := []transport.CommandRequest{
		{CommandID: "cmd-2", Type: "list_scripts"},
	}

	results := handler.ExecuteBatch(ctx, commands)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Status != transport.CommandStatusFailed || results[0].Error != "timeout" {
		t.Fatalf("expected timeout failure, got status=%s error=%s", results[0].Status, results[0].Error)
	}
}
