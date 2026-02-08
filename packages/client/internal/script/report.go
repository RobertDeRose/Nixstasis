package script

import "github.com/sfero-nixstasis/client/internal/telemetry"

// ToReport maps a ScriptResult into the telemetry report payload.
func ToReport(result ScriptResult) telemetry.Report {
	data := map[string]any{
		"status":            result.Status,
		"validation_status": result.ValidationStatus,
		"duration_ms":       result.DurationMs,
	}

	if len(result.Warnings) > 0 {
		data["warnings"] = result.Warnings
	}
	if result.Error != nil {
		data["error"] = result.Error
	}
	if result.Output != nil {
		data["output"] = result.Output
	}

	return telemetry.Report{
		Data: data,
	}
}
