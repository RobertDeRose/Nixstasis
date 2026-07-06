package script

import "time"

// ScriptInfo describes a discovered stary script on disk.
//
//revive:disable-next-line:exported
type ScriptInfo struct {
	Name    string
	Version string
	Path    string
}

// ExecutionStatus describes the outcome of a script execution.
type ExecutionStatus string

// ValidationStatus describes schema validation results.
type ValidationStatus string

// ScriptErrorType identifies error categories for script execution.
//
//revive:disable-next-line:exported
type ScriptErrorType string

// ScriptWarningType identifies warning categories for script execution.
//
//revive:disable-next-line:exported
type ScriptWarningType string

const (
	// StatusSuccess indicates successful execution.
	StatusSuccess ExecutionStatus = "success"
	// StatusError indicates execution failure.
	StatusError ExecutionStatus = "error"
	// StatusTimeout indicates execution timeout.
	StatusTimeout ExecutionStatus = "timeout"

	// ValidationValid indicates the output passed schema validation.
	ValidationValid ValidationStatus = "valid"
	// ValidationInvalid indicates schema validation failure.
	ValidationInvalid ValidationStatus = "invalid"
	// ValidationSkipped indicates validation was not performed.
	ValidationSkipped ValidationStatus = "skipped"

	// ErrorSyntax indicates a syntax error.
	ErrorSyntax ScriptErrorType = "syntax"
	// ErrorExecution indicates a runtime execution error.
	ErrorExecution ScriptErrorType = "execution"
	// ErrorValidation indicates a schema validation error.
	ErrorValidation ScriptErrorType = "validation"
	// ErrorTimeout indicates a timeout error.
	ErrorTimeout ScriptErrorType = "timeout"
	// ErrorIO indicates an IO-related error.
	ErrorIO ScriptErrorType = "io"

	// WarningSlowExecution indicates the script ran slower than expected.
	WarningSlowExecution ScriptWarningType = "slow_execution"
)

// ScriptError contains details about a script failure.
//
//revive:disable-next-line:exported
type ScriptError struct {
	Type    ScriptErrorType `json:"type"`
	Message string          `json:"message"`
	Details any             `json:"details,omitempty"`
}

// ValidationErrorDetails captures formatted output for schema failures.
//
//revive:disable-next-line:exported
type ValidationErrorDetails struct {
	Simple  string `json:"simple"`
	Verbose string `json:"verbose,omitempty"`
}

// ScriptWarning captures non-fatal issues like slow execution.
//
//revive:disable-next-line:exported
type ScriptWarning struct {
	Type       ScriptWarningType `json:"type"`
	Message    string            `json:"message"`
	DurationMs int64             `json:"duration_ms"`
}

// ScriptResult is the normalized result of executing a script.
//
//revive:disable-next-line:exported
type ScriptResult struct {
	ScriptName       string           `json:"script_name"`
	Status           ExecutionStatus  `json:"status"`
	ValidationStatus ValidationStatus `json:"validation_status"`
	DurationMs       int64            `json:"duration_ms"`
	Output           map[string]any   `json:"output,omitempty"`
	Error            *ScriptError     `json:"error,omitempty"`
	Warnings         []ScriptWarning  `json:"warnings,omitempty"`
}

// FrontMatter describes the YAML header of a stary file.
type FrontMatter struct {
	Name    string         `yaml:"name"`
	Version string         `yaml:"version,omitempty"`
	Schema  map[string]any `yaml:"schema"`
}

// RuntimeConfig configures script execution behavior.
type RuntimeConfig struct {
	Timeout              time.Duration
	WarnAfter            time.Duration
	MQTTBroker           string
	ExecCommandAllowlist map[string]string
	CommandPolicyVersion string
	ExecWorkDir          string
	ExecEnv              []string
	ExecUser             *ExecUser
	MQTTPublishTopics    []string
	MQTTSubscribeTopics  []string
}

// ExecUser specifies a restricted UID/GID for exec_cmd.
type ExecUser struct {
	UID uint32
	GID uint32
}
