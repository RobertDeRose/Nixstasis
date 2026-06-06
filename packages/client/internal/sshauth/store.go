package sshauth

import (
	"errors"
	"sync"
	"time"
)

// Entry is an in-memory terminal SSH authorization.
type Entry struct {
	Key        AuthorizedKey
	TargetUser string
	CommandID  string
	SessionRef string
	IssuedAt   time.Time
	ExpiresAt  time.Time
}

// Store keeps ephemeral SSH authorizations in process memory only.
type Store struct {
	mu      sync.RWMutex
	entries map[string]Entry
	now     func() time.Time
}

// NewStore creates an empty authorization store.
func NewStore() *Store {
	return &Store{entries: make(map[string]Entry), now: time.Now}
}

// NewStoreWithClock creates an empty store with a test-controlled clock.
func NewStoreWithClock(now func() time.Time) *Store {
	if now == nil {
		now = time.Now
	}
	return &Store{entries: make(map[string]Entry), now: now}
}

// Add stores a key for targetUser until now+ttl.
func (s *Store) Add(publicKey, targetUser, commandID, sessionRef string, ttl time.Duration) (Entry, error) {
	if s == nil {
		return Entry{}, errors.New("ssh authorization store is not configured")
	}
	if targetUser == "" {
		return Entry{}, errors.New("target_user is required")
	}
	if ttl <= 0 {
		return Entry{}, errors.New("ttl_seconds must be positive")
	}
	key, err := ParseAuthorizedKeyLine(publicKey)
	if err != nil {
		return Entry{}, err
	}
	now := s.now().UTC()
	entry := Entry{Key: key, TargetUser: targetUser, CommandID: commandID, SessionRef: sessionRef, IssuedAt: now, ExpiresAt: now.Add(ttl)}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeExpiredLocked(now)
	s.entries[entryKey(targetUser, key.Type, key.Blob)] = entry
	return entry, nil
}

// Authorize returns the canonical key line if the offered key is currently allowed for targetUser.
func (s *Store) Authorize(targetUser, keyType, keyBlob string) (AuthorizedKey, bool) {
	if s == nil || targetUser == "" {
		return AuthorizedKey{}, false
	}
	key, err := ParseOfferedKey(keyType, keyBlob)
	if err != nil {
		return AuthorizedKey{}, false
	}
	now := s.now().UTC()
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeExpiredLocked(now)
	entry, ok := s.entries[entryKey(targetUser, key.Type, key.Blob)]
	if !ok || !entry.ExpiresAt.After(now) {
		return AuthorizedKey{}, false
	}
	return entry.Key, true
}

// RevokeCommand removes all entries associated with commandID.
func (s *Store) RevokeCommand(commandID string) int {
	if s == nil || commandID == "" {
		return 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deleteMatchingLocked(func(entry Entry) bool { return entry.CommandID == commandID })
}

// RevokeSession removes all entries associated with sessionRef.
func (s *Store) RevokeSession(sessionRef string) int {
	if s == nil || sessionRef == "" {
		return 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.deleteMatchingLocked(func(entry Entry) bool { return entry.SessionRef == sessionRef })
}

// RevokeAll removes every entry from the store. Intended for tests and for
// the dev-lab ssh terminal smoke flow.
func (s *Store) RevokeAll() int {
	if s == nil {
		return 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now().UTC()
	s.purgeExpiredLocked(now)
	count := len(s.entries)
	s.entries = make(map[string]Entry)
	return count
}

// Len returns the current non-expired entry count.
func (s *Store) Len() int {
	if s == nil {
		return 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.purgeExpiredLocked(s.now().UTC())
	return len(s.entries)
}

func (s *Store) deleteMatchingLocked(match func(Entry) bool) int {
	count := 0
	for key := range s.entries {
		entry := s.entries[key]
		if match(entry) {
			delete(s.entries, key)
			count++
		}
	}
	return count
}

func (s *Store) purgeExpiredLocked(now time.Time) {
	for key := range s.entries {
		entry := s.entries[key]
		if !entry.ExpiresAt.After(now) {
			delete(s.entries, key)
		}
	}
}

func entryKey(targetUser, keyType, keyBlob string) string {
	return targetUser + "\x00" + keyType + "\x00" + keyBlob
}
