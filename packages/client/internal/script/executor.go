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
	results := make(chan ScriptResult, len(scripts))
	var wg sync.WaitGroup

	for _, script := range scripts {
		wg.Add(1)
		go func(info ScriptInfo) {
			defer wg.Done()
			results <- e.executeScript(ctx, info)
		}(script)
	}

	wg.Wait()
	close(results)

	mapped := make(map[string]ScriptResult)
	for res := range results {
		if res.ScriptName == "" {
			continue
		}
		mapped[res.ScriptName] = res
	}

	return mapped, nil
}

func (e *Executor) executeScript(ctx context.Context, info ScriptInfo) ScriptResult {
	rt := NewRuntime(e.config)
	defer func() {
		if err := rt.Close(); err != nil {
			slog.Debug("Failed to close runtime", "error", err)
		}
	}()

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
