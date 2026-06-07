package commands

import (
	"fmt"
	"os"
)

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
