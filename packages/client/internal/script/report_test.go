package script

import "testing"

func TestReportEnvelope(t *testing.T) {
	result := ScriptResult{
		ScriptName:       "example",
		Status:           StatusSuccess,
		ValidationStatus: ValidationValid,
		DurationMs:       123,
		Output:           map[string]any{"value": "ok"},
	}

	report := ToReport(result)
	data, ok := report.Data.(map[string]any)
	if !ok {
		t.Fatalf("expected map data")
	}
	if data["status"] != StatusSuccess {
		t.Fatalf("expected status success")
	}
	if data["validation_status"] != ValidationValid {
		t.Fatalf("expected validation status valid")
	}
}
