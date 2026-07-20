import Config
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :nixstasis, Nixstasis.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "nixstasis_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nixstasis, NixstasisWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "DyEo0UgkV/xV5vL2aju1u25ASSxsJfIoBA5v5tR6Ziun20nkoN2jCbfGAWv4ECn3",
  server: false

# In test we don't send emails
config :nixstasis, Nixstasis.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# E2E defaults for test environment
config :nixstasis, :e2e_journey_dir, Path.expand("../../client/scripts/e2e/journeys", __DIR__)

config :nixstasis, :e2e,
  allowed_env_labels: ["local", "test"],
  protocol_versions: ["1"],
  environments: %{
    "local" => %{
      base_url: "http://localhost:4000",
      seed_script: "e2e/seed.exs"
    }
  },
  suites: %{
    "full" => ["auth", "dashboard", "create_record", "update_record", "logout"],
    "runtime" => ["runtime_linux_telemetry", "runtime_transport_contract", "runtime_transport_negative"],
    # Focused suite for validating optional custom step labels (step_id != action).
    "runtime_step_labels" => ["runtime_step_labels"]
  },
  log_dir: "priv/e2e/logs",
  report_dir: "priv/e2e/reports",
  retention: [
    enabled: false,
    retention_days: 14,
    max_run_count: 2000,
    max_log_bytes: 1_000_000_000,
    check_interval_ms: 60_000
  ]

config :nixstasis, :base_domain, "devices.example.com"
config :nixstasis, :local_browser_auth_fallback?, true
