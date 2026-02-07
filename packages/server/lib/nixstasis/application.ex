defmodule Nixstasis.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NixstasisWeb.Telemetry,
      Nixstasis.Repo,
      {DNSCluster, query: Application.get_env(:nixstasis, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Nixstasis.PubSub},
      # Start a worker by calling: Nixstasis.Worker.start_link(arg)
      # {Nixstasis.Worker, arg},
      Nixstasis.Monitoring.OfflineChecker,
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
end
