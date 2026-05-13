// Package config handles configuration loading from files and environment variables.
package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/viper"
)

const (
	defaultConfigRoot         = "/etc/nixstasis"
	defaultUserConfig         = "$HOME/.config/nixstasis"
	defaultScriptsDir         = "/usr/libexec/nixstasis/scripts"
	defaultAuthorizedKeysPath = "/var/lib/nixstasis/.ssh/authorized_keys"
	defaultFRPCBinary         = "/usr/libexec/nixstasis/frpc"
	defaultFRPCConfig         = "/etc/nixstasis/frpc.toml"
)

// Config holds the top-level configuration structure.
type Config struct {
	API     APIConfig     `mapstructure:"api"`
	Poll    PollConfig    `mapstructure:"poll"`
	Scripts ScriptsConfig `mapstructure:"scripts"`
	FRP     FRPConfig     `mapstructure:"frp"`
	Runtime RuntimeConfig `mapstructure:"runtime"`
	Log     LogConfig     `mapstructure:"log"`
}

// APIConfig holds configuration for the Nixstasis API.
type APIConfig struct {
	URL string `mapstructure:"url"`
}

// PollConfig holds configuration for the polling loop.
type PollConfig struct {
	Interval time.Duration `mapstructure:"interval"`
}

// ScriptsConfig holds configuration for script discovery and execution.
type ScriptsConfig struct {
	Dir string `mapstructure:"dir"`
}

// FRPConfig holds configuration for FRP tunnel connectivity.
type FRPConfig struct {
	AuthToken string `mapstructure:"auth_token"`
	Name      string `mapstructure:"name"`
}

// RuntimeConfig holds opt-in script command capabilities.
type RuntimeConfig struct {
	MQTTBroker          string            `mapstructure:"mqtt_broker"`
	ExecCommands        map[string]string `mapstructure:"exec_commands"`
	ExecWorkDir         string            `mapstructure:"exec_work_dir"`
	ExecEnv             []string          `mapstructure:"exec_env"`
	MQTTPublishTopics   []string          `mapstructure:"mqtt_publish_topics"`
	MQTTSubscribeTopics []string          `mapstructure:"mqtt_subscribe_topics"`
	AuthorizedKeysPath  string            `mapstructure:"authorized_keys_path"`
}

// LogConfig holds configuration for logging.
type LogConfig struct {
	Level  string `mapstructure:"level"`
	Format string `mapstructure:"format"` // json or text
}

func setDefaults() *viper.Viper {
	v := viper.New()

	// Defaults
	v.SetDefault("api.url", "http://localhost:4000")
	v.SetDefault("poll.interval", 10*time.Second)
	v.SetDefault("scripts.dir", defaultScriptsDir)
	v.SetDefault("frp.auth_token", "")
	v.SetDefault("frp.name", "")
	v.SetDefault("runtime.exec_work_dir", "/")
	v.SetDefault("runtime.authorized_keys_path", defaultAuthorizedKeysPath)
	v.SetDefault("log.level", "info")
	v.SetDefault("log.format", "text")

	return v
}

// GetDefaultConfig returns a Config struct populated with default values.
func GetDefaultConfig() (*Config, error) {
	v := setDefaults()

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal default config: %w", err)
	}

	return &cfg, nil
}

// Load reads configuration from file and environment variables.
func Load() (*Config, error) {
	v := setDefaults()

	// Config File
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	if configFile := os.Getenv("NIXSTASIS_CONFIG_FILE"); configFile != "" {
		v.SetConfigFile(configFile)
	}
	v.AddConfigPath(defaultConfigRoot)
	v.AddConfigPath(defaultUserConfig)
	v.AddConfigPath(".")

	// Environment Variables
	v.SetEnvPrefix("nixstasis")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	if err := v.ReadInConfig(); err != nil {
		// It's okay if config file doesn't exist, we have defaults
		var configFileNotFoundError viper.ConfigFileNotFoundError
		if !errors.As(err, &configFileNotFoundError) {
			return nil, err
		}
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// IdentityPath returns the canonical identity file path.
func IdentityPath() string {
	if path := os.Getenv("NIXSTASIS_IDENTITY_PATH"); path != "" {
		return path
	}

	return filepath.Join(defaultConfigRoot, "id")
}

// FRPCConfigPath returns the canonical frpc config path.
func FRPCConfigPath() string {
	if path := os.Getenv("NIXSTASIS_FRPC_CONFIG_PATH"); path != "" {
		return path
	}

	return defaultFRPCConfig
}

// FRPCBinaryPath returns the canonical bundled frpc path.
func FRPCBinaryPath() string {
	if path := os.Getenv("NIXSTASIS_FRPC_BINARY_PATH"); path != "" {
		return path
	}

	return defaultFRPCBinary
}

// DefaultScriptsDir returns the canonical scripts directory.
func DefaultScriptsDir() string {
	return defaultScriptsDir
}
