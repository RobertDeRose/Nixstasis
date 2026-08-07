defmodule Nixstasis.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        NixstasisWeb.Telemetry,
        Nixstasis.Repo
      ] ++
        retention_children() ++
        [
          {DNSCluster, query: Application.get_env(:nixstasis, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Nixstasis.PubSub},
          # Start a worker by calling: Nixstasis.Worker.start_link(arg)
          # {Nixstasis.Worker, arg},
          {Nixstasis.Devices, :remote_access_leases},
          Nixstasis.Provisioning,
          {Nixstasis.Devices.SshKeyManager, :terminal_sessions},
          NixstasisWeb.RateLimiterStore,
          Nixstasis.Monitoring.OfflineChecker,
          Nixstasis.TLSObservations,
          # Start to serve requests, typically the last entry
          NixstasisWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nixstasis.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NixstasisWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp retention_children do
    retention_enabled? =
      Application.get_env(:nixstasis, :e2e, [])
      |> Keyword.get(:retention, [])
      |> Keyword.get(:enabled, true)

    if retention_enabled? do
      [Nixstasis.E2E.RetentionWorker]
    else
      []
    end
  end
end
