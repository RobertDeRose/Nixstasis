//go:build linux

package script

import (
	"os/exec"
	"syscall"
)

func setExecUser(cmd *exec.Cmd, user *ExecUser) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Credential: &syscall.Credential{
			Uid: user.UID,
			Gid: user.GID,
		},
	}
}
