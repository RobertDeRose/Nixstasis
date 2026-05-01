package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
)

var removeScriptCmd = &cobra.Command{
	Use:   "remove <name>",
	Short: "Remove an installed stary script",
	Args:  cobra.ExactArgs(1),
	RunE: func(_ *cobra.Command, args []string) error {
		name := args[0]
		installDir := script.DefaultInstallDir()

		scripts, err := script.DiscoverScripts(installDir)
		if err != nil {
			return err
		}

		var matches []script.ScriptInfo
		for _, info := range scripts {
			if info.Name == name {
				matches = append(matches, info)
			}
		}

		if len(matches) == 0 {
			return fmt.Errorf("script not found: %s", name)
		}
		selected := matches[0]
		if len(matches) > 1 {
			if latest, ok := script.LatestScript(matches, name); ok {
				selected = latest
			} else {
				return fmt.Errorf("multiple scripts named %s; remove by path", name)
			}
		}

		if err := os.Remove(selected.Path); err != nil {
			return fmt.Errorf("remove script: %w", err)
		}

		if selected.Version != "" {
			fmt.Printf("Removed %s (%s)\n", name, selected.Version)
		} else {
			fmt.Printf("Removed %s\n", name)
		}
		return nil
	},
}

func init() {
	scriptCmd.AddCommand(removeScriptCmd)
}
