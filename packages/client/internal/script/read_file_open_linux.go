//go:build linux

package script

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"
)

// secureOpenReadFile opens an already-canonicalized absolute path without
// following symbolic links in any path component. Walking from an open root
// directory fd with openat(2) keeps path resolution bound to each directory
// handle, so a component swapped to a symlink after authorization fails closed.
func secureOpenReadFile(path string) (*os.File, error) {
	clean := filepath.Clean(path)
	if !filepath.IsAbs(clean) || clean == string(os.PathSeparator) {
		return nil, fmt.Errorf("read_file path must name an absolute file: %s", path)
	}

	parts := strings.Split(strings.TrimPrefix(clean, string(os.PathSeparator)), string(os.PathSeparator))
	dirFD, err := unix.Open(string(os.PathSeparator), unix.O_PATH|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open filesystem root: %w", err)
	}

	for i, part := range parts {
		last := i == len(parts)-1
		if last {
			fd, openErr := unix.Openat(dirFD, part, unix.O_RDONLY|unix.O_CLOEXEC|unix.O_NOFOLLOW, 0)
			closeErr := unix.Close(dirFD)
			if openErr != nil {
				if closeErr != nil {
					return nil, fmt.Errorf("secure open %s: %w", clean, errors.Join(openErr, closeErr))
				}
				return nil, fmt.Errorf("secure open %s: %w", clean, openErr)
			}
			if closeErr != nil {
				if fileCloseErr := unix.Close(fd); fileCloseErr != nil {
					return nil, fmt.Errorf("secure open %s: %w", clean, errors.Join(closeErr, fileCloseErr))
				}
				return nil, fmt.Errorf("secure open %s: %w", clean, closeErr)
			}
			return os.NewFile(uintptr(fd), clean), nil
		}

		nextFD, openErr := unix.Openat(
			dirFD,
			part,
			unix.O_PATH|unix.O_DIRECTORY|unix.O_CLOEXEC|unix.O_NOFOLLOW,
			0,
		)
		closeErr := unix.Close(dirFD)
		if openErr != nil {
			if closeErr != nil {
				return nil, fmt.Errorf("secure open directory %s: %w", part, errors.Join(openErr, closeErr))
			}
			return nil, fmt.Errorf("secure open directory %s: %w", part, openErr)
		}
		if closeErr != nil {
			if nextCloseErr := unix.Close(nextFD); nextCloseErr != nil {
				return nil, fmt.Errorf("secure open directory %s: %w", part, errors.Join(closeErr, nextCloseErr))
			}
			return nil, fmt.Errorf("secure open directory %s: %w", part, closeErr)
		}
		dirFD = nextFD
	}

	if err := unix.Close(dirFD); err != nil {
		return nil, fmt.Errorf("close filesystem root: %w", err)
	}
	return nil, fmt.Errorf("read_file path must name a file: %s", path)
}
