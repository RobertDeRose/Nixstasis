package script

import "testing"

func TestShouldIgnoreEcho(t *testing.T) {
	replyTopic := "topic"
	topic := "topic"
	msg := "payload"

	handler := func(payload string) bool {
		if replyTopic == topic && payload == msg {
			return false
		}
		return true
	}

	if handler("payload") {
		t.Fatalf("expected echo to be ignored when topic matches and payload equals msg")
	}
	if !handler("response") {
		t.Fatalf("expected response to pass when payload differs")
	}
}
