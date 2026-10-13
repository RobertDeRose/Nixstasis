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

// ParseStaryFile reads the stary file at path and parses it with
// ParseStaryContent. A file whose size exceeds maxStarySourceBytes (1 MiB) fails
// with errStarySourceTooLarge, reporting its actual size, before any of it is
// read. The read itself is bounded to limit+1 bytes, so a file that grows after
// the size check still fails in ParseStaryContent rather than being read into
// memory. File open, stat, and read errors are wrapped; ParseStaryContent errors
// are returned unchanged.
func ParseStaryFile(path string) (FrontMatter, string, error) {
	file, err := os.Open(path) // #nosec G304 -- path is provided by the caller for script loading.
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}
	if info.Size() > maxStarySourceBytes {
		return FrontMatter{}, "", starySourceTooLargeError(info.Size())
	}

	data, err := io.ReadAll(io.LimitReader(file, maxStarySourceBytes+1))
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}

	return ParseStaryContent(string(data))
}

// ParseStaryContent splits raw stary content into YAML front-matter and a
// Starlark body. Content larger than maxStarySourceBytes (1 MiB) fails with
// errStarySourceTooLarge before any parsing. The front-matter must start with
// --- (after an optional UTF-8 byte order mark) and end with a --- line, and
// declare a non-blank name and a schema.
// Missing delimiters or required fields return an error; YAML decoding errors
// are wrapped. The body is returned with leading line breaks removed, without
// validating the Starlark or compiling the schema.
func ParseStaryContent(content string) (FrontMatter, string, error) {
	if len(content) > maxStarySourceBytes {
		return FrontMatter{}, "", starySourceTooLargeError(int64(len(content)))
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

// starySourceTooLargeError wraps errStarySourceTooLarge with the observed size
// and the limit.
func starySourceTooLargeError(size int64) error {
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
