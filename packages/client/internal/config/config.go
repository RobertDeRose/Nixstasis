// Package config handles configuration loading from files and environment variables.
package config

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config holds the top-level configuration structure.
type Config struct {
	API     APIConfig     `mapstructure:"api"`
	Poll    PollConfig    `mapstructure:"poll"`
	Scripts ScriptsConfig `mapstructure:"scripts"`
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
	v.SetDefault("scripts.dir", "/usr/libexec/nixstasis/scripts")
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
	v.AddConfigPath("/etc/nixstasis")
	v.AddConfigPath("$HOME/.config/nixstasis")
	v.AddConfigPath(".")

	// Environment Variables
	v.SetEnvPrefix("nixstasis")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	if err := v.ReadInConfig(); err != nil {
		// It's okay if config file doesn't exist, we have defaults
		var configFileNotFoundError viper.ConfigFileNotFoundError
		if errors.As(err, &configFileNotFoundError) {
			return nil, err
		}
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}
