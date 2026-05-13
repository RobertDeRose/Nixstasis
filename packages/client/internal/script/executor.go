package script

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"
	"sync"
	"time"
)

// maxConcurrentScripts limits the number of scripts executing in parallel
// to avoid exhausting file descriptors, subprocess limits, or MQTT connections.
const maxConcurrentScripts = 20

// Executor runs scripts and returns structured results.
type Executor struct {
	config RuntimeConfig
}

// NewExecutor constructs an Executor with the provided runtime configuration.
func NewExecutor(config RuntimeConfig) *Executor {
	return &Executor{config: config}
}

// ExecuteScripts runs all scripts and returns a result map keyed by script name.
func (e *Executor) ExecuteScripts(ctx context.Context, scripts []ScriptInfo) (map[string]ScriptResult, error) {
	// Share a single Runtime (and thus a single MQTT connection) across all
	// script executions within this poll cycle.
	rt := NewRuntime(e.config)
	defer func() {
		if err := rt.Close(); err != nil {
			slog.Debug("Failed to close shared runtime", "error", err)
		}
	}()

	results := make(chan ScriptResult, len(scripts))
	jobs := make(chan ScriptInfo, len(scripts))
	var wg sync.WaitGroup

	workerCount := min(maxConcurrentScripts, len(scripts))
	for range workerCount {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for info := range jobs {
				select {
				case <-ctx.Done():
					results <- canceledScriptResult(info)
				default:
					results <- e.executeScript(ctx, rt, info)
				}
			}
		}()
	}

	for _, script := range scripts {
		jobs <- script
	}
	close(jobs)

	wg.Wait()
	close(results)

	mapped := make(map[string]ScriptResult)
	var errs []error
	for res := range results {
		if res.ScriptName == "" {
			continue
		}
		mapped[res.ScriptName] = res
		if res.Error != nil {
			errs = append(errs, fmt.Errorf("%s: %s", res.ScriptName, res.Error.Message))
		}
	}

	return mapped, errors.Join(errs...)
}

func canceledScriptResult(info ScriptInfo) ScriptResult {
	name := info.Name
	if name == "" {
		fm, _, err := ParseStaryFile(info.Path)
		if err == nil && fm.Name != "" {
			name = fm.Name
		} else {
			name = filepath.Base(info.Path)
		}
	}

	return ScriptResult{
		ScriptName:       name,
		Status:           StatusTimeout,
		ValidationStatus: ValidationSkipped,
		Error:            &ScriptError{Type: ErrorTimeout, Message: ErrTimeout.Error()},
	}
}

func (e *Executor) executeScript(ctx context.Context, rt *Runtime, info ScriptInfo) ScriptResult {
	start := time.Now()
	result := ScriptResult{ScriptName: info.Name, ValidationStatus: ValidationSkipped}

	fm, body, err := ParseStaryFile(info.Path)
	if err != nil {
		if result.ScriptName == "" {
			result.ScriptName = filepath.Base(info.Path)
		}
		return e.finalizeResult(result, start, StatusError, mapError(err))
	}

	if fm.Name != "" {
		result.ScriptName = fm.Name
	} else if result.ScriptName == "" {
		result.ScriptName = filepath.Base(info.Path)
	}

	schema, err := CompileSchema(fm.Schema)
	if err != nil {
		return e.finalizeResult(result, start, StatusError, &ScriptError{Type: ErrorValidation, Message: err.Error()})
	}

	output, err := rt.Execute(ctx, info.Path, body)
	if err != nil {
		return e.finalizeResult(result, start, statusFromError(err), mapError(err))
	}

	if err := ValidateOutput(schema, output); err != nil {
		result.ValidationStatus = ValidationInvalid
		return e.finalizeResult(result, start, StatusError, validationError(err))
	}

	result.Status = StatusSuccess
	result.ValidationStatus = ValidationValid
	result.Output = output
	return e.finalizeResult(result, start, StatusSuccess, nil)
}

func validationError(err error) *ScriptError {
	if err == nil {
		return nil
	}

	var detailsErr *ValidationDetailsError
	if errors.As(err, &detailsErr) {
		return &ScriptError{
			Type:    ErrorValidation,
			Message: detailsErr.Summary,
			Details: ValidationErrorDetails{
				Simple:  detailsErr.Simple,
				Verbose: detailsErr.Verbose,
			},
		}
	}

	return &ScriptError{
		Type:    ErrorValidation,
		Message: err.Error(),
	}
}

func (e *Executor) finalizeResult(result ScriptResult, start time.Time, status ExecutionStatus, err *ScriptError) ScriptResult {
	result.Status = status
	result.Error = err
	result.DurationMs = time.Since(start).Milliseconds()

	if result.DurationMs > e.config.WarnAfter.Milliseconds() {
		result.Warnings = append(result.Warnings, ScriptWarning{
			Type:       WarningSlowExecution,
			Message:    fmt.Sprintf("script took %dms", result.DurationMs),
			DurationMs: result.DurationMs,
		})
	}

	return result
}
