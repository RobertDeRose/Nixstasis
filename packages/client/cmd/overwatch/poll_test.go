package main

import (
	"context"
	"testing"

	"github.com/sfero-nixstasis/client/internal/transport"
)

type fakeCommandHandler struct {
	called  bool
	results []transport.CommandResult
}

func (f *fakeCommandHandler) ExecuteBatch(_ context.Context, _ []transport.CommandRequest) []transport.CommandResult {
	f.called = true
	return f.results
}

type fakeCommandClient struct {
	called  bool
	results []transport.CommandResult
}

func (f *fakeCommandClient) SendCommandResults(_ context.Context, _ string, results []transport.CommandResult) error {
	f.called = true
	f.results = results
	return nil
}

func TestGivenCommands_WhenHandleCommandResponses_ThenResultsSent(t *testing.T) {
	handler := &fakeCommandHandler{
		results: []transport.CommandResult{
			{CommandID: "cmd-1", Status: transport.CommandStatusOK},
		},
	}
	client := &fakeCommandClient{}
	commands := []transport.CommandRequest{{CommandID: "cmd-1", Type: "list_scripts"}}

	if err := handleCommandResponses(context.Background(), client, nil, handler, "device-1", commands); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !handler.called {
		t.Fatalf("expected handler to be called")
	}
	if !client.called {
		t.Fatalf("expected client to be called")
	}
	if len(client.results) != 1 || client.results[0].CommandID != "cmd-1" {
		t.Fatalf("unexpected results: %+v", client.results)
	}
}
