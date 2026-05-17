package e2e

import (
	"fmt"
	"os"
	"path/filepath"

	"go.yaml.in/yaml/v3"
)

type journeySpec struct {
	ID          string        `yaml:"id"`
	Description string        `yaml:"description"`
	Steps       []journeyStep `yaml:"steps"`
}

type journeyStep struct {
	StepID string `yaml:"step_id,omitempty"`
	Action string `yaml:"action"`
	Expect string `yaml:"expect"`
}

func (s journeyStep) effectiveStepID() string {
	if s.StepID != "" {
		return s.StepID
	}
	return s.Action
}

type journeyState struct {
	DeviceID             string
	DeviceToken          string
	DeviceMac            string
	ProductName          string
	ReportID             string
	AlertRuleID          string
	CommandRef           string
	ScriptsDir           string
	PollDuration         int64
	TelemetrySeen        bool
	TelemetryCountBefore int
	TelemetryCountAfter  int
	AlertCountBefore     int
	AlertCountAfter      int
}

func loadJourneySpec(journeyID string) (journeySpec, error) {
	root, err := moduleRoot()
	if err != nil {
		return journeySpec{}, err
	}

	path := filepath.Join(root, "scripts", "e2e", "journeys", fmt.Sprintf("%s.yaml", journeyID))
	// #nosec G304 -- journey specs are trusted local files packaged with the client.
	content, err := os.ReadFile(path)
	if err != nil {
		return journeySpec{}, fmt.Errorf("read journey spec: %w", err)
	}

	var spec journeySpec
	if err := yaml.Unmarshal(content, &spec); err != nil {
		return journeySpec{}, fmt.Errorf("parse journey spec: %w", err)
	}

	if spec.ID == "" {
		return journeySpec{}, fmt.Errorf("journey spec missing id")
	}
	if len(spec.Steps) == 0 {
		return journeySpec{}, fmt.Errorf("journey spec has no steps")
	}

	return spec, nil
}

func moduleRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("get working dir: %w", err)
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return "", fmt.Errorf("go.mod not found to resolve module root")
}
