package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/spf13/cobra"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/transport"
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

func runRegister(cfg *config.Config) error {
	slog.Info("Starting registration process")

	// 1. Detect Identity
	mac, err := identity.GetPrimaryMAC()
	if err != nil {
		slog.Error("Failed to detect MAC address", "error", err)
		// We can't register without a MAC, so fatal exit
		// But in a loop we might want to retry detection?
		// For now, fail fast as hardware likely won't change in seconds.
		return fmt.Errorf("failed to detect MAC address: %w", err)
	}

	ip, err := identity.GetPrimaryIP()
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

	// 2. Setup Client
	client := transport.NewClient(cfg.API)

	// 3. Register with Retries (T015)
	var credentials transport.DeviceCredentials
	maxRetries := 8
	baseDelay := 2 * time.Second
	maxDelay := 30 * time.Second

	for i := range maxRetries {
		credentials, err = client.RegisterDeviceCredentials(context.Background(), id)
		if err == nil {
			break
		}

		message := "Registration failed"
		if errors.Is(err, transport.ErrDevicePendingApproval) {
			message = "Registration pending approval"
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

	// 4. Save credentials
	store := identity.NewStore(config.IdentityPath())
	if err := store.Save(identity.Credentials{UUID: credentials.UUID, Token: credentials.Token}); err != nil {
		return fmt.Errorf("failed to save credentials: %w", err)
	}

	slog.Info("Credentials persisted successfully")
	return nil
}
