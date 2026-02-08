package script

import (
	"errors"
	"log/slog"

	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

func statusFromError(err error) ExecutionStatus {
	if errors.Is(err, ErrTimeout) {
		return StatusTimeout
	}
	return StatusError
}

func mapError(err error) *ScriptError {
	if err == nil {
		return nil
	}

	if errors.Is(err, ErrTimeout) {
		return &ScriptError{Type: ErrorTimeout, Message: err.Error()}
	}

	var syntaxErr *syntax.Error
	if errors.As(err, &syntaxErr) {
		return &ScriptError{Type: ErrorSyntax, Message: err.Error()}
	}

	var evalErr *starlark.EvalError
	if errors.As(err, &evalErr) {
		return &ScriptError{Type: ErrorExecution, Message: err.Error()}
	}

	slog.Debug("Unhandled script error", "error", err)
	return &ScriptError{Type: ErrorIO, Message: err.Error()}
}
