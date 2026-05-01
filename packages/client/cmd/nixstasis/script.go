package main

import "github.com/spf13/cobra"

var scriptCmd = &cobra.Command{
	Use:   "script",
	Short: "Manage and run stary scripts",
}

func init() {
	rootCmd.AddCommand(scriptCmd)
}
