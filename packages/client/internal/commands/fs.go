package commands

import (
	"fmt"
	"os"
)

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
