package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/sfero-nixstasis/client/internal/identity"
	"github.com/sfero-nixstasis/client/internal/transport"
	"github.com/spf13/cobra"
)

var registerCmd = &cobra.Command{
	Use:   "register",
	Short: "Register the device with the Nixstasis server",
	Run: func(_ *cobra.Command, _ []string) {
		runRegister()
	},
}

func init() {
	rootCmd.AddCommand(registerCmd)
}

func runRegister() {
	slog.Info("Starting registration process")

	// 1. Detect Identity
	mac, err := identity.GetPrimaryMAC()
	if err != nil {
		slog.Error("Failed to detect MAC address", "error", err)
		// We can't register without a MAC, so fatal exit
		// But in a loop we might want to retry detection?
		// For now, fail fast as hardware likely won't change in seconds.
		return
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
	var uuid string
	maxRetries := 5
	baseDelay := 2 * time.Second

	for i := range maxRetries {
		uuid, err = client.RegisterDevice(context.Background(), id)
		if err == nil {
			break
		}

		slog.Warn("Registration failed", "attempt", i+1, "error", err)
		if i < maxRetries-1 {
			// Exponential backoff
			sleepDuration := baseDelay * time.Duration(1<<i)
			slog.Info("Retrying registration...", "wait_time", sleepDuration)
			time.Sleep(sleepDuration)
		}
	}

	if err != nil {
		slog.Error("Failed to register device after retries", "error", err)
		// Return with error code
		os.Exit(1)
	}

	slog.Info("Registration successful", "uuid", uuid)

	// 4. Save UUID
	store := identity.NewStore("/etc/nixstasis/id") // TODO: Make configurable via cfg
	if err := store.SaveUUID(uuid); err != nil {
		slog.Error("Failed to save UUID", "error", err)
		return
	}

	slog.Info("UUID persisted successfully")
}
