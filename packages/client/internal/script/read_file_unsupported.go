//go:build !linux && !darwin

package script

import (
	"fmt"
	"os"
)

func openReadFile(_ string) (*os.File, error) {
	return nil, fmt.Errorf("secure read_file is unsupported on this platform")
}
