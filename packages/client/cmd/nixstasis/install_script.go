package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
)

var installForce bool

var installScriptCmd = &cobra.Command{
	Use:   "install <path>",
	Short: "Install a stary script",
	Args:  cobra.ExactArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		path := args[0]

		fm, _, err := script.ParseStaryFile(path)
		if err != nil {
			return err
		}
		if _, err := script.CompileSchema(fm.Schema); err != nil {
			return err
		}
		versionNumber, err := script.ParseVersionNumber(fm.Version)
		if err != nil {
			return err
		}
		if strings.Contains(fm.Name, string(filepath.Separator)) {
			return fmt.Errorf("script name contains path separators")
		}

		installDir := script.DefaultInstallDir()
		if err := os.MkdirAll(installDir, 0o750); err != nil {
			return fmt.Errorf("create scripts dir: %w", err)
		}

		existing, err := script.DiscoverScripts(installDir)
		if err != nil {
			return err
		}
		if maxVersion, ok := script.MaxVersion(existing, fm.Name); ok && versionNumber <= maxVersion && !installForce {
			return fmt.Errorf("script version must be greater than v%d (use --force to overwrite)", maxVersion)
		}

		destPath := filepath.Join(installDir, script.InstallFilename(fm.Name, fm.Version))
		if _, err := os.Stat(destPath); err == nil && !installForce {
			return fmt.Errorf("script already exists: %s (use --force to overwrite)", destPath)
		}

		data, err := os.ReadFile(path) // #nosec G304 -- path is provided by the user for installation.
		if err != nil {
			return fmt.Errorf("read script: %w", err)
		}

		if err := os.WriteFile(destPath, data, 0o644); err != nil {
			return fmt.Errorf("write script: %w", err)
		}

		if fm.Version != "" {
			fmt.Printf("Installed %s (%s) at %s\n", fm.Name, fm.Version, destPath)
		} else {
			fmt.Printf("Installed %s at %s\n", fm.Name, destPath)
		}
		return nil
	},
}

func init() {
	installScriptCmd.Flags().BoolVar(&installForce, "force", false, "overwrite existing script")
	scriptCmd.AddCommand(installScriptCmd)
}
