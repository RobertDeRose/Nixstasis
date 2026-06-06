package sshauth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"time"
)

const (
	maxIPCRequestBytes  = 4096
	maxIPCResponseBytes = 4096
	defaultDialTimeout  = 750 * time.Millisecond
)

// QueryRequest is the helper-to-client SSH authorization lookup request.
type QueryRequest struct {
	User    string `json:"user"`
	KeyType string `json:"key_type"`
	KeyBlob string `json:"key_blob"`
}

// QueryResponse is the client-to-helper SSH authorization lookup response.
type QueryResponse struct {
	Authorized bool   `json:"authorized"`
	KeyType    string `json:"key_type,omitempty"`
	KeyBlob    string `json:"key_blob,omitempty"`
}

// Server serves local Unix-socket SSH authorization lookups.
type Server struct {
	Path  string
	Store *Store
	ln    net.Listener
}

// NewServer creates an SSH authorization IPC server.
func NewServer(path string, store *Store) *Server {
	if path == "" {
		path = DefaultSocketPath
	}
	return &Server{Path: path, Store: store}
}

// Start opens the Unix-domain socket and begins serving authorization lookups.
func (s *Server) Start(ctx context.Context) error {
	if s.Store == nil {
		return errors.New("ssh authorization store is not configured")
	}
	if err := prepareSocketPath(s.Path); err != nil {
		return err
	}
	ln, err := new(net.ListenConfig).Listen(ctx, "unix", s.Path)
	if err != nil {
		return fmt.Errorf("listen ssh authorization socket: %w", err)
	}
	chownSocketGroup(s.Path)
	// #nosec G302 -- group write is required for AuthorizedKeysCommandUser IPC.
	if err := os.Chmod(s.Path, 0o660); err != nil {
		ignoreError(ln.Close())
		return fmt.Errorf("chmod ssh authorization socket: %w", err)
	}
	s.ln = ln
	go func() {
		<-ctx.Done()
		ignoreError(s.Close())
	}()
	go s.serve()
	return nil
}

// Close stops the IPC server and removes its socket path.
func (s *Server) Close() error {
	if s == nil || s.ln == nil {
		return nil
	}
	err := s.ln.Close()
	ignoreError(os.Remove(s.Path))
	return err
}

func (s *Server) serve() {
	for {
		conn, err := s.ln.Accept()
		if err != nil {
			return
		}
		go s.handle(conn)
	}
}

func (s *Server) handle(conn net.Conn) {
	defer func() { ignoreError(conn.Close()) }()
	ignoreError(conn.SetDeadline(time.Now().Add(defaultDialTimeout)))
	var req QueryRequest
	if err := json.NewDecoder(io.LimitReader(conn, maxIPCRequestBytes)).Decode(&req); err != nil {
		ignoreError(json.NewEncoder(conn).Encode(QueryResponse{Authorized: false}))
		return
	}
	key, ok := s.Store.Authorize(req.User, req.KeyType, req.KeyBlob)
	if !ok {
		ignoreError(json.NewEncoder(conn).Encode(QueryResponse{Authorized: false}))
		return
	}
	ignoreError(json.NewEncoder(conn).Encode(QueryResponse{Authorized: true, KeyType: key.Type, KeyBlob: key.Blob}))
}

// Query asks the local SSH authorization server whether an offered key is allowed.
func Query(ctx context.Context, path string, req QueryRequest) (QueryResponse, error) {
	if path == "" {
		path = DefaultSocketPath
	}
	dialer := net.Dialer{Timeout: defaultDialTimeout}
	conn, err := dialer.DialContext(ctx, "unix", path)
	if err != nil {
		return QueryResponse{}, err
	}
	defer func() { ignoreError(conn.Close()) }()
	deadline, ok := ctx.Deadline()
	if !ok {
		deadline = time.Now().Add(defaultDialTimeout)
	}
	ignoreError(conn.SetDeadline(deadline))
	if err := json.NewEncoder(conn).Encode(req); err != nil {
		return QueryResponse{}, err
	}
	var resp QueryResponse
	if err := json.NewDecoder(io.LimitReader(conn, maxIPCResponseBytes)).Decode(&resp); err != nil {
		return QueryResponse{}, err
	}
	return resp, nil
}

func prepareSocketPath(path string) error {
	if path == "" || !filepath.IsAbs(path) {
		return errors.New("ssh authorization socket path must be absolute")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create ssh authorization runtime directory: %w", err)
	}
	info, err := os.Lstat(path)
	if err == nil {
		if info.Mode().Type() != os.ModeSocket {
			return fmt.Errorf("refusing to replace non-socket at %s", path)
		}
		if err := os.Remove(path); err != nil {
			return fmt.Errorf("remove stale ssh authorization socket: %w", err)
		}
		return nil
	}
	if !os.IsNotExist(err) {
		return fmt.Errorf("stat ssh authorization socket: %w", err)
	}
	return nil
}

func chownSocketGroup(path string) {
	group, err := user.LookupGroup("nixstasis-ssh")
	if err != nil {
		return
	}
	gid, err := strconv.Atoi(group.Gid)
	if err != nil {
		return
	}
	ignoreError(os.Chown(path, -1, gid))
}

func ignoreError(error) {}
