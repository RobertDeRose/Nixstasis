package main

import (
	"log/slog"
	"os"
	"time"

	"github.com/sfero-nixstasis/client/internal/script"
	"github.com/spf13/cobra"
	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

var startREPL = func(globals starlark.StringDict) error {
	thread := &starlark.Thread{
		Name: "REPL",
		Load: script.MakeLoadOptions(&syntax.FileOptions{}),
	}
	script.REPLOptions(&syntax.FileOptions{}, thread, globals)
	return nil
}

var replCmd = &cobra.Command{
	Use:   "repl",
	Short: "Start an interactive Starlark REPL with builtins",
	RunE: func(_ *cobra.Command, _ []string) error {
		return runREPL()
	},
}

func init() {
	scriptCmd.AddCommand(replCmd)
}

func runREPL() error {
	runtime := script.NewRuntime(script.RuntimeConfig{
		Timeout:    5 * time.Second,
		WarnAfter:  3 * time.Second,
		MQTTBroker: os.Getenv("NIXSTASIS_MQTT_BROKER"),
	})
	defer func() {
		if err := runtime.Close(); err != nil {
			slog.Debug("Failed to close REPL runtime", "error", err)
		}
	}()

	return startREPL(runtime.Builtins())
}
