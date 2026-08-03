package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/sshauth"
)

const (
	envSSHAuthoritySocket = "NIXSTASIS_SSH_AUTHORITY_SOCKET"
	helperDialTimeout     = 5 * time.Second
)

var sshAuthorizedKeysCmd = &cobra.Command{
	Use:    "ssh-authorized-keys",
	Short:  "AuthorizedKeysCommand helper: print a key on stdout if it is authorized (Nixstasis internal)",
	Hidden: true,
	Args:   cobra.ExactArgs(3),
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSSHAuthorizedKeys(cmd.Context(), args[0], args[1], args[2])
	},
}

func init() {
	rootCmd.AddCommand(sshAuthorizedKeysCmd)
}

// runSSHAuthorizedKeys is invoked by sshd's AuthorizedKeysCommand. The
// contract is: write the canonical authorized_keys line to stdout for
// authorized offers, exit 0 with empty stdout for denies, and exit non-zero
// only on hard errors that the operator should see.
func runSSHAuthorizedKeys(ctx context.Context, username, keyType, keyBlob string) error {
	line, err := authorizedKeyLine(ctx, username, keyType, keyBlob)
	if err != nil {
		return err
	}
	if line == "" {
		return nil
	}

	if _, err := fmt.Printf("%s\n", line); err != nil {
		return fmt.Errorf("write authorized key to stdout: %w", err)
	}
	return nil
}

func authorizedKeyLine(ctx context.Context, username, keyType, keyBlob string) (string, error) {
	if username == "" {
		return "", fmt.Errorf("missing username argument")
	}
	offeredKey, err := sshauth.ParseOfferedKey(keyType, keyBlob)
	if err != nil {
		return "", err
	}

	socketPath := strings.TrimSpace(os.Getenv(envSSHAuthoritySocket))
	if socketPath == "" {
		socketPath = sshauth.DefaultSocketPath
	}

	dialCtx, cancel := context.WithTimeout(ctx, helperDialTimeout)
	defer cancel()

	resp, err := sshauth.Query(dialCtx, socketPath, sshauth.QueryRequest{
		User:    username,
		KeyType: keyType,
		KeyBlob: keyBlob,
	})
	if err != nil {
		slog.Debug("ssh-authorized-keys query failed", "socket", socketPath, "error", err)
		// Treat lookup errors as "not authorized" for sshd: exit 0 with
		// empty stdout. Operators see the failure via the journal entry
		// above and via sshd's own AuthorizedKeysCommand logging.
		return "", nil
	}
	if !resp.Authorized {
		return "", nil
	}

	authorizedKey, err := sshauth.ParseOfferedKey(resp.KeyType, resp.KeyBlob)
	if err != nil {
		return "", fmt.Errorf("invalid authorized key response: %w", err)
	}
	if authorizedKey.Type != offeredKey.Type || authorizedKey.Blob != offeredKey.Blob {
		return "", fmt.Errorf("authorized key response does not match offered key")
	}
	return offeredKey.Line, nil
}
