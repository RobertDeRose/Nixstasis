// Package e2e provides a lightweight client-side E2E harness.
package e2e

import (
	"fmt"
	"os"
	"strings"

	"go.yaml.in/yaml/v3"
)

// Config defines configuration for E2E runs.
type Config struct {
	APIURL          string
	BaseDomain      string
	Suite           string
	Environment     string
	Trigger         string
	ProtocolVersion string
	RunnerID        string
	RunnerToken     string
	IdempotencyKey  string
	Journeys        []string
	LogDir          string
	ReportDir       string
	StaryDir        string
}

type rawConfig struct {
	API struct {
		URL string `yaml:"url"`
	} `yaml:"api"`
	E2E struct {
		BaseDomain      string   `yaml:"base_domain"`
		Suite           string   `yaml:"suite"`
		Environment     string   `yaml:"environment"`
		Trigger         string   `yaml:"trigger"`
		ProtocolVersion string   `yaml:"protocol_version"`
		RunnerID        string   `yaml:"runner_id"`
		IdempotencyKey  string   `yaml:"idempotency_key"`
		Journeys        []string `yaml:"journeys"`
		LogDir          string   `yaml:"log_dir"`
		ReportDir       string   `yaml:"report_dir"`
		StaryDir        string   `yaml:"stary_dir"`
	} `yaml:"e2e"`
}

// LoadConfig reads E2E config from a YAML file.
func LoadConfig(path string) (Config, error) {
	// #nosec G304 -- path is provided by trusted CLI/config inputs.
	content, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config: %w", err)
	}

	var raw rawConfig
	if err := yaml.Unmarshal(content, &raw); err != nil {
		return Config{}, fmt.Errorf("parse config: %w", err)
	}

	protocolVersion := raw.E2E.ProtocolVersion
	if protocolVersion == "" {
		protocolVersion = "1"
	}

	baseDomain := raw.E2E.BaseDomain
	if baseDomain == "" {
		baseDomain = "devices.example.com"
	}

	cfg := Config{
		APIURL:          raw.API.URL,
		BaseDomain:      baseDomain,
		Suite:           raw.E2E.Suite,
		Environment:     raw.E2E.Environment,
		Trigger:         raw.E2E.Trigger,
		ProtocolVersion: protocolVersion,
		RunnerID:        firstNonEmpty(strings.TrimSpace(os.Getenv("NIXSTASIS_E2E_RUNNER_ID")), raw.E2E.RunnerID),
		RunnerToken:     strings.TrimSpace(os.Getenv("NIXSTASIS_E2E_RUNNER_TOKEN")),
		IdempotencyKey:  raw.E2E.IdempotencyKey,
		Journeys:        raw.E2E.Journeys,
		LogDir:          raw.E2E.LogDir,
		ReportDir:       raw.E2E.ReportDir,
		StaryDir:        raw.E2E.StaryDir,
	}

	return cfg, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}
