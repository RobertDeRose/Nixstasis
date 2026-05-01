package main

import (
	"testing"

	"go.starlark.net/starlark"
)

func TestGivenReplCommand_WhenRun_ThenBuiltinsAvailable(t *testing.T) {
	original := startREPL
	defer func() { startREPL = original }()

	var globals starlark.StringDict
	startREPL = func(g starlark.StringDict) error {
		globals = g
		return nil
	}

	if err := replCmd.RunE(replCmd, []string{}); err != nil {
		t.Fatalf("expected repl to start, got error: %v", err)
	}

	if _, ok := globals["pub_and_get"]; !ok {
		t.Fatalf("expected pub_and_get builtin to be available")
	}
	if _, ok := globals["exec_cmd"]; !ok {
		t.Fatalf("expected exec_cmd builtin to be available")
	}
}
