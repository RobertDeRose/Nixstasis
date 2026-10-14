//go:build linux || darwin

package script

import (
	"fmt"
	"os"
	"strings"

	"golang.org/x/sys/unix"
)

// Walk from an opened root directory, never following symlinks or reopening a
// validated pathname. Each directory descriptor anchors the next lookup.
func openReadFile(path string) (*os.File, error) {
	fd, err := unix.Open("/", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(fd), "/")
	parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
	for index, part := range parts {
		flags := unix.O_RDONLY | unix.O_CLOEXEC | unix.O_NOFOLLOW | unix.O_NONBLOCK
		if index < len(parts)-1 {
			flags |= unix.O_DIRECTORY
		}
		next, err := unix.Openat(int(file.Fd()), part, flags, 0)
		_ = file.Close()
		if err != nil {
			return nil, fmt.Errorf("open path component without symlinks: %w", err)
		}
		file = os.NewFile(uintptr(next), path)
	}
	return file, nil
}
