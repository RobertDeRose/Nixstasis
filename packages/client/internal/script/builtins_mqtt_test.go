package script

import (
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
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
	if !topicAllowed("$SYS/broker/clients", []string{"$SYS/#"}) {
		t.Fatalf("expected explicit $-prefixed pattern to allow system topic")
	}
}

// TestMQTTTopicRestrictionsRejectRequestedWildcards verifies that allowlist
// patterns never authorize wildcard characters in requested topics, and that
// leading wildcards never authorize $-prefixed system topics.
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
		{
			name:    "leading multi-level wildcard does not authorize system topics",
			topic:   "$SYS/broker/clients",
			allowed: []string{"#"},
		},
		{
			name:    "leading single-level wildcard does not authorize system topics",
			topic:   "$SYS/broker",
			allowed: []string{"+/broker"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if topicAllowed(test.topic, test.allowed) {
				t.Fatalf("expected requested topic %q to be rejected", test.topic)
			}
		})
	}
}

// TestPubAndGetRejectsWildcardReplyTopicBeforeBroker verifies that reply topic
// validation fails before attempting to contact an unreachable broker.
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

// TestPubAndGetReturnsOversizedReplyError verifies that an oversized reply
// delivered to the subscription handler fails the call and still unsubscribes.
func TestPubAndGetReturnsOversizedReplyError(t *testing.T) {
	client := &fakeMQTTClient{reply: make([]byte, maxMQTTReplyBytes+1)}
	runtime := NewRuntime(RuntimeConfig{
		Timeout:             5 * time.Second,
		MQTTBroker:          "tcp://127.0.0.1:1",
		MQTTPublishTopics:   []string{"request/+"},
		MQTTSubscribeTopics: []string{"reply/+"},
	})
	runtime.mqttClient = client

	_, err := runtime.Execute(t.Context(), "test.star", `
def main():
    return {"out": pub_and_get(topic="request/device-1", msg="ping", reply_topic="reply/device-1")}
`)
	if err == nil || !strings.Contains(err.Error(), "mqtt reply payload exceeded 1048576-byte limit") {
		t.Fatalf("expected MQTT reply size error, got %v", err)
	}
	if got := client.unsubscribedTopics(); !slices.Equal(got, []string{"reply/device-1"}) {
		t.Fatalf("unsubscribed topics = %v, want [reply/device-1]", got)
	}
}

// TestPubAndGetReportsSubscribeTimeout verifies that a subscribe that never
// completes fails with a timeout error instead of wrapping a nil error.
func TestPubAndGetReportsSubscribeTimeout(t *testing.T) {
	client := &fakeMQTTClient{subscribeToken: pendingToken{}}
	runtime := NewRuntime(RuntimeConfig{
		Timeout:             5 * time.Second,
		MQTTBroker:          "tcp://127.0.0.1:1",
		MQTTPublishTopics:   []string{"request/+"},
		MQTTSubscribeTopics: []string{"reply/+"},
	})
	runtime.mqttClient = client

	_, err := runtime.Execute(t.Context(), "test.star", `
def main():
    return {"out": pub_and_get(topic="request/device-1", msg="ping", reply_topic="reply/device-1")}
`)
	if err == nil || !strings.Contains(err.Error(), "subscribe timed out after 3s") {
		t.Fatalf("expected subscribe timeout error, got %v", err)
	}
}

// fakeMQTTClient delivers a fixed reply to the subscribed handler on publish.
// Unimplemented mqtt.Client methods panic through the nil embedded interface.
type fakeMQTTClient struct {
	mqtt.Client

	reply []byte
	// subscribeToken, when set, replaces the completed token Subscribe returns.
	subscribeToken mqtt.Token

	mu           sync.Mutex
	handler      mqtt.MessageHandler
	unsubscribed []string
}

// IsConnected reports a live connection so connectMQTT reuses the fake.
func (c *fakeMQTTClient) IsConnected() bool { return true }

// Disconnect does nothing because the fake holds no connection.
func (c *fakeMQTTClient) Disconnect(uint) {}

// Subscribe records callback as the reply handler and completes immediately.
func (c *fakeMQTTClient) Subscribe(_ string, _ byte, callback mqtt.MessageHandler) mqtt.Token {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.handler = callback
	if c.subscribeToken != nil {
		return c.subscribeToken
	}
	return completedToken{}
}

// Publish synchronously delivers the configured reply to the handler recorded
// by Subscribe, which must run first, and completes immediately.
func (c *fakeMQTTClient) Publish(string, byte, bool, any) mqtt.Token {
	c.mu.Lock()
	handler := c.handler
	c.mu.Unlock()
	handler(c, fakeMQTTMessage{payload: c.reply})
	return completedToken{}
}

// Unsubscribe records topics for cleanup assertions and completes immediately.
func (c *fakeMQTTClient) Unsubscribe(topics ...string) mqtt.Token {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.unsubscribed = append(c.unsubscribed, topics...)
	return completedToken{}
}

// unsubscribedTopics returns a copy of the topics passed to Unsubscribe, in
// call order.
func (c *fakeMQTTClient) unsubscribedTopics() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return slices.Clone(c.unsubscribed)
}

type fakeMQTTMessage struct {
	mqtt.Message

	payload []byte
}

// Payload returns the fixed reply bytes.
func (m fakeMQTTMessage) Payload() []byte { return m.payload }

type completedToken struct{}

// Wait reports that the operation already completed.
func (completedToken) Wait() bool { return true }

// WaitTimeout reports completion without waiting.
func (completedToken) WaitTimeout(time.Duration) bool { return true }

// Done returns an already-closed channel.
func (completedToken) Done() <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}

// Error reports that the operation succeeded.
func (completedToken) Error() error { return nil }

// pendingToken models an MQTT operation the broker never completes.
type pendingToken struct{}

// Wait blocks forever in the real client; the fake reports no completion.
func (pendingToken) Wait() bool { return false }

// WaitTimeout reports that the timeout elapsed without completion.
func (pendingToken) WaitTimeout(time.Duration) bool { return false }

// Done returns a channel that never closes.
func (pendingToken) Done() <-chan struct{} { return make(chan struct{}) }

// Error reports no error because the operation never finished.
func (pendingToken) Error() error { return nil }

// TestAcceptCriteriaMatchesOnlyExpectedKeyValues verifies that all requested
// fields must match while extra response fields remain accepted.
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

// TestResponseMatchesAcceptIgnoresMalformedReplies verifies that malformed JSON
// and non-object replies do not match accept criteria and do not fail the call.
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

// TestResponseMatchesAcceptBoundsReplyPayload verifies the inclusive 1 MiB
// MQTT reply ceiling without accept criteria: a reply of exactly
// maxMQTTReplyBytes matches, and one byte more fails with the size error.
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

// TestResponseMatchesAcceptRejectsOversizedJSONBeforeDecode verifies that the
// size ceiling applies before accept-criteria JSON decoding, even when the
// oversized reply would otherwise match.
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

// TestParseAcceptCriteriaRejectsCyclicValue verifies that reply filters cannot
// contain a self-referential dictionary.
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

// TestParseAcceptCriteriaRejectsNestedSelectors verifies that reply filters
// reject dotted selectors instead of treating them as nested JSON paths.
func TestParseAcceptCriteriaRejectsNestedSelectors(t *testing.T) {
	accept := starlark.NewDict(1)
	if err := accept.SetKey(starlark.String("status.ok"), starlark.String("ready")); err != nil {
		t.Fatalf("set accept key: %v", err)
	}
	if _, err := parseAcceptCriteria(t.Context(), accept); err == nil {
		t.Fatalf("expected nested accept selector to fail")
	}
}
