//go:build linux

package script

import (
	"os/exec"

	"golang.org/x/sys/unix"
)

func setExecUser(cmd *exec.Cmd, user *ExecUser) {
	cmd.SysProcAttr = &unix.SysProcAttr{
		Credential: &unix.Credential{
			Uid: user.UID,
			Gid: user.GID,
		},
	}
}
