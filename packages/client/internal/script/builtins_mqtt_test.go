package script

import (
	"strings"
	"testing"
	"time"

	"go.starlark.net/starlark"
)

func TestMQTTTopicRestrictions(t *testing.T) {
	allowed := []string{"devices/+/request", "broadcast/#"}

	if !topicAllowed("devices/device-1/request", allowed) {
		t.Fatalf("expected single-level wildcard to allow topic")
	}
	if !topicAllowed("broadcast/a/b", allowed) {
		t.Fatalf("expected multi-level wildcard to allow topic")
	}
	if topicAllowed("devices/device-1/response", allowed) {
		t.Fatalf("expected unmatched topic to be rejected")
	}
}

func TestPubAndGetRequiresMQTTCapability(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{Timeout: 5 * time.Second})
	_, err := runtime.Execute(t.Context(), "test.star", `
def main():
    return {"out": pub_and_get(topic="a", msg="b")}
`)
	if err == nil || !strings.Contains(err.Error(), "capability is not configured") {
		t.Fatalf("expected capability error, got %v", err)
	}
}

func TestAcceptCriteriaMatchesOnlyExpectedKeyValues(t *testing.T) {
	accept := starlark.NewDict(2)
	if err := accept.SetKey(starlark.String("status"), starlark.String("ok")); err != nil {
		t.Fatalf("set accept status: %v", err)
	}
	if err := accept.SetKey(starlark.String("count"), starlark.MakeInt(2)); err != nil {
		t.Fatalf("set accept count: %v", err)
	}
	criteria, err := parseAcceptCriteria(accept)
	if err != nil {
		t.Fatalf("parseAcceptCriteria failed: %v", err)
	}

	if responseMatchesAccept([]byte(`{"status":"pending","count":2}`), criteria) {
		t.Fatalf("expected non-matching response to be ignored")
	}
	if !responseMatchesAccept([]byte(`{"status":"ok","count":2,"secret":"still-returned"}`), criteria) {
		t.Fatalf("expected matching response to be accepted")
	}
}

func TestParseAcceptCriteriaRejectsNestedSelectors(t *testing.T) {
	accept := starlark.NewDict(1)
	if err := accept.SetKey(starlark.String("status.ok"), starlark.String("ready")); err != nil {
		t.Fatalf("set accept key: %v", err)
	}
	if _, err := parseAcceptCriteria(accept); err == nil {
		t.Fatalf("expected nested accept selector to fail")
	}
}
