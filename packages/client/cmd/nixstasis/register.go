package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/nixstasis/packages/client/internal/transport"
)

var registerCmd = &cobra.Command{
	Use:   "register",
	Short: "Register the device with the Nixstasis server",
	RunE: func(cmd *cobra.Command, _ []string) error {
		cfg, err := commandConfig(cmd)
		if err != nil {
			return err
		}
		return runRegister(cfg)
	},
}

func init() {
	rootCmd.AddCommand(registerCmd)
}

// runRegister creates an API client and registers the device using the
// configured interface, a saved MAC, or server route detection.
func runRegister(cfg *config.Config) error {
	client, err := transport.NewClient(cfg.API)
	if err != nil {
		return err
	}
	return runRegisterWithClient(client, func(saved string) (string, error) {
		return identity.ResolveMAC(context.Background(), cfg.Identity.Interface, saved, cfg.API.URL)
	})
}

// runRegisterWithClient registers with the MAC from resolveMAC, which receives
// the MAC saved by an interrupted enrollment or an existing runtime identity.
func runRegisterWithClient(client *transport.Client, resolveMAC func(saved string) (string, error)) error {
	slog.Info("Starting registration process")

	// 1. Load any proof from an interrupted enrollment or an existing runtime
	// identity, and fix the identity MAC before the first request.
	identityPath := config.IdentityPath()
	registrationPath := config.RegistrationPath()
	identityStore := identity.NewStore(identityPath)
	registrationStore := identity.NewStore(registrationPath)
	enrollment, err := prepareRegistration(identityStore, registrationStore, resolveMAC)
	if err != nil {
		return err
	}
	mac := enrollment.MACAddress

	ip, err := identity.GetPrimaryIP(context.Background())
	if err != nil {
		slog.Warn("Failed to detect IP address", "error", err)
		ip = "0.0.0.0" // Fallback
	}

	id := identity.DeviceIdentity{
		MACAddress: mac,
		IPAddress:  ip,
		Name:       identity.GenerateDeviceName(mac),
	}
	slog.Info("Device identity detected", "name", id.Name, "mac", mac, "ip", ip)

	// 4. Register with Retries (T015)
	var credentials transport.DeviceCredentials
	maxRetries := 8
	baseDelay := 2 * time.Second
	maxDelay := 30 * time.Second

	for i := range maxRetries {
		credentials, err = client.RegisterDeviceCredentials(context.Background(), id, enrollment.Token, enrollment.ReplacementToken)
		if err == nil {
			break
		}

		message := "Registration failed"
		if errors.Is(err, transport.ErrDevicePendingApproval) {
			message = "Registration pending approval"
			if credentials.RegistrationToken != "" {
				enrollment.Token = credentials.RegistrationToken
				enrollment.UUID = credentials.UUID
				if saveErr := registrationStore.SaveEnrollment(enrollment); saveErr != nil {
					return fmt.Errorf("failed to persist registration proof: %w", saveErr)
				}
			}
		}
		slog.Warn(message, "attempt", i+1, "error", err)
		if i < maxRetries-1 {
			// Exponential backoff
			sleepDuration := min(baseDelay*time.Duration(1<<i), maxDelay)
			slog.Info("Retrying registration...", "wait_time", sleepDuration)
			time.Sleep(sleepDuration)
		}
	}

	if err != nil {
		return fmt.Errorf("failed to register device after %d retries: %w", maxRetries, err)
	}

	slog.Info("Registration successful", "uuid", credentials.UUID, "token_issued", credentials.Token != "")

	// 5. Save runtime credentials and discard the one-time enrollment proof.
	runtimeCredentials := identity.Credentials{UUID: credentials.UUID, Token: credentials.Token, MACAddress: mac}
	if err := identityStore.Save(runtimeCredentials); err != nil {
		// The server has already consumed the enrollment proof. Preserve the
		// runtime token in the retry store so a later run can exchange it for a
		// fresh token instead of retrying the stale proof.
		if recoveryErr := registrationStore.SaveEnrollment(identity.Enrollment{
			UUID: credentials.UUID, Token: credentials.Token, MACAddress: mac,
		}); recoveryErr != nil {
			return fmt.Errorf("failed to save credentials and preserve retry credentials: %w", errors.Join(err, recoveryErr))
		}
		return fmt.Errorf("failed to save credentials: %w (runtime credentials preserved for retry)", err)
	}
	if err := removeRegistrationProof(identityPath, registrationPath); err != nil {
		return err
	}

	slog.Info("Credentials persisted successfully")
	return nil
}

// removeRegistrationProof removes separate proof storage after the atomic
// identity save, preserving any path that names the newly saved identity.
func removeRegistrationProof(identityPath, registrationPath string) error {
	if registrationPath == identityPath {
		return nil
	}
	identityInfo, err := os.Stat(identityPath)
	if err != nil {
		return fmt.Errorf("failed to inspect saved identity: %w", err)
	}
	registrationInfo, err := os.Stat(registrationPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to inspect registration proof: %w", err)
	}
	if !os.SameFile(identityInfo, registrationInfo) {
		if err := identity.NewStore(registrationPath).Remove(); err != nil {
			return fmt.Errorf("failed to remove registration proof: %w", err)
		}
	}
	return nil
}

// prepareRegistration prefers recovery state over runtime credentials,
// resolves the identity MAC, and persists the enrollment proof and proposed
// runtime token before registration can send a request.
func prepareRegistration(identityStore, registrationStore *identity.Store, resolveMAC func(saved string) (string, error)) (identity.Enrollment, error) {
	// Recovery state supersedes a readable but invalidated runtime identity.
	enrollment, err := registrationStore.LoadEnrollment()
	if err != nil && !errors.Is(err, identity.ErrNoIdentity) {
		return identity.Enrollment{}, fmt.Errorf("failed to load registration state: %w", err)
	}
	if errors.Is(err, identity.ErrNoIdentity) {
		credentials, loadErr := identityStore.Load()
		if loadErr != nil && !errors.Is(loadErr, identity.ErrNoIdentity) {
			return identity.Enrollment{}, fmt.Errorf("failed to load runtime credentials: %w", loadErr)
		}
		enrollment = identity.Enrollment{UUID: credentials.UUID, Token: credentials.Token, MACAddress: credentials.MACAddress}
	}
	mac, err := resolveMAC(enrollment.MACAddress)
	if err != nil {
		return identity.Enrollment{}, fmt.Errorf("failed to detect MAC address: %w", err)
	}
	enrollment.MACAddress = mac
	if enrollment.Token == "" {
		enrollment.Token = identity.NewToken()
	}
	if enrollment.ReplacementToken == "" {
		enrollment.ReplacementToken = identity.NewToken()
	}
	// Neither a lost response nor a process restart can discard the credentials
	// the server is about to commit.
	if err := registrationStore.SaveEnrollment(enrollment); err != nil {
		return identity.Enrollment{}, fmt.Errorf("failed to prepare registration credentials: %w", err)
	}
	return enrollment, nil
}
