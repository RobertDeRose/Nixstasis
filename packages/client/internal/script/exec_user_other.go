//go:build !linux

package script

import "os/exec"

func setExecUser(_ *exec.Cmd, _ *ExecUser) {
	// No-op on non-Linux platforms.
}
