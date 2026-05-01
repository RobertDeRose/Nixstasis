package main

import (
	"fmt"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/script"
)

var listScriptsCmd = &cobra.Command{
	Use:   "list",
	Short: "List available stary scripts",
	RunE: func(cmd *cobra.Command, _ []string) error {
		scripts, err := script.DiscoverScripts(cfg.Scripts.Dir)
		if err != nil {
			return err
		}

		writer := tabwriter.NewWriter(cmd.OutOrStdout(), 2, 4, 2, ' ', 0)
		if _, err := fmt.Fprintln(writer, "NAME\tVERSION\tPATH"); err != nil {
			return err
		}
		for _, info := range scripts {
			if _, err := fmt.Fprintf(writer, "%s\t%s\t%s\n", info.Name, info.Version, info.Path); err != nil {
				return err
			}
		}
		return writer.Flush()
	},
}

func init() {
	scriptCmd.AddCommand(listScriptsCmd)
}
