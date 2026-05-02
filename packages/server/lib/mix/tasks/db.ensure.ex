defmodule Mix.Tasks.Db.Ensure do
  @moduledoc """
  Ensures a local PostgreSQL database is available for development and tests.
  """

  use Mix.Task

  @shortdoc "Starts a local Postgres container for DB-backed tasks when needed"

  @default_image "postgres:16-alpine"
  @default_container "nixstasis-postgres"
  @startup_attempts 60
  @startup_delay_ms 500

  @impl Mix.Task
  def run(_args) do
    if should_manage_container?() do
      ensure_local_database!()
    end
  end

  defp should_manage_container? do
    Mix.env() in [:dev, :test] and autostart_enabled?() and local_hostname?()
  end

  defp autostart_enabled? do
    System.get_env("NIXSTASIS_DB_AUTOSTART", "true")
    |> String.downcase()
    |> then(&(&1 not in ["0", "false", "no"]))
  end

  defp local_hostname? do
    hostname() in ["localhost", "127.0.0.1", "::1"]
  end

  defp ensure_local_database! do
    if port_open?() do
      :ok
    else
      engine = container_engine!()
      settings = settings()

      case container_state(engine, settings.container_name) do
        :running -> :ok
        :stopped -> start_container!(engine, settings)
        :missing -> create_container!(engine, settings)
      end

      wait_for_postgres!(engine, settings)
    end

    ensure_database_exists!()
  end

  defp ensure_database_exists! do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    {:ok, conn} =
      Postgrex.start_link(
        hostname: hostname(),
        port: port(),
        username: username(),
        password: password(),
        database: maintenance_database(),
        backoff_type: :stop,
        prepare: :unnamed
      )

    try do
      database = database_name()
      escaped_database = String.replace(database, "'", "''")

      query =
        "SELECT 1 FROM pg_database WHERE datname = '#{escaped_database}'"

      %Postgrex.Result{rows: rows} = Postgrex.query!(conn, query, [])

      case rows do
        [[1]] -> :ok
        [["1"]] -> :ok
        _ -> Postgrex.query!(conn, ~s(CREATE DATABASE "#{database}"), [])
      end
    after
      GenServer.stop(conn, :normal)
    end
  end

  defp container_engine! do
    System.find_executable("container") ||
      System.find_executable("docker") ||
      System.find_executable("podman") ||
      Mix.raise(
        "No local database is listening on #{hostname()}:#{port()} and none of container, docker, or podman is installed. " <>
          "Install one of them, start Postgres manually, or set NIXSTASIS_DB_AUTOSTART=false."
      )
  end

  defp settings do
    %{
      container_name: System.get_env("NIXSTASIS_DB_CONTAINER", @default_container),
      image: System.get_env("NIXSTASIS_DB_IMAGE", @default_image),
      username: username(),
      password: password(),
      database: database_name(),
      port: Integer.to_string(port())
    }
  end

  defp create_container!(engine, settings) do
    Mix.shell().info("Starting #{settings.container_name} via #{Path.basename(engine)} for #{Mix.env()} tasks")

    args = [
      "run",
      "--detach",
      "--name",
      settings.container_name,
      "--publish",
      "#{settings.port}:5432",
      "--env",
      "POSTGRES_USER=#{settings.username}",
      "--env",
      "POSTGRES_PASSWORD=#{settings.password}",
      "--env",
      "POSTGRES_DB=#{settings.database}",
      settings.image
    ]

    case run_cmd(engine, args) do
      {_output, 0} -> :ok
      {output, _status} ->
        case container_state(engine, settings.container_name) do
          :running -> :ok
          :stopped -> start_container!(engine, settings)
          :missing -> Mix.raise("Failed to start local Postgres container:\n\n#{output}")
        end
    end
  end

  defp start_container!(engine, settings) do
    Mix.shell().info("Starting existing #{settings.container_name} via #{Path.basename(engine)}")

    case run_cmd(engine, ["start", settings.container_name]) do
      {_output, 0} -> :ok
      {output, _status} -> Mix.raise("Failed to start #{settings.container_name}:\n\n#{output}")
    end
  end

  defp wait_for_postgres!(engine, settings, attempt \\ 1)

  defp wait_for_postgres!(_engine, settings, attempt) when attempt > @startup_attempts do
    Mix.raise(
      "Timed out waiting for #{settings.container_name} to accept Postgres connections on port #{settings.port}."
    )
  end

  defp wait_for_postgres!(engine, settings, attempt) do
    case run_cmd(engine, ["exec", settings.container_name, "pg_isready", "-U", settings.username, "-d", settings.database]) do
      {_output, 0} -> :ok
      _result ->
        Process.sleep(@startup_delay_ms)
        wait_for_postgres!(engine, settings, attempt + 1)
    end
  end

  defp container_state(engine, container_name) do
    case run_cmd(engine, ["inspect", "--format", "{{.State.Running}}", container_name]) do
      {"true", 0} -> :running
      {"false", 0} -> :stopped
      {_output, _status} -> :missing
    end
  end

  defp port_open? do
    host =
      case hostname() do
        "localhost" -> {127, 0, 0, 1}
        "127.0.0.1" -> {127, 0, 0, 1}
        "::1" -> {0, 0, 0, 0, 0, 0, 0, 1}
      end

    case :gen_tcp.connect(host, port(), [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp run_cmd(executable, args) do
    {output, status} = System.cmd(executable, args, stderr_to_stdout: true)
    {String.trim(output), status}
  end

  defp repo_config do
    Application.get_env(:nixstasis, Nixstasis.Repo, [])
  end

  defp hostname do
    Keyword.get(repo_config(), :hostname, "localhost")
  end

  defp port do
    Keyword.get(repo_config(), :port, 5432)
  end

  defp username do
    Keyword.get(repo_config(), :username, "postgres")
  end

  defp password do
    Keyword.get(repo_config(), :password, "postgres")
  end

  defp database_name do
    Keyword.fetch!(repo_config(), :database)
  end

  defp maintenance_database do
    System.get_env("NIXSTASIS_DB_MAINTENANCE_DATABASE", "postgres")
  end
end
