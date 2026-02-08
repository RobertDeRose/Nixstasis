package script

import (
	"fmt"
	"os"
	"strings"

	"go.yaml.in/yaml/v3"
)

// ParseStaryFile reads a stary file from disk and returns its front-matter and body.
func ParseStaryFile(path string) (FrontMatter, string, error) {
	data, err := os.ReadFile(path) // #nosec G304 -- path is provided by the caller for script loading.
	if err != nil {
		return FrontMatter{}, "", fmt.Errorf("read stary file: %w", err)
	}

	return ParseStaryContent(string(data))
}

// ParseStaryContent parses raw stary content into front-matter and body.
func ParseStaryContent(content string) (FrontMatter, string, error) {
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
