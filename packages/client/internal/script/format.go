package script

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"go.yaml.in/yaml/v3"
)

// maxStarySourceBytes bounds script source before YAML/Starlark parsing begins.
// Parsing itself happens before runtime execution limits can take effect, so the
// source must be bounded independently.
const maxStarySourceBytes = 1 << 20

var errStarySourceTooLarge = errors.New("stary source exceeds maximum size")

// ParseStaryFile reads a stary file from disk and returns its front-matter and body.
func ParseStaryFile(path string) (FrontMatter, string, error) {
	file, err := os.Open(path) // #nosec G304 -- path is provided by the caller for script loading.
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, maxStarySourceBytes+1))
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}
	if len(data) > maxStarySourceBytes {
		return FrontMatter{}, "", starySourceTooLargeError(len(data))
	}

	return ParseStaryContent(string(data))
}

// ParseStaryContent parses raw stary content into front-matter and body.
func ParseStaryContent(content string) (FrontMatter, string, error) {
	if len(content) > maxStarySourceBytes {
		return FrontMatter{}, "", starySourceTooLargeError(len(content))
	}

	front, body, err := splitFrontMatter(content)
	if err != nil {
		return FrontMatter{}, "", err
	}

	var fm FrontMatter
	if err := yaml.Unmarshal([]byte(front), &fm); err != nil {
		return FrontMatter{}, "", fmt.Errorf("parse front-matter: %w", err)
	}

	if strings.TrimSpace(fm.Name) == "" {
		return FrontMatter{}, "", fmt.Errorf("front-matter missing name")
	}
	if fm.Schema == nil {
		return FrontMatter{}, "", fmt.Errorf("front-matter missing schema")
	}

	return fm, body, nil
}

func starySourceTooLargeError(size int) error {
	return fmt.Errorf("%w: %d bytes exceeds %d-byte limit", errStarySourceTooLarge, size, maxStarySourceBytes)
}

func splitFrontMatter(content string) (frontMatter, body string, err error) {
	trimmed := strings.TrimLeft(content, "\ufeff")
	if !strings.HasPrefix(trimmed, "---") {
		return "", "", fmt.Errorf("front-matter must start with ---")
	}

	rest := strings.TrimPrefix(trimmed, "---")
	switch {
	case strings.HasPrefix(rest, "\r\n"):
		rest = rest[2:]
	case strings.HasPrefix(rest, "\n"):
		rest = rest[1:]
	case strings.HasPrefix(rest, "\r"):
		rest = rest[1:]
	}

	lines := strings.Split(rest, "\n")
	frontLines := make([]string, 0, len(lines))
	for i, line := range lines {
		if strings.TrimSpace(line) == "---" {
			front := strings.Join(frontLines, "\n")
			body := strings.Join(lines[i+1:], "\n")
			body = strings.TrimLeft(body, "\r\n")
			return front, body, nil
		}
		frontLines = append(frontLines, line)
	}

	return "", "", fmt.Errorf("front-matter terminator not found")
}
