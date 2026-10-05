package script

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"os"
	"sync"
	"sync/atomic"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"go.starlark.net/lib/json"
	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

// ErrTimeout is returned when a script execution exceeds its allowed runtime.
var ErrTimeout = errors.New("script timeout")

// ErrExecutionLimit is returned when a script exceeds the runtime Starlark
// computation-step budget.
var ErrExecutionLimit = errors.New("script execution step limit exceeded")

// defaultMaxStarlarkExecutionSteps bounds deterministic interpreter work in
// addition to the wall-clock timeout. Builtins remain responsible for their
// own I/O and allocation limits.
const defaultMaxStarlarkExecutionSteps uint64 = 1_000_000

// maxMQTTConnectAttempts is the maximum number of consecutive MQTT connection
// failures before the Runtime stops attempting for the rest of this poll cycle.
// A new Runtime is created each poll cycle, so the breaker resets automatically.
const maxMQTTConnectAttempts = 3

const runtimeContextThreadKey = "nixstasis.runtime.context"

// Runtime executes Starlark scripts with a configured set of builtins.
type Runtime struct {
	config RuntimeConfig
	// builtins is populated once in NewRuntime and must not be mutated after
	// construction. Multiple goroutines read it concurrently via ExecFileOptions.
	builtins          starlark.StringDict
	maxExecutionSteps uint64
	mqttMu            sync.Mutex
	mqttClient        mqtt.Client
	mqttFailures      int
	// pubAndGetSem serializes pub_and_get calls. Capacity MUST be 1 because
	// the shared MQTT client's Subscribe/Unsubscribe are not scoped per-call;
	// allowing concurrent pub_and_get on the same reply topic would race the
	// subscription handler.
	pubAndGetSem chan struct{}
	mqttSeq      atomic.Uint64
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
	if config.ExecWorkDir == "" {
		config.ExecWorkDir = os.TempDir()
	}

	r := &Runtime{
		config:            config,
		maxExecutionSteps: defaultMaxStarlarkExecutionSteps,
		pubAndGetSem:      make(chan struct{}, 1),
	}
	r.builtins = starlark.StringDict{
		"pub_and_get": starlark.NewBuiltin("pub_and_get", r.pubAndGetBuiltin),
		"exec_cmd":    starlark.NewBuiltin("exec_cmd", r.execCmdBuiltin),
		"read_file":   starlark.NewBuiltin("read_file", r.readFileBuiltin),
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
	if len(body) > maxStarySourceBytes {
		return nil, starySourceTooLargeError(len(body))
	}

	ctx, cancel := context.WithTimeout(ctx, r.config.Timeout)
	defer cancel()

	resCh := make(chan result, 1)
	thread := &starlark.Thread{Name: "stary"}
	stepLimitExceeded := false
	thread.OnMaxSteps = func(thread *starlark.Thread) {
		stepLimitExceeded = true
		thread.Cancel(ErrExecutionLimit.Error())
	}
	thread.SetMaxExecutionSteps(r.maxExecutionSteps)
	thread.SetLocal(runtimeContextThreadKey, ctx)

	// Defensive copy: ExecFileOptions may mutate the predeclared dict during
	// execution. Each goroutine gets its own shallow copy to avoid races.
	predeclared := r.Builtins()

	go func() {
		globals, err := starlark.ExecFileOptions(&syntax.FileOptions{}, thread, scriptPath, body, predeclared)
		if err != nil {
			if stepLimitExceeded {
				err = ErrExecutionLimit
			}
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
			if stepLimitExceeded {
				err = ErrExecutionLimit
			}
			resCh <- result{err: err}
			return
		}

		out, err := starlarkValueToGo(ctx, val)
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

// Starlark values are converted after script execution, so the Starlark
// interpreter's own execution limits do not protect this traversal. Keep the
// native representation bounded independently.
const (
	maxStarlarkConversionDepth       = 64
	maxStarlarkConversionNodes       = 10_000
	maxStarlarkConversionStringBytes = 256 << 10
	maxStarlarkConversionOutputBytes = 1 << 20
)

type starlarkConverter struct {
	ctx         context.Context
	nodes       int
	outputBytes int
	activeLists map[*starlark.List]struct{}
	activeDicts map[*starlark.Dict]struct{}
}

func starlarkValueToGo(ctx context.Context, value starlark.Value) (any, error) {
	converter := &starlarkConverter{
		ctx:         ctx,
		activeLists: make(map[*starlark.List]struct{}),
		activeDicts: make(map[*starlark.Dict]struct{}),
	}
	return converter.convert(value, 0)
}

func (c *starlarkConverter) convert(value starlark.Value, depth int) (any, error) {
	if err := c.checkContext(); err != nil {
		return nil, err
	}
	if depth > maxStarlarkConversionDepth {
		return nil, fmt.Errorf("starlark conversion exceeds maximum nesting depth of %d", maxStarlarkConversionDepth)
	}
	if err := c.consumeNodes(1); err != nil {
		return nil, err
	}

	switch v := value.(type) {
	case starlark.NoneType:
		return c.convertScalar(nil, 4)
	case starlark.Bool:
		return c.convertScalar(bool(v), 5)
	case starlark.String:
		return c.convertString(string(v))
	case starlark.Int:
		i, ok := v.Int64()
		if !ok {
			return nil, fmt.Errorf("integer value exceeds int64 range")
		}
		return c.convertScalar(i, 20)
	case starlark.Float:
		return c.convertScalar(float64(v), 24)
	case *starlark.List:
		return c.convertList(v, depth)
	case starlark.Tuple:
		if err := c.reserveNodes(len(v)); err != nil {
			return nil, err
		}
		if err := c.consumeOutputBytes(containerOutputOverhead(len(v))); err != nil {
			return nil, err
		}
		return c.convertIterable(len(v), v.Iterate(), depth)
	case *starlark.Dict:
		return c.convertDict(v, depth)
	default:
		return nil, fmt.Errorf("unsupported starlark type: %s", value.Type())
	}
}

func (c *starlarkConverter) convertScalar(value any, outputBytes int) (any, error) {
	if err := c.consumeOutputBytes(outputBytes); err != nil {
		return nil, err
	}
	return value, nil
}

func (c *starlarkConverter) convertList(value *starlark.List, depth int) ([]any, error) {
	if _, ok := c.activeLists[value]; ok {
		return nil, fmt.Errorf("starlark conversion contains cyclic list")
	}
	if err := c.reserveNodes(value.Len()); err != nil {
		return nil, err
	}
	if err := c.consumeOutputBytes(containerOutputOverhead(value.Len())); err != nil {
		return nil, err
	}
	c.activeLists[value] = struct{}{}
	defer delete(c.activeLists, value)
	return c.convertIterable(value.Len(), value.Iterate(), depth)
}

func (c *starlarkConverter) convertDict(value *starlark.Dict, depth int) (map[string]any, error) {
	if _, ok := c.activeDicts[value]; ok {
		return nil, fmt.Errorf("starlark conversion contains cyclic dict")
	}
	if err := c.reserveNodes(2 * value.Len()); err != nil {
		return nil, err
	}
	if err := c.consumeOutputBytes(dictOutputOverhead(value.Len())); err != nil {
		return nil, err
	}

	c.activeDicts[value] = struct{}{}
	defer delete(c.activeDicts, value)

	res := make(map[string]any, value.Len())
	for _, item := range value.Items() {
		if err := c.checkContext(); err != nil {
			return nil, err
		}
		if err := c.consumeNodes(1); err != nil {
			return nil, err
		}
		key, ok := item[0].(starlark.String)
		if !ok {
			return nil, fmt.Errorf("dict keys must be strings")
		}
		keyString, err := c.convertStringValue(string(key))
		if err != nil {
			return nil, err
		}
		val, err := c.convert(item[1], depth+1)
		if err != nil {
			return nil, err
		}
		res[keyString] = val
	}
	return res, nil
}

func (c *starlarkConverter) convertIterable(size int, iter starlark.Iterator, depth int) ([]any, error) {
	defer iter.Done()
	res := make([]any, 0, size)
	var val starlark.Value
	for iter.Next(&val) {
		if err := c.checkContext(); err != nil {
			return nil, err
		}
		converted, err := c.convert(val, depth+1)
		if err != nil {
			return nil, err
		}
		res = append(res, converted)
	}
	return res, nil
}

func (c *starlarkConverter) convertString(value string) (any, error) {
	converted, err := c.convertStringValue(value)
	if err != nil {
		return nil, err
	}
	return converted, nil
}

func (c *starlarkConverter) convertStringValue(value string) (string, error) {
	if len(value) > maxStarlarkConversionStringBytes {
		return "", fmt.Errorf("starlark conversion string exceeds size limit of %d bytes", maxStarlarkConversionStringBytes)
	}
	if err := c.consumeOutputBytes(len(value)); err != nil {
		return "", err
	}
	return value, nil
}

func (c *starlarkConverter) checkContext() error {
	if c.ctx == nil {
		return nil
	}
	select {
	case <-c.ctx.Done():
		return ErrTimeout
	default:
		return nil
	}
}

func (c *starlarkConverter) consumeNodes(count int) error {
	if err := c.reserveNodes(count); err != nil {
		return err
	}
	c.nodes += count
	return nil
}

func (c *starlarkConverter) reserveNodes(count int) error {
	if count < 0 || count > maxStarlarkConversionNodes-c.nodes {
		return fmt.Errorf("starlark conversion exceeds node limit of %d", maxStarlarkConversionNodes)
	}
	return nil
}

func (c *starlarkConverter) consumeOutputBytes(count int) error {
	if count < 0 || count > maxStarlarkConversionOutputBytes-c.outputBytes {
		return fmt.Errorf("starlark conversion exceeds output size limit of %d bytes", maxStarlarkConversionOutputBytes)
	}
	c.outputBytes += count
	return nil
}

func containerOutputOverhead(size int) int {
	if size == 0 {
		return 2
	}
	return size + 1
}

func dictOutputOverhead(size int) int {
	if size == 0 {
		return 2
	}
	return (2 * size) + 1
}
