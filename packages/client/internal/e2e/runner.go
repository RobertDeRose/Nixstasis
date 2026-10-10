package e2e

import (
	"context"
	"errors"
	"fmt"
)

// Runner executes client/server E2E journeys.
type Runner struct {
	cfg Config
}

const (
	statusPassed = "passed"
	statusFailed = "failed"
)

// JourneyResult captures a single journey execution outcome.
type JourneyResult struct {
	JourneyID  string
	Status     string
	Error      string
	DurationMs int64
}

// RunSummary captures a full run summary.
type RunSummary struct {
	RunID    string
	Status   string
	Journeys []JourneyResult
}

// NewRunner constructs a new Runner.
func NewRunner(cfg Config) *Runner {
	return &Runner{
		cfg: cfg,
	}
}

// RunSuite executes a full suite or a selected subset of journeys.
func (r *Runner) RunSuite(ctx context.Context, journeyIDs []string) (*RunSummary, error) {
	if ctx == nil {
		return nil, errors.New("context is required")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := r.validateConfig(); err != nil {
		return nil, err
	}

	journeys := journeyIDs
	if len(journeys) == 0 {
		journeys = r.cfg.Journeys
	}

	if len(journeys) == 0 {
		return nil, fmt.Errorf("no journeys selected")
	}

	api, err := newAPIClient(r.cfg)
	if err != nil {
		return nil, err
	}
	run, err := api.createRun(ctx, runCreateRequest{
		SuiteID:          r.cfg.Suite,
		JourneyIDs:       journeys,
		EnvironmentLabel: r.cfg.Environment,
		TriggerSource:    r.cfg.Trigger,
		IdempotencyKey:   r.cfg.IdempotencyKey,
		ProtocolVersion:  r.cfg.ProtocolVersion,
	})
	if err != nil {
		return nil, err
	}

	results := make([]JourneyResult, 0, len(journeys))
	payloads := make([]resultPayload, 0, len(journeys))
	for index, journey := range journeys {
		result, payload := r.executeJourney(ctx, run, journey, index+1)
		results = append(results, result)
		payloads = append(payloads, payload)
	}

	if err := api.submitResults(ctx, run.ID, payloads); err != nil {
		return nil, err
	}

	return &RunSummary{
		RunID:    run.ID,
		Status:   summarizeStatus(results),
		Journeys: results,
	}, nil
}

func (r *Runner) validateConfig() error {
	switch {
	case r.cfg.APIURL == "":
		return errors.New("API url is required")
	case r.cfg.Suite == "":
		return errors.New("suite is required")
	case r.cfg.Environment == "":
		return errors.New("environment is required")
	case r.cfg.Trigger == "":
		return errors.New("trigger is required")
	case r.cfg.ProtocolVersion == "":
		return errors.New("protocol version is required")
	case r.cfg.RunnerID == "":
		return errors.New("E2E runner id is required")
	case len(r.cfg.RunnerToken) < 32:
		return errors.New("E2E runner token must be at least 32 bytes")
	}
	return nil
}

func summarizeStatus(results []JourneyResult) string {
	statuses := map[string]int{}
	for _, result := range results {
		statuses[result.Status]++
	}

	switch {
	case statuses[statusFailed] > 0:
		return statusFailed
	case statuses["queued"] > 0 || statuses["running"] > 0:
		return "running"
	case statuses["blocked"] > 0 || statuses["skipped"] > 0:
		return "blocked"
	default:
		return statusPassed
	}
}
