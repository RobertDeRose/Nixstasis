package sshauth

import (
	"testing"
	"time"
)

func TestStoreRemovesExpiredEntriesWithoutLookup(t *testing.T) {
	store := NewStore()
	if _, err := store.Add(testAuthorizedKey, "nixstasis-support", "command-1", "session-1", 25*time.Millisecond); err != nil {
		t.Fatalf("Store.Add() error = %v", err)
	}

	deadline := time.NewTimer(time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			store.mu.RLock()
			remaining := len(store.entries)
			store.mu.RUnlock()
			if remaining == 0 {
				key, err := ParseAuthorizedKeyLine(testAuthorizedKey)
				if err != nil {
					t.Fatalf("ParseAuthorizedKeyLine() error = %v", err)
				}
				if _, ok := store.Authorize("nixstasis-support", key.Type, key.Blob); ok {
					t.Fatal("expired authorization remained authorized")
				}
				return
			}
		case <-deadline.C:
			t.Fatal("expired authorization remained in the store without a lookup")
		}
	}
}
