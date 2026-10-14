//go:build linux

package script

import (
	"context"
	"testing"
	"time"
)

func TestReadFileSupportsSymlinkFreeProcDiagnostics(t *testing.T) {
	for _, path := range []string{"/proc/1/comm", "/proc/1/net/route"} {
		runtime := NewRuntime(RuntimeConfig{Timeout: time.Second, ReadFileAllowlist: []string{path}})
		result, err := runtime.Execute(context.Background(), "test.star", `def main():
    return {"out": read_file(path="`+path+`")}`)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		if result["out"] == "" {
			t.Fatalf("empty diagnostic: %s", path)
		}
	}
}
