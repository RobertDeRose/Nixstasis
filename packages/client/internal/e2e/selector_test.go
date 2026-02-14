package e2e

import "testing"

func TestSelectJourneysUsesAllWhenEmpty(t *testing.T) {
	all := []string{"auth", "dashboard"}
	selected, err := SelectJourneys(all, nil)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(selected) != 2 {
		t.Fatalf("expected 2 journeys, got %d", len(selected))
	}
}

func TestSelectJourneysRejectsUnknown(t *testing.T) {
	all := []string{"auth"}
	_, err := SelectJourneys(all, []string{journeyLogout})
	if err == nil {
		t.Fatalf("expected error for unknown journey")
	}
}
