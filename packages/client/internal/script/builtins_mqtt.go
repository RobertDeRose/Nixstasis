package script

import (
	"context"
	"encoding/json/v2"
	"fmt"
	"reflect"
	"strings"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"go.starlark.net/starlark"
)

func (r *Runtime) pubAndGetBuiltin(thread *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	ctx := runtimeContext(thread)
	if ctx.Err() != nil {
		return nil, ErrTimeout
	}
	select {
	case r.pubAndGetSem <- struct{}{}:
		defer func() { <-r.pubAndGetSem }()
	case <-ctx.Done():
		return nil, ErrTimeout
	}

	var topic string
	var msg string
	var replyTopic string
	var accept *starlark.Dict

	if err := starlark.UnpackArgs("pub_and_get", args, kwargs,
		"topic", &topic,
		"msg", &msg,
		"reply_topic?", &replyTopic,
		"accept?", &accept,
	); err != nil {
		return nil, err
	}

	if strings.TrimSpace(replyTopic) == "" {
		replyTopic = topic
	}
	if len(r.config.MQTTPublishTopics) == 0 || len(r.config.MQTTSubscribeTopics) == 0 {
		return nil, fmt.Errorf("pub_and_get capability is not configured")
	}
	if !topicAllowed(topic, r.config.MQTTPublishTopics) {
		return nil, fmt.Errorf("publish topic is not allowed: %s", topic)
	}
	if !topicAllowed(replyTopic, r.config.MQTTSubscribeTopics) {
		return nil, fmt.Errorf("subscribe topic is not allowed: %s", replyTopic)
	}
	acceptCriteria, err := parseAcceptCriteria(accept)
	if err != nil {
		return nil, err
	}
	if ctx.Err() != nil {
		return nil, ErrTimeout
	}

	client, err := r.connectMQTT()
	if err != nil {
		return nil, err
	}

	responseCh := make(chan []byte, 1)
	var handler mqtt.MessageHandler = func(_ mqtt.Client, message mqtt.Message) {
		payload := message.Payload()
		if replyTopic == topic && string(payload) == msg {
			return
		}
		if !responseMatchesAccept(payload, acceptCriteria) {
			return
		}
		select {
		case responseCh <- payload:
		default:
		}
	}

	if token := client.Subscribe(replyTopic, 0, handler); !token.WaitTimeout(3*time.Second) || token.Error() != nil {
		return nil, fmt.Errorf("subscribe failed: %w", token.Error())
	}
	defer func() {
		token := client.Unsubscribe(replyTopic)
		token.WaitTimeout(2 * time.Second)
	}()

	if token := client.Publish(topic, 0, false, msg); !token.WaitTimeout(3*time.Second) || token.Error() != nil {
		return nil, fmt.Errorf("publish failed: %w", token.Error())
	}

	select {
	case payload := <-responseCh:
		return starlark.String(string(payload)), nil
	case <-ctx.Done():
		return nil, ErrTimeout
	case <-time.After(5 * time.Second):
		return starlark.None, nil
	}
}

func runtimeContext(thread *starlark.Thread) context.Context {
	if thread == nil {
		return context.Background()
	}
	ctx, ok := thread.Local(runtimeContextThreadKey).(context.Context)
	if !ok || ctx == nil {
		return context.Background()
	}
	return ctx
}

func parseAcceptCriteria(accept *starlark.Dict) (map[string]any, error) {
	if accept == nil {
		return nil, nil
	}
	criteria := make(map[string]any, accept.Len())
	for _, item := range accept.Items() {
		field, ok := item[0].(starlark.String)
		if !ok {
			return nil, fmt.Errorf("accept keys must be strings")
		}
		name := string(field)
		if strings.TrimSpace(name) == "" || strings.ContainsAny(name, ".[]") {
			return nil, fmt.Errorf("accept keys must be non-empty top-level JSON field names")
		}
		value, err := starlarkValueToGo(item[1])
		if err != nil {
			return nil, fmt.Errorf("accept value for %s: %w", name, err)
		}
		criteria[name] = value
	}
	return criteria, nil
}

func responseMatchesAccept(payload []byte, accept map[string]any) bool {
	if len(accept) == 0 {
		return true
	}
	var input map[string]any
	if err := json.Unmarshal(payload, &input); err != nil {
		return false
	}
	for key, want := range accept {
		got, ok := input[key]
		if !ok || !acceptValuesEqual(got, want) {
			return false
		}
	}
	return true
}

func acceptValuesEqual(got, want any) bool {
	if reflect.DeepEqual(got, want) {
		return true
	}
	switch want := want.(type) {
	case int64:
		return numberString(got) == fmt.Sprint(want)
	case float64:
		return numberString(got) == fmt.Sprint(want)
	default:
		return false
	}
}

func numberString(value any) string {
	switch value := value.(type) {
	case float64, int64, int, uint64:
		return fmt.Sprint(value)
	default:
		return ""
	}
}

func topicAllowed(topic string, patterns []string) bool {
	for _, pattern := range patterns {
		if mqttTopicMatch(pattern, topic) {
			return true
		}
	}
	return false
}

func mqttTopicMatch(pattern, topic string) bool {
	if pattern == "" || topic == "" {
		return false
	}
	patternParts := strings.Split(pattern, "/")
	topicParts := strings.Split(topic, "/")
	for i, part := range patternParts {
		if part == "#" {
			return i == len(patternParts)-1
		}
		if i >= len(topicParts) {
			return false
		}
		if part != "+" && part != topicParts[i] {
			return false
		}
	}
	return len(patternParts) == len(topicParts)
}

func (r *Runtime) connectMQTT() (mqtt.Client, error) {
	r.mqttMu.Lock()
	defer r.mqttMu.Unlock()

	if r.mqttClient != nil && r.mqttClient.IsConnected() {
		return r.mqttClient, nil
	}

	if r.mqttFailures >= maxMQTTConnectAttempts {
		return nil, fmt.Errorf("mqtt connect circuit open: %d consecutive failures, skipping until next poll cycle", r.mqttFailures)
	}

	opts := mqtt.NewClientOptions()
	opts.AddBroker(r.config.MQTTBroker)
	opts.SetClientID(fmt.Sprintf("nixstasis-stary-%d-%d", time.Now().UnixNano(), r.mqttSeq.Add(1)))

	client := mqtt.NewClient(opts)
	if token := client.Connect(); !token.WaitTimeout(5*time.Second) || token.Error() != nil {
		r.mqttFailures++
		return nil, fmt.Errorf("mqtt connect failed: %w", token.Error())
	}

	r.mqttFailures = 0
	r.mqttClient = client
	return client, nil
}
