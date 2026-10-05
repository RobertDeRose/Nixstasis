//go:build !linux

package script

import (
	"os"
	"path/filepath"
)

// Production client artifacts target Linux. Keep non-Linux development builds
// constrained to the canonical target's parent directory as a best-effort
// equivalent of the descriptor-relative Linux open path.
func secureOpenReadFile(path string) (*os.File, error) {
	return os.OpenInRoot(filepath.Dir(path), filepath.Base(path))
}
