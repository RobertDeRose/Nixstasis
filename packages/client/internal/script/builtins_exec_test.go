package script

import "testing"

func TestBlockedCommand(t *testing.T) {
	blacklist := []string{"rm", "mkfs", "mkfs."}
	if !blockedCommand("rm", blacklist) {
		t.Fatalf("expected rm to be blocked")
	}
	if !blockedCommand("mkfs.ext4", blacklist) {
		t.Fatalf("expected mkfs.ext4 to be blocked")
	}
	if blockedCommand("echo", blacklist) {
		t.Fatalf("did not expect echo to be blocked")
	}
}
