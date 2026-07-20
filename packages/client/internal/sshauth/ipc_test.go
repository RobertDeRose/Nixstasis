package sshauth

import (
	"errors"
	"os/user"
	"strings"
	"testing"
)

func TestChownSocketGroupIgnoresMissingOptionalGroup(t *testing.T) {
	err := chownSocketGroupWith(
		"/run/nixstasis/ssh-authority.sock",
		func(string) (*user.Group, error) { return nil, user.UnknownGroupError("nixstasis-ssh") },
		func(string, int, int) error { return nil },
	)
	if err != nil {
		t.Fatalf("chownSocketGroupWith() error = %v, want nil", err)
	}
}

func TestChownSocketGroupReturnsLookupFailure(t *testing.T) {
	want := errors.New("lookup failed")

	err := chownSocketGroupWith(
		"/run/nixstasis/ssh-authority.sock",
		func(string) (*user.Group, error) { return nil, want },
		func(string, int, int) error { return nil },
	)

	if err == nil || !strings.Contains(err.Error(), want.Error()) {
		t.Fatalf("chownSocketGroupWith() error = %v, want error containing %q", err, want)
	}
}

func TestChownSocketGroupReturnsChownFailure(t *testing.T) {
	want := errors.New("permission denied")

	err := chownSocketGroupWith(
		"/run/nixstasis/ssh-authority.sock",
		func(string) (*user.Group, error) { return &user.Group{Gid: "123"}, nil },
		func(string, int, int) error { return want },
	)

	if err == nil || !strings.Contains(err.Error(), want.Error()) {
		t.Fatalf("chownSocketGroupWith() error = %v, want error containing %q", err, want)
	}
}
