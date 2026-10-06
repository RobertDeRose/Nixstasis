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

func TestMQTTTopicRestrictionsRejectRequestedWildcards(t *testing.T) {
	tests := []struct {
		name    string
		topic   string
		allowed []string
	}{
		{
			name:    "single-level allowlist does not authorize multi-level wildcard",
			topic:   "reply/#",
			allowed: []string{"reply/+"},
		},
		{
			name:    "multi-level allowlist does not authorize single-level wildcard",
			topic:   "reply/+",
			allowed: []string{"reply/#"},
		},
		{
			name:    "exact multi-level wildcard is still not a concrete topic",
			topic:   "reply/#",
			allowed: []string{"reply/#"},
		},
		{
			name:    "embedded wildcard character is not a concrete topic",
			topic:   "reply/device+1",
			allowed: []string{"reply/#"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if topicAllowed(test.topic, test.allowed) {
				t.Fatalf("expected requested wildcard topic %q to be rejected", test.topic)
			}
		})
	}
}

func TestPubAndGetRejectsWildcardReplyTopicBeforeBroker(t *testing.T) {
	runtime := NewRuntime(RuntimeConfig{
		Timeout:             5 * time.Second,
		MQTTBroker:          "tcp://127.0.0.1:1",
		MQTTPublishTopics:   []string{"request/+"},
		MQTTSubscribeTopics: []string{"reply/+"},
	})
	_, err := runtime.Execute(t.Context(), "test.star", `
def main():
    return {"out": pub_and_get(topic="request/device-1", msg="b", reply_topic="reply/#")}
`)
	if err == nil || !strings.Contains(err.Error(), "subscribe topic is not allowed: reply/#") {
		t.Fatalf("expected wildcard reply topic rejection before broker interaction, got %v", err)
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
	criteria, err := parseAcceptCriteria(t.Context(), accept)
	if err != nil {
		t.Fatalf("parseAcceptCriteria failed: %v", err)
	}

	matches, err := responseMatchesAccept([]byte(`{"status":"pending","count":2}`), criteria)
	if err != nil {
		t.Fatalf("responseMatchesAccept returned error: %v", err)
	}
	if matches {
		t.Fatalf("expected non-matching response to be ignored")
	}

	matches, err = responseMatchesAccept([]byte(`{"status":"ok","count":2,"secret":"still-returned"}`), criteria)
	if err != nil {
		t.Fatalf("responseMatchesAccept returned error: %v", err)
	}
	if !matches {
		t.Fatalf("expected matching response to be accepted")
	}
}

func TestResponseMatchesAcceptIgnoresMalformedReplies(t *testing.T) {
	for _, payload := range []string{`{`, `not JSON`, `["ok"]`, `{"status":"ok","broken":}`} {
		t.Run(payload, func(t *testing.T) {
			matches, err := responseMatchesAccept([]byte(payload), map[string]any{"status": "ok"})
			if err != nil || matches {
				t.Fatalf("malformed reply should be ignored, got matches=%v, err=%v", matches, err)
			}
		})
	}
}

func TestResponseMatchesAcceptBoundsReplyPayload(t *testing.T) {
	for _, test := range []struct {
		name    string
		size    int
		wantErr bool
	}{
		{name: "at limit", size: maxMQTTReplyBytes},
		{name: "over limit", size: maxMQTTReplyBytes + 1, wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			matches, err := responseMatchesAccept([]byte(strings.Repeat("x", test.size)), nil)
			if test.wantErr {
				if err == nil || !strings.Contains(err.Error(), "mqtt reply payload exceeded 1048576-byte limit") {
					t.Fatalf("expected MQTT reply size error, got %v", err)
				}
				if matches {
					t.Fatal("oversized MQTT reply unexpectedly matched")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected MQTT reply size error: %v", err)
			}
			if !matches {
				t.Fatal("reply at size limit unexpectedly rejected")
			}
		})
	}
}

func TestResponseMatchesAcceptRejectsOversizedJSONBeforeDecode(t *testing.T) {
	payload := append([]byte(`{"status":"ok","padding":"`), []byte(strings.Repeat("x", maxMQTTReplyBytes))...)
	payload = append(payload, []byte(`"}`)...)

	matches, err := responseMatchesAccept(payload, map[string]any{"status": "ok"})
	if err == nil || !strings.Contains(err.Error(), "mqtt reply payload exceeded 1048576-byte limit") {
		t.Fatalf("expected MQTT reply size error, got %v", err)
	}
	if matches {
		t.Fatal("oversized JSON MQTT reply unexpectedly matched")
	}
}

func TestParseAcceptCriteriaRejectsCyclicValue(t *testing.T) {
	accept := starlark.NewDict(1)
	if err := accept.SetKey(starlark.String("status"), accept); err != nil {
		t.Fatalf("set cyclic accept value: %v", err)
	}

	_, err := parseAcceptCriteria(t.Context(), accept)
	if err == nil || !strings.Contains(err.Error(), "cyclic dict") {
		t.Fatalf("expected cyclic accept criteria error, got %v", err)
	}
}

func TestParseAcceptCriteriaRejectsNestedSelectors(t *testing.T) {
	accept := starlark.NewDict(1)
	if err := accept.SetKey(starlark.String("status.ok"), starlark.String("ready")); err != nil {
		t.Fatalf("set accept key: %v", err)
	}
	if _, err := parseAcceptCriteria(t.Context(), accept); err == nil {
		t.Fatalf("expected nested accept selector to fail")
	}
}
