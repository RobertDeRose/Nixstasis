package commands

import (
	"bufio"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// #nosec G304 -- callers pass validated application-owned paths.
func syncDir(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open dir for sync: %w", err)
	}
	defer dir.Close()
	if err := dir.Sync(); err != nil {
		return fmt.Errorf("sync dir: %w", err)
	}
	return nil
}

func ensureDir(path string) error {
	if err := os.MkdirAll(path, 0o750); err != nil {
		return fmt.Errorf("create scripts dir: %w", err)
	}
	return nil
}

func writeFile(dest, content string) error {
	if err := os.WriteFile(dest, []byte(content), 0o644); err != nil {
		return fmt.Errorf("write script: %w", err)
	}
	return nil
}

func removeFile(path string) error {
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove script: %w", err)
	}
	return nil
}

//nolint:gocyclo // Atomic authorized_keys updates require sequential validation, write, fsync, rename, and chmod handling.
func appendAuthorizedKey(path, key string) error {
	cleanPath, err := canonicalAuthorizedKeysPath(path)
	if err != nil {
		return err
	}
	line, err := normalizeAuthorizedKey(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(cleanPath), 0o700); err != nil {
		return fmt.Errorf("create ssh dir: %w", err)
	}

	existing, err := os.ReadFile(cleanPath) // #nosec G304 -- canonicalAuthorizedKeysPath constrains this path.
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("read authorized_keys: %w", err)
	}
	if authorizedKeyExists(existing, line) {
		return enforceAuthorizedKeysMode(cleanPath)
	}

	content := strings.TrimRight(string(existing), "\n")
	if content != "" {
		content += "\n"
	}
	content += line + "\n"

	tmp, err := os.CreateTemp(filepath.Dir(cleanPath), ".authorized_keys.*")
	if err != nil {
		return fmt.Errorf("create authorized_keys temp: %w", err)
	}
	tmpPath := tmp.Name()
	defer func() {
		if err := os.Remove(tmpPath); err != nil && !os.IsNotExist(err) {
			fmt.Fprintf(os.Stderr, "failed to remove authorized_keys temp file: %v\n", err)
		}
	}()

	if _, err := tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("write authorized_keys temp: %w", err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("chmod authorized_keys temp: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("sync authorized_keys temp: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close authorized_keys temp: %w", err)
	}
	if err := os.Rename(tmpPath, cleanPath); err != nil {
		return fmt.Errorf("replace authorized_keys: %w", err)
	}
	if err := syncDir(filepath.Dir(cleanPath)); err != nil {
		return err
	}
	return enforceAuthorizedKeysMode(cleanPath)
}

func canonicalAuthorizedKeysPath(path string) (string, error) {
	cleanPath := filepath.Clean(path)
	if !filepath.IsAbs(cleanPath) || filepath.Base(cleanPath) != "authorized_keys" {
		return "", fmt.Errorf("authorized_keys path must be absolute and end with authorized_keys")
	}
	return cleanPath, nil
}

func normalizeAuthorizedKey(key string) (string, error) {
	line := strings.TrimSpace(key)
	if line == "" || strings.ContainsAny(line, "\r\n") {
		return "", fmt.Errorf("malformed public key")
	}
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return "", fmt.Errorf("malformed public key")
	}
	switch fields[0] {
	case "ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
	default:
		return "", fmt.Errorf("unsupported public key type")
	}
	if strings.ContainsAny(fields[1], " "+"\t") {
		return "", fmt.Errorf("malformed public key")
	}
	decoded, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil {
		return "", fmt.Errorf("malformed public key")
	}
	if keyType, ok := sshKeyBlobType(decoded); !ok || keyType != fields[0] {
		return "", fmt.Errorf("malformed public key")
	}
	return strings.Join(fields, " "), nil
}

func sshKeyBlobType(blob []byte) (string, bool) {
	if len(blob) < 4 {
		return "", false
	}
	length := int(binary.BigEndian.Uint32(blob[:4]))
	if length <= 0 || length > len(blob)-4 {
		return "", false
	}
	return string(blob[4 : 4+length]), true
}

func authorizedKeyExists(existing []byte, key string) bool {
	scanner := bufio.NewScanner(strings.NewReader(string(existing)))
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) == key {
			return true
		}
	}
	return false
}

func enforceAuthorizedKeysMode(path string) error {
	if err := os.Chmod(path, 0o600); err != nil {
		return fmt.Errorf("chmod authorized_keys: %w", err)
	}
	return chownAuthorizedKeysToParent(path)
}

func chownAuthorizedKeysToParent(path string) error {
	dirInfo, err := os.Stat(filepath.Dir(path))
	if err != nil {
		return fmt.Errorf("stat authorized_keys dir: %w", err)
	}
	fileInfo, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat authorized_keys: %w", err)
	}
	dirStat, ok := dirInfo.Sys().(*syscall.Stat_t)
	if !ok {
		return nil
	}
	fileStat, ok := fileInfo.Sys().(*syscall.Stat_t)
	if !ok {
		return nil
	}
	if fileStat.Uid == dirStat.Uid && fileStat.Gid == dirStat.Gid {
		return nil
	}
	if err := os.Chown(path, int(dirStat.Uid), int(dirStat.Gid)); err != nil {
		return fmt.Errorf("chown authorized_keys: %w", err)
	}
	return nil
}
