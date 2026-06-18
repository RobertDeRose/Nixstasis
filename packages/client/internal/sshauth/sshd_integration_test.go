//go:build !no_sshd_integration

package sshauth

import (
	"bytes"
	"context"
	cryptorand "crypto/rand"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestRealSSHDIntegration exercises the in-memory SSH authorization pipeline
// against a real sshd + ssh pair. It mirrors the production drop-in
// (AuthorizedKeysFile none, AuthorizedKeysCommand + CommandUser) so a passing
// run demonstrates the wire path end-to-end. The test is skipped when the
// host does not provide sshd/ssh, or on platforms where the user-switch in
// AuthorizedKeysCommandUser is not safe to perform.
func TestRealSSHDIntegration(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("sshd integration test is not supported on Windows")
	}
	if runtime.GOOS == "darwin" {
		// macOS ships with a heavily customized OpenSSH whose
		// AuthorizedKeysCommand safe_path walk can fail on otherwise valid
		// $HOME paths because parent directories created by tools like
		// Home Manager aren't always owned by the test user. CI runs on
		// Linux; skip cleanly on macOS developer workstations.
		t.Skip("sshd integration test is Linux-only (CI)")
	}

	ctx, cancel := context.WithCancel(t.Context())
	t.Cleanup(cancel)

	sshdPath, err := exec.LookPath("sshd")
	if err != nil {
		t.Skipf("sshd not on PATH: %v", err)
	}
	sshPath, err := exec.LookPath("ssh")
	if err != nil {
		t.Skipf("ssh not on PATH: %v", err)
	}
	sshKeygenPath, err := exec.LookPath("ssh-keygen")
	if err != nil {
		t.Skipf("ssh-keygen not on PATH: %v", err)
	}

	currentUser, err := user.Current()
	if err != nil {
		t.Fatalf("lookup current user: %v", err)
	}
	if currentUser.Uid == "0" {
		t.Skip("sshd integration test is not run as root to avoid clobbering the host sshd")
	}

	// Build a one-off nixstasis binary so the test runs the actual production
	// helper code path (cmd/nixstasis/ssh_authorized_keys.go).
	shortRoot := shortDirForSSH(t)
	binPath := filepath.Join(shortRoot, "nixstasis")
	repoRoot := repoRootFromTest(t)
	buildCmd := exec.CommandContext(ctx, "go", "build", "-o", binPath, "./cmd/nixstasis")
	buildCmd.Dir = repoRoot
	buildCmd.Env = append(os.Environ(), "GOEXPERIMENT=jsonv2")
	if out, err := buildCmd.CombinedOutput(); err != nil {
		t.Fatalf("go build failed: %v\n%s", err, out)
	}

	socketPath := filepath.Join(shortRoot, "ssh-authority.sock")
	helperPath := filepath.Join(shortRoot, "ssh-authorized-keys")
	sshdConfigPath := filepath.Join(shortRoot, "sshd_config")
	hostKeyPath := filepath.Join(shortRoot, "host_ed25519")
	clientKeyPath := filepath.Join(shortRoot, "client_ed25519")
	knownHostsPath := filepath.Join(shortRoot, "known_hosts")
	workDir := shortRoot

	writeShellHelper(t, helperPath, binPath, socketPath)
	hostKey := generateHostKey(ctx, t, sshKeygenPath, hostKeyPath)
	clientKeyPath, clientKeyPub := generateClientKeypair(ctx, t, sshKeygenPath, clientKeyPath)
	_ = clientKeyPath
	listener, port := reserveLoopbackPort(ctx, t)
	listener.Close()

	_ = buildSshdConfig(sshdConfigPath, hostKeyPath, port, helperPath, currentUser.Username)

	sshdCmd := exec.CommandContext(ctx, sshdPath, "-D", "-e", "-f", sshdConfigPath, "-h", hostKey, "-p", fmt.Sprintf("%d", port))
	sshdCmd.Stdout = os.Stdout
	sshdCmd.Stderr = os.Stderr
	if err := sshdCmd.Start(); err != nil {
		t.Fatalf("start sshd: %v", err)
	}
	t.Cleanup(func() {
		_ = sshdCmd.Process.Signal(os.Interrupt)
		done := make(chan error, 1)
		go func() { done <- sshdCmd.Wait() }()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			_ = sshdCmd.Process.Kill()
			<-done
		}
	})

	waitForSSHDPort(ctx, t, port, 5*time.Second)

	store := NewStore()
	server := NewServer(socketPath, store)
	if err := server.Start(ctx); err != nil {
		t.Fatalf("start sshauth server: %v", err)
	}
	t.Cleanup(func() { _ = server.Close() })

	// Allow the test to run as the same user that owns the socket so we
	// don't need root or an /etc/passwd override. This still exercises the
	// full sshd + helper + IPC pipeline.
	t.Run("in store key is authorized", func(t *testing.T) {
		_, err := store.Add(clientKeyPub, currentUser.Username, "cmd-allow", "session-allow", 5*time.Minute)
		if err != nil {
			t.Fatalf("Add() error = %v", err)
		}
		stdout, stderr, err := runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "ok"})
		if err != nil {
			t.Fatalf("ssh allow failed: %v\nstderr: %s", err, stderr)
		}
		if strings.TrimSpace(stdout) != "ok" {
			t.Fatalf("expected ok, got %q", stdout)
		}
	})

	t.Run("unknown key is denied", func(t *testing.T) {
		store.RevokeAll()
		_, otherPub := generateClientKeypair(ctx, t, sshKeygenPath, filepath.Join(workDir, "unknown_ed25519"))
		_, _ = store.Add(otherPub, currentUser.Username, "cmd-unknown", "session-unknown", 5*time.Minute)

		stdout, stderr, _ := runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "should-not-print"})
		if strings.Contains(stdout, "should-not-print") {
			t.Fatalf("ssh unexpectedly authenticated: stdout=%q stderr=%q", stdout, stderr)
		}
		if !looksLikeAuthFailure(stderr) {
			t.Fatalf("expected authentication failure in stderr, got %q", stderr)
		}
	})

	t.Run("expired key is denied", func(t *testing.T) {
		store.RevokeAll()
		_, err := store.Add(clientKeyPub, currentUser.Username, "cmd-expired", "session-expired", 50*time.Millisecond)
		if err != nil {
			t.Fatalf("Add() error = %v", err)
		}
		time.Sleep(200 * time.Millisecond)

		stdout, stderr, _ := runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "stale"})
		if strings.Contains(stdout, "stale") {
			t.Fatalf("ssh unexpectedly authenticated expired key: stdout=%q stderr=%q", stdout, stderr)
		}
		if !looksLikeAuthFailure(stderr) {
			t.Fatalf("expected authentication failure in stderr, got %q", stderr)
		}
	})

	t.Run("unknown user is denied", func(t *testing.T) {
		store.RevokeAll()
		_, err := store.Add(clientKeyPub, "nope", "cmd-user", "session-user", 5*time.Minute)
		if err != nil {
			t.Fatalf("Add() error = %v", err)
		}
		stdout, stderr, _ := runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "wrong-user"})
		if strings.Contains(stdout, "wrong-user") {
			t.Fatalf("ssh unexpectedly authenticated wrong-user: stdout=%q stderr=%q", stdout, stderr)
		}
		if !looksLikeAuthFailure(stderr) {
			t.Fatalf("expected authentication failure in stderr, got %q", stderr)
		}
	})

	t.Run("revoked session is denied", func(t *testing.T) {
		store.RevokeAll()
		_, err := store.Add(clientKeyPub, currentUser.Username, "cmd-revoke", "session-revoke", 5*time.Minute)
		if err != nil {
			t.Fatalf("Add() error = %v", err)
		}

		// First login should succeed before revoke.
		stdout, stderr, err := runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "ok"})
		if err != nil {
			t.Fatalf("ssh pre-revoke failed: %v\nstderr: %s", err, stderr)
		}
		if strings.TrimSpace(stdout) != "ok" {
			t.Fatalf("expected ok pre-revoke, got %q", stdout)
		}

		// Issue an ssh_revoke to drop the entry.
		revoked := store.RevokeSession("session-revoke")
		if revoked != 1 {
			t.Fatalf("RevokeSession = %d, want 1", revoked)
		}

		stdout, stderr, _ = runSSH(ctx, t, sshPath, port, knownHostsPath, clientKeyPath, currentUser.Username, []string{"echo", "after-revoke"})
		if strings.Contains(stdout, "after-revoke") {
			t.Fatalf("ssh unexpectedly authenticated after revoke: stdout=%q stderr=%q", stdout, stderr)
		}
		if !looksLikeAuthFailure(stderr) {
			t.Fatalf("expected authentication failure in stderr, got %q", stderr)
		}
	})
}

// generateClientKeypair produces a brand new ed25519 keypair and returns both
// the path to the private key and the public key in authorized_keys form.
func generateClientKeypair(ctx context.Context, t *testing.T, sshKeygen, base string) (privPath, pubLine string) {
	t.Helper()
	cmd := exec.CommandContext(ctx, sshKeygen, "-t", "ed25519", "-N", "", "-f", base)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("ssh-keygen: %v\n%s", err, out)
	}
	pubBytes, err := os.ReadFile(base + ".pub")
	if err != nil {
		t.Fatalf("read pubkey: %v", err)
	}
	return base, strings.TrimSpace(string(pubBytes))
}

// generateHostKey produces a bare ed25519 host key (no passphrase, no comment).
func generateHostKey(ctx context.Context, t *testing.T, sshKeygen, path string) string {
	t.Helper()
	cmd := exec.CommandContext(ctx, sshKeygen, "-t", "ed25519", "-N", "", "-f", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("ssh-keygen host key: %v\n%s", err, out)
	}
	return path
}

// writeShellHelper writes the production-style wrapper that exec's the
// built nixstasis binary with the ssh-authorized-keys subcommand, exposing
// the IPC socket to the helper via the standard env var. The wrapper is
// mode 0700 to satisfy OpenSSH 10.2p1's stricter AuthorizedKeysCommand
// safe_path check.
func writeShellHelper(t *testing.T, helperPath, binPath, socketPath string) {
	t.Helper()
	content := "#!/bin/sh\nexport NIXSTASIS_SSH_AUTHORITY_SOCKET=" + socketPath + "\nexec " + binPath + " ssh-authorized-keys \"$@\"\n"
	if err := os.WriteFile(helperPath, []byte(content), 0o700); err != nil {
		t.Fatalf("write helper wrapper: %v", err)
	}
}

// buildSshdConfig writes an sshd_config that mirrors the production drop-in
// while binding to a non-privileged loopback port and using the test user as
// the AuthorizedKeysCommandUser (avoids needing root).
func buildSshdConfig(path, hostKey string, port int, helper string, username string) string {
	body := fmt.Sprintf(`Port %d
ListenAddress 127.0.0.1
HostKey %s
PidFile %s
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
LogLevel VERBOSE
StrictModes no
AuthorizedKeysFile none
AuthorizedKeysCommand %s
AuthorizedKeysCommandUser %s
Match User %s
    PubkeyAuthentication yes
    AuthorizedKeysCommand %s
    AuthorizedKeysCommandUser %s
`, port, hostKey, path+".pid", helper, username, username, helper, username)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		panic(fmt.Sprintf("write sshd_config: %v", err))
	}
	return path
}

// runSSH shells out to the system ssh client and returns combined output.
func runSSH(ctx context.Context, t *testing.T, sshPath string, port int, knownHosts, keyPath, username string, command []string) (string, string, error) {
	t.Helper()
	args := make([]string, 0, 15+len(command))
	args = append(
		args,
		"-i", keyPath,
		"-p", fmt.Sprintf("%d", port),
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile="+knownHosts,
		"-o", "PasswordAuthentication=no",
		"-o", "KbdInteractiveAuthentication=no",
		"-o", "PreferredAuthentications=publickey",
		"-o", "NumberOfPasswordPrompts=0",
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=5",
		username+"@127.0.0.1",
		"--",
	)
	args = append(args, command...)
	cmd := exec.CommandContext(ctx, sshPath, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// reserveLoopbackPort grabs a free TCP port for sshd to bind to.
func reserveLoopbackPort(ctx context.Context, t *testing.T) (net.Listener, int) {
	t.Helper()
	lc := &net.ListenConfig{}
	ln, err := lc.Listen(ctx, "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve port: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	return ln, port
}

// waitForSSHDPort polls for the sshd listener to be reachable. sshd is
// launched as a separate process; we cannot use the helper's IPC for liveness.
func waitForSSHDPort(ctx context.Context, t *testing.T, port int, timeout time.Duration) {
	t.Helper()
	dialer := &net.Dialer{Timeout: 200 * time.Millisecond}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := dialer.DialContext(ctx, "tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err == nil {
			_ = conn.Close()
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("sshd did not start listening on 127.0.0.1:%d within %s", port, timeout)
}

// looksLikeAuthFailure returns true when stderr text from ssh looks like the
// usual "Permission denied" / "publickey" failure.
func looksLikeAuthFailure(stderr string) bool {
	stderr = strings.ToLower(stderr)
	return strings.Contains(stderr, "permission denied") ||
		strings.Contains(stderr, "publickey") ||
		strings.Contains(stderr, "authentication failed")
}

// repoRootFromTest walks up from the test file to find the directory that
// contains the nixstasis client module root (i.e. cmd/nixstasis).
func repoRootFromTest(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot determine test file path")
	}
	dir := filepath.Dir(thisFile)
	for range 6 {
		if _, err := os.Stat(filepath.Join(dir, "cmd", "nixstasis")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	t.Fatalf("could not locate client repo root (no cmd/nixstasis above %s)", filepath.Dir(thisFile))
	return ""
}

// shortDirForSSH creates a uniquely named directory under the user's home
// with a short absolute path. sshd rejects AuthorizedKeysCommand paths whose
// directories fail ownership/mode checks, and on macOS os.TempDir() is a
// multi-level symlink tree that trips those checks. A $HOME-nested directory
// owned by the test user passes sshd's strict validation.
func shortDirForSSH(t *testing.T) string {
	t.Helper()
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatalf("lookup home: %v", err)
	}
	var id [4]byte
	if _, err := cryptorand.Read(id[:]); err != nil {
		t.Fatalf("read random: %v", err)
	}
	dir := filepath.Join(home, ".cache", "nixstasis-sshd-test-"+hex.EncodeToString(id[:]))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("create short sshd test dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return dir
}
