// Command mock_api provides a lightweight HTTP server for end-to-end testing.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json/v2"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
)

type deviceState struct {
	lastTelemetry   map[string]any
	lastPollAt      time.Time
	lastCmdResults  []transport.CommandResult
	pendingCommands []transport.CommandRequest
	payloads        map[string]transport.CommandPayload
}

type server struct {
	mu              sync.Mutex
	devices         map[string]*deviceState
	remoteAccessOn  bool
	allowUnknownIDs bool
}

func main() {
	addr := flag.String("addr", ":4000", "listen address")
	remoteAccess := flag.Bool("remote-access", false, "set remote_access_requested=true on poll responses")
	allowUnknown := flag.Bool("allow-unknown", true, "accept polls from unknown devices")
	logDest := flag.String("log", "", "log destination: 'stderr' or file path (default: discard)")
	flag.Parse()

	logCloser := configureLogging(*logDest)
	if logCloser != nil {
		defer logCloser.Close()
	}

	srv := &server{
		devices:         make(map[string]*deviceState),
		remoteAccessOn:  *remoteAccess,
		allowUnknownIDs: *allowUnknown,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", srv.handleRoot)
	mux.HandleFunc("/api/v1/devices/register", srv.handleRegister)
	mux.HandleFunc("/api/v1/devices/", srv.handleDeviceRoutes)

	server := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		errCh <- server.ListenAndServe()
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("shutdown signal received: %s", sig)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			log.Printf("shutdown error: %v", err)
		}
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("server error: %v", err)
		}
	}
}

func configureLogging(destination string) io.Closer {
	switch destination {
	case "":
		log.SetOutput(io.Discard)
		return nil
	case "stderr":
		log.SetOutput(os.Stderr)
		return nil
	default:
		file, err := os.OpenFile(destination, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600) // #nosec G304 -- user-provided log destination for mock server.
		if err != nil {
			log.SetOutput(os.Stderr)
			log.Printf("failed to open log file %s: %v", destination, err)
			return nil
		}
		log.SetOutput(file)
		return file
	}
}

func (s *server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"endpoints": []string{
			"POST /api/v1/devices/register",
			"POST /api/v1/devices/{id}/heartbeat",
			"POST /api/v1/devices/{id}/command_results",
			"POST /api/v1/devices/{id}/commands",
			"POST /api/v1/devices/{id}/command_payloads",
			"POST /api/v1/devices/{id}/command_payloads/{ref}",
			"GET  /api/v1/devices/{id}/command_payloads/{ref}",
			"GET  /api/v1/devices/{id}/telemetry",
			"GET  /api/v1/devices/{id}/command_results",
		},
	})
}

func (s *server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}

	id := randomID()
	s.mu.Lock()
	s.devices[id] = &deviceState{}
	s.mu.Unlock()

	writeJSON(w, http.StatusCreated, map[string]any{"data": map[string]string{"id": id}})
}

func (s *server) handleDeviceRoutes(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/devices/")
	if path == "" || path == r.URL.Path {
		http.NotFound(w, r)
		return
	}

	parts := strings.SplitN(path, "/", 2)
	id := parts[0]
	rest := ""
	if len(parts) == 2 {
		rest = parts[1]
	}

	switch {
	case rest == "heartbeat":
		s.handlePoll(w, r, id)
	case rest == "command_results":
		s.handleCommandResults(w, r, id)
	case rest == "commands":
		s.handleQueueCommands(w, r, id)
	case rest == "telemetry":
		s.handleTelemetry(w, r, id)
	case rest == "command_payloads":
		s.handleCommandPayloadRoot(w, r, id)
	case strings.HasPrefix(rest, "command_payloads/"):
		ref := strings.TrimPrefix(rest, "command_payloads/")
		s.handleCommandPayload(w, r, id, ref)
	default:
		http.NotFound(w, r)
	}
}

func (s *server) handlePoll(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}

	body := make(map[string]any)
	if err := json.UnmarshalRead(r.Body, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}

	s.mu.Lock()
	state := s.devices[id]
	if state == nil {
		if !s.allowUnknownIDs {
			s.mu.Unlock()
			writeError(w, http.StatusNotFound, "unknown device", nil)
			return
		}
		state = &deviceState{}
		s.devices[id] = state
	}

	state.lastTelemetry = body
	state.lastPollAt = time.Now()
	commands := append([]transport.CommandRequest(nil), state.pendingCommands...)
	state.pendingCommands = nil
	s.mu.Unlock()

	log.Printf("poll: device=%s commands=%d", id, len(commands))

	writeJSON(w, http.StatusOK, map[string]any{
		"data": map[string]any{
			"remote_access_requested": s.remoteAccessOn,
			"commands":                commands,
		},
	})
}

func (s *server) handleCommandResults(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		if r.Method == http.MethodGet {
			s.handleCommandResultsGet(w, r, id)
			return
		}
		http.NotFound(w, r)
		return
	}

	var req struct {
		Results []transport.CommandResult `json:"results"`
	}
	if err := json.UnmarshalRead(r.Body, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}

	s.mu.Lock()
	state := s.ensureDevice(id)
	state.lastCmdResults = req.Results
	s.mu.Unlock()

	log.Printf("command_results: device=%s results=%d", id, len(req.Results))
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) handleCommandResultsGet(w http.ResponseWriter, _ *http.Request, id string) {
	s.mu.Lock()
	state := s.devices[id]
	s.mu.Unlock()
	if state == nil {
		writeError(w, http.StatusNotFound, "unknown device", nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"results": state.lastCmdResults,
	})
}

func (s *server) handleQueueCommands(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}

	var payload any
	if err := json.UnmarshalRead(r.Body, &payload); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}

	commands, err := parseCommands(payload)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid commands payload", err)
		return
	}

	s.mu.Lock()
	state := s.ensureDevice(id)
	state.pendingCommands = append(state.pendingCommands, commands...)
	s.mu.Unlock()

	log.Printf("queued commands: device=%s count=%d", id, len(commands))
	writeJSON(w, http.StatusAccepted, map[string]any{"queued": len(commands)})
}

func (s *server) handleCommandPayload(w http.ResponseWriter, r *http.Request, id, ref string) {
	if ref == "" {
		http.NotFound(w, r)
		return
	}

	switch r.Method {
	case http.MethodGet:
		s.mu.Lock()
		state := s.devices[id]
		s.mu.Unlock()
		if state == nil || state.payloads == nil {
			writeError(w, http.StatusNotFound, "payload not found", nil)
			return
		}
		payload, ok := state.payloads[ref]
		if !ok {
			writeError(w, http.StatusNotFound, "payload not found", nil)
			return
		}
		writeJSON(w, http.StatusOK, payload)
	case http.MethodPost:
		var payload transport.CommandPayload
		if err := json.UnmarshalRead(r.Body, &payload); err != nil {
			writeError(w, http.StatusBadRequest, "invalid json", err)
			return
		}
		if payload.ContentType == "" || payload.Name == "" {
			writeError(w, http.StatusBadRequest, "content_type and name required", nil)
			return
		}

		s.mu.Lock()
		state := s.ensureDevice(id)
		if state.payloads == nil {
			state.payloads = make(map[string]transport.CommandPayload)
		}
		state.payloads[ref] = payload
		s.mu.Unlock()

		writeJSON(w, http.StatusAccepted, map[string]any{"stored": ref})
	default:
		http.NotFound(w, r)
	}
}

func (s *server) handleCommandPayloadRoot(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}

	var payload transport.CommandPayload
	if err := json.UnmarshalRead(r.Body, &payload); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}
	if payload.ContentType == "" || payload.Name == "" {
		writeError(w, http.StatusBadRequest, "content_type and name required", nil)
		return
	}

	ref := "payload-" + randomID()
	s.mu.Lock()
	state := s.ensureDevice(id)
	if state.payloads == nil {
		state.payloads = make(map[string]transport.CommandPayload)
	}
	state.payloads[ref] = payload
	s.mu.Unlock()

	writeJSON(w, http.StatusAccepted, map[string]any{"ref": ref})
}

func (s *server) handleTelemetry(w http.ResponseWriter, _ *http.Request, id string) {
	s.mu.Lock()
	state := s.devices[id]
	s.mu.Unlock()
	if state == nil {
		writeError(w, http.StatusNotFound, "unknown device", nil)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"last_poll_at": state.lastPollAt,
		"telemetry":    state.lastTelemetry,
	})
}

func (s *server) ensureDevice(id string) *deviceState {
	state := s.devices[id]
	if state == nil {
		state = &deviceState{payloads: make(map[string]transport.CommandPayload)}
		s.devices[id] = state
	}
	return state
}

func parseCommands(payload any) ([]transport.CommandRequest, error) {
	switch v := payload.(type) {
	case map[string]any:
		if raw, ok := v["commands"]; ok {
			return parseCommands(raw)
		}
		cmd, err := decodeCommand(v)
		if err != nil {
			return nil, err
		}
		return []transport.CommandRequest{cmd}, nil
	case []any:
		var commands []transport.CommandRequest
		for _, item := range v {
			itemMap, ok := item.(map[string]any)
			if !ok {
				return nil, fmt.Errorf("command entry must be object")
			}
			cmd, err := decodeCommand(itemMap)
			if err != nil {
				return nil, err
			}
			commands = append(commands, cmd)
		}
		return commands, nil
	default:
		return nil, fmt.Errorf("unexpected payload type")
	}
}

func decodeCommand(raw map[string]any) (transport.CommandRequest, error) {
	commandID, ok := raw["command_id"].(string)
	if !ok || commandID == "" {
		return transport.CommandRequest{}, fmt.Errorf("command_id required")
	}
	typ, ok := raw["type"].(string)
	if !ok || typ == "" {
		return transport.CommandRequest{}, fmt.Errorf("type required")
	}
	payload, err := parseCommandPayload(raw["payload"])
	if err != nil {
		return transport.CommandRequest{}, err
	}
	payloadRef, ok := raw["payload_ref"].(string)
	if !ok {
		payloadRef = ""
	}
	args := parseCommandArgs(raw["args"])

	return transport.CommandRequest{
		CommandID:  commandID,
		Type:       typ,
		Args:       args,
		Payload:    payload,
		PayloadRef: payloadRef,
	}, nil
}

func parseCommandPayload(raw any) (*transport.CommandPayload, error) {
	if raw == nil {
		return nil, nil
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("payload marshal: %w", err)
	}
	var decoded transport.CommandPayload
	if err := json.Unmarshal(b, &decoded); err != nil {
		return nil, fmt.Errorf("payload decode: %w", err)
	}
	if decoded.ContentType == "" && decoded.Name == "" && decoded.Data == "" {
		return nil, nil
	}
	return &decoded, nil
}

func parseCommandArgs(raw any) []string {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	args := make([]string, 0, len(list))
	for _, item := range list {
		if str, ok := item.(string); ok {
			args = append(args, str)
		}
	}
	return args
}

func randomID() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("device-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(buf)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.MarshalWrite(w, body); err != nil {
		log.Printf("mock api write error: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string, err error) {
	payload := map[string]any{"error": message}
	if err != nil {
		payload["detail"] = err.Error()
	}
	writeJSON(w, status, payload)
}
