package script

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"sync"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"go.starlark.net/lib/json"
	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

// ErrTimeout is returned when a script execution exceeds its allowed runtime.
var ErrTimeout = errors.New("script timeout")

// Runtime executes Starlark scripts with a configured set of builtins.
type Runtime struct {
	config     RuntimeConfig
	builtins   starlark.StringDict
	mqttMu     sync.Mutex
	mqttClient mqtt.Client
}

// NewRuntime constructs a Runtime with configured timeouts, builtins, and safety defaults.
func NewRuntime(config RuntimeConfig) *Runtime {
	if config.Timeout == 0 {
		config.Timeout = 5 * time.Second
	}
	if config.WarnAfter == 0 {
		config.WarnAfter = 3 * time.Second
	}
	if config.MQTTBroker == "" {
		config.MQTTBroker = "tcp://localhost:1883"
	}
	r := &Runtime{config: config}
	r.builtins = starlark.StringDict{
		"pub_and_get": starlark.NewBuiltin("pub_and_get", r.pubAndGetBuiltin),
		"exec_cmd":    starlark.NewBuiltin("exec_cmd", r.execCmdBuiltin),
		"json":        json.Module,
	}

	return r
}

// Builtins returns a copy of the runtime's predeclared builtins.
func (r *Runtime) Builtins() starlark.StringDict {
	globals := make(starlark.StringDict, len(r.builtins))
	maps.Copy(globals, r.builtins)
	return globals
}

// Close releases any runtime resources such as MQTT connections.
func (r *Runtime) Close() error {
	r.mqttMu.Lock()
	defer r.mqttMu.Unlock()

	if r.mqttClient != nil && r.mqttClient.IsConnected() {
		r.mqttClient.Disconnect(250)
	}
	r.mqttClient = nil
	return nil
}

type result struct {
	val any
	err error
}

// Execute runs the provided script body and returns the output dict as a Go map.
func (r *Runtime) Execute(ctx context.Context, scriptPath, body string) (map[string]any, error) {
	ctx, cancel := context.WithTimeout(ctx, r.config.Timeout)
	defer cancel()

	resCh := make(chan result, 1)
	thread := &starlark.Thread{Name: "stary"}

	go func() {
		globals, err := starlark.ExecFileOptions(&syntax.FileOptions{}, thread, scriptPath, body, r.builtins)
		if err != nil {
			resCh <- result{err: err}
			return
		}

		mainFn, ok := globals["main"]
		if !ok {
			resCh <- result{err: fmt.Errorf("script missing main()")}
			return
		}

		callable, ok := mainFn.(starlark.Callable)
		if !ok {
			resCh <- result{err: fmt.Errorf("main() is not callable")}
			return
		}

		val, err := starlark.Call(thread, callable, nil, nil)
		if err != nil {
			resCh <- result{err: err}
			return
		}

		out, err := starlarkValueToGo(val)
		resCh <- result{val: out, err: err}
	}()

	select {
	case <-ctx.Done():
		thread.Cancel(ErrTimeout.Error())
		<-resCh
		return nil, ErrTimeout
	case res := <-resCh:
		if res.err != nil {
			return nil, res.err
		}
		if res.val == nil {
			return map[string]any{}, nil
		}
		out, ok := res.val.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("script must return a dict, got %T", res.val)
		}
		return out, nil
	}
}

// Consolidated conversion logic.
func starlarkValueToGo(value starlark.Value) (any, error) {
	switch v := value.(type) {
	case starlark.NoneType:
		return nil, nil
	case starlark.Bool:
		return bool(v), nil
	case starlark.String:
		return string(v), nil
	case starlark.Int:
		i, _ := v.Int64()
		return i, nil
	case starlark.Float:
		return float64(v), nil
	case *starlark.List:
		return convertIterable(v.Len(), v.Iterate())
	case starlark.Tuple:
		return convertIterable(len(v), v.Iterate())
	case *starlark.Dict:
		res := make(map[string]any)
		for _, item := range v.Items() {
			key, ok := item[0].(starlark.String)
			if !ok {
				return nil, fmt.Errorf("dict keys must be strings")
			}
			val, err := starlarkValueToGo(item[1])
			if err != nil {
				return nil, err
			}
			res[string(key)] = val
		}
		return res, nil
	default:
		return nil, fmt.Errorf("unsupported starlark type: %s", value.Type())
	}
}

func convertIterable(size int, iter starlark.Iterator) ([]any, error) {
	defer iter.Done()
	res := make([]any, 0, size)
	var val starlark.Value
	for iter.Next(&val) {
		converted, err := starlarkValueToGo(val)
		if err != nil {
			return nil, err
		}
		res = append(res, converted)
	}
	return res, nil
}
