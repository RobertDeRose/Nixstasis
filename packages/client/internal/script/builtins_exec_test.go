package script

import "testing"

func TestAllowedCommand(t *testing.T) {
	allowlist := []string{"echo", "smartctl", "nixstasis."}
	if !allowedCommand("echo", allowlist) {
		t.Fatalf("expected echo to be allowed")
	}
	if !allowedCommand("/usr/bin/smartctl", allowlist) {
		t.Fatalf("expected smartctl path to be allowed")
	}
	if !allowedCommand("nixstasis.helper", allowlist) {
		t.Fatalf("expected prefix match to be allowed")
	}
	if allowedCommand("rm", allowlist) {
		t.Fatalf("did not expect rm to be allowed")
	}
	if allowedCommand("echo", nil) {
		t.Fatalf("did not expect commands to be allowed by default")
	}
}
