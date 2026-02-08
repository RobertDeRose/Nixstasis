package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/sfero-nixstasis/client/internal/script"
	"github.com/spf13/cobra"
	"go.yaml.in/yaml/v3"
)

const (
	colorRed     = "\033[31m"
	colorGreen   = "\033[32m"
	colorMagenta = "\033[35m"
	colorReset   = "\033[0m"
)

var testScriptCmd = &cobra.Command{
	Use:          "test <path>",
	Short:        "Execute a stary script and print YAML output",
	Args:         cobra.ExactArgs(1),
	SilenceUsage: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runTestScript(cmd, args[0])
	},
}

var testScriptVerbose bool

func init() {
	testScriptCmd.Flags().BoolVar(&testScriptVerbose, "verbose", false, "show verbose schema validation details")
	scriptCmd.AddCommand(testScriptCmd)
}

func runTestScript(cmd *cobra.Command, path string) error {
	out := cmd.OutOrStdout()
	info, err := script.ResolveScript(path, nil)
	if err != nil {
		return err
	}

	executor := script.NewExecutor(script.RuntimeConfig{
		Timeout:    5 * time.Second,
		WarnAfter:  3 * time.Second,
		MQTTBroker: os.Getenv("NIXSTASIS_MQTT_BROKER"),
	})

	results, err := executor.ExecuteScripts(context.Background(), []script.ScriptInfo{info})
	if err != nil {
		return err
	}

	result, ok := results[info.Name]
	if !ok {
		return fmt.Errorf("no result for script: %s", info.Name)
	}

	if result.Status != script.StatusSuccess {
		return formatScriptFailure(result)
	}

	payload, err := yaml.Marshal(result.Output)
	if err != nil {
		return err
	}

	_, err = bytes.NewBuffer(payload).WriteTo(out)
	return err
}

func formatScriptFailure(result script.ScriptResult) error {
	if result.Error == nil || result.Error.Message == "" {
		return fmt.Errorf("script failed: unknown error")
	}

	if result.Error.Type == script.ErrorValidation {
		return formatValidationFailure(result.Error)
	}

	return fmt.Errorf("script failed: %s", result.Error.Message)
}

type outputValidationError struct {
	details string
	message string
}

func (e *outputValidationError) Error() string {
	switch {
	case e.details != "":
		return colorMagenta + "Output validation failed:" + colorReset + "\n" + e.details
	case e.message != "":
		return colorMagenta + "Output validation failed:" + colorReset + " " + e.message
	default:
		return colorMagenta + "Output validation failed" + colorReset
	}
}

func formatValidationFailure(err *script.ScriptError) error {
	if err == nil {
		return &outputValidationError{}
	}

	switch details := err.Details.(type) {
	case script.ValidationErrorDetails:
		text := details.Simple
		if testScriptVerbose && details.Verbose != "" {
			text = details.Verbose
		}
		if text != "" {
			return &outputValidationError{details: colorizeValidationDetails(text)}
		}
	case *script.ValidationErrorDetails:
		if details != nil {
			text := details.Simple
			if testScriptVerbose && details.Verbose != "" {
				text = details.Verbose
			}
			if text != "" {
				return &outputValidationError{details: colorizeValidationDetails(text)}
			}
		}
	}

	if err.Message != "" {
		return &outputValidationError{message: friendlyValidationMessage(err.Message)}
	}
	return &outputValidationError{}
}

func friendlyValidationMessage(message string) string {
	trimmed := strings.TrimSpace(message)
	trimmed = strings.TrimPrefix(trimmed, "schema validation failed: ")
	trimmed = strings.TrimPrefix(trimmed, "jsonschema: ")

	const token = "does not validate with "
	if _, after, ok := strings.Cut(trimmed, token); ok {
		rest := after
		if _, after, ok := strings.Cut(rest, ": "); ok {
			return strings.TrimSpace(after)
		}
	}

	return strings.TrimSpace(trimmed)
}

func colorizeValidationDetails(details string) string {
	if details == "" {
		return details
	}

	lines := strings.Split(details, "\n")
	for i, line := range lines {
		lines[i] = colorizeValidationLine(line)
	}
	return strings.Join(lines, "\n")
}

func colorizeValidationLine(line string) string {
	if !strings.HasPrefix(line, "❌ ") {
		return colorMagenta + line + colorReset
	}

	rest := strings.TrimPrefix(line, "❌ ")
	path, msg, ok := strings.Cut(rest, ": ")
	if !ok {
		return colorRed + "X" + colorReset + " " + colorMagenta + rest + colorReset
	}

	base := msg
	keyword := ""
	schema := ""
	if before, after, ok := strings.Cut(msg, " (keyword: "); ok {
		base = before
		after = strings.TrimSuffix(after, ")")
		if kw, sch, ok := strings.Cut(after, ", schema: "); ok {
			keyword = strings.TrimSpace(kw)
			schema = strings.TrimSpace(sch)
		}
	}

	builder := strings.Builder{}
	builder.WriteString(colorRed + "X" + colorReset)
	builder.WriteString(" ")
	builder.WriteString(colorMagenta + path + colorReset)
	builder.WriteString(colorMagenta + ": " + colorReset)
	builder.WriteString(colorGreen + strings.TrimSpace(base) + colorReset)

	if keyword != "" || schema != "" {
		builder.WriteString(" ")
		builder.WriteString(colorMagenta + "(keyword: " + colorReset)
		builder.WriteString(colorGreen + keyword + colorReset)
		builder.WriteString(colorMagenta + ", schema: " + colorReset)
		builder.WriteString(colorGreen + schema + colorReset)
		builder.WriteString(colorMagenta + ")" + colorReset)
	}

	return builder.String()
}
