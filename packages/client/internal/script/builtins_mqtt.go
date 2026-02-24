package script

import (
	"fmt"
	"strings"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"go.starlark.net/starlark"
)

func (r *Runtime) pubAndGetBuiltin(_ *starlark.Thread, _ *starlark.Builtin, args starlark.Tuple, kwargs []starlark.Tuple) (starlark.Value, error) {
	var topic string
	var msg string
	var replyTopic string

	if err := starlark.UnpackArgs("pub_and_get", args, kwargs,
		"topic", &topic,
		"msg", &msg,
		"reply_topic?", &replyTopic,
	); err != nil {
		return nil, err
	}

	if strings.TrimSpace(replyTopic) == "" {
		replyTopic = topic
	}

	client, err := r.connectMQTT()
	if err != nil {
		return nil, err
	}
	defer client.Disconnect(250)

	responseCh := make(chan []byte, 1)
	var handler mqtt.MessageHandler = func(_ mqtt.Client, message mqtt.Message) {
		payload := message.Payload()
		if replyTopic == topic && string(payload) == msg {
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
	case <-time.After(5 * time.Second):
		return starlark.None, nil
	}
}

func (r *Runtime) connectMQTT() (mqtt.Client, error) {
	r.mqttMu.Lock()
	defer r.mqttMu.Unlock()

	if r.mqttClient != nil && r.mqttClient.IsConnected() {
		return r.mqttClient, nil
	}

	opts := mqtt.NewClientOptions()
	opts.AddBroker(r.config.MQTTBroker)
	opts.SetClientID(fmt.Sprintf("nixstasis-stary-%d", time.Now().UnixNano()))

	client := mqtt.NewClient(opts)
	if token := client.Connect(); !token.WaitTimeout(5*time.Second) || token.Error() != nil {
		return nil, fmt.Errorf("mqtt connect failed: %w", token.Error())
	}

	r.mqttClient = client
	return client, nil
}
