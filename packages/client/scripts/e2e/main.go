// Package main provides the E2E harness CLI entrypoint.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/e2e"
)

type cliOptions struct {
	configPath       string
	apiURL           string
	suite            string
	environment      string
	trigger          string
	protocolVersion  string
	idempotencyKey   string
	journey          string
	journeys         string
	journeySelection bool
}

func main() {
	opts := parseFlags()

	cfg, err := e2e.LoadConfig(opts.configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}

	journeySelectionProvided := applyOverrides(&cfg, opts)

	if cfg.Suite == "runtime" && !journeySelectionProvided {
		cfg.Journeys = []string{
			"runtime_linux_telemetry",
			"runtime_transport_contract",
			"runtime_transport_negative",
		}
	}

	runner := e2e.NewRunner(cfg)
	summary, err := runner.RunSuite(context.Background(), cfg.Journeys)
	if err != nil {
		fmt.Fprintf(os.Stderr, "run failed: %v\n", err)
		os.Exit(1)
	}

	payload, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to encode summary: %v\n", err)
		os.Exit(1)
	}

	fmt.Println(string(payload))
}

func parseFlags() cliOptions {
	configPath := flag.String("config", "scripts/e2e/config.example.yaml", "path to e2e config")
	apiURL := flag.String("api-url", "", "base API URL")
	suite := flag.String("suite", "", "suite id")
	environment := flag.String("env", "", "environment label")
	trigger := flag.String("trigger", "", "trigger source (manual|ci)")
	protocolVersion := flag.String("protocol-version", "", "E2E protocol version header")
	idempotencyKey := flag.String("idempotency-key", "", "optional idempotency key for run creation")
	journey := flag.String("journey", "", "single journey id")
	journeys := flag.String("journeys", "", "comma-separated journey ids")
	flag.Parse()

	return cliOptions{
		configPath:      *configPath,
		apiURL:          *apiURL,
		suite:           *suite,
		environment:     *environment,
		trigger:         *trigger,
		protocolVersion: *protocolVersion,
		idempotencyKey:  *idempotencyKey,
		journey:         *journey,
		journeys:        *journeys,
	}
}

func applyOverrides(cfg *e2e.Config, opts cliOptions) bool {
	if opts.apiURL != "" {
		cfg.APIURL = opts.apiURL
	}
	if opts.suite != "" {
		cfg.Suite = opts.suite
	}
	if opts.environment != "" {
		cfg.Environment = opts.environment
	}
	if opts.trigger != "" {
		cfg.Trigger = opts.trigger
	}
	if opts.protocolVersion != "" {
		cfg.ProtocolVersion = opts.protocolVersion
	}
	if opts.idempotencyKey != "" {
		cfg.IdempotencyKey = opts.idempotencyKey
	}

	if opts.journey != "" {
		cfg.Journeys = []string{opts.journey}
		opts.journeySelection = true
	}
	if opts.journeys != "" {
		cfg.Journeys = parseJourneyList(opts.journeys)
		opts.journeySelection = true
	}

	return opts.journeySelection
}

func parseJourneyList(raw string) []string {
	parts := strings.Split(raw, ",")
	clean := make([]string, 0, len(parts))
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			clean = append(clean, trimmed)
		}
	}
	return clean
}
