defmodule Nixstasis.E2E.LogStore do
  @moduledoc """
  Simple file-backed log storage for per-journey E2E logs.
  """

  def write_log(run_id, journey_id, content) when is_binary(run_id) and is_binary(journey_id) do
    write_log(run_id, nil, journey_id, content)
  end

  def write_log(run_id, sequence, journey_id, content)
      when is_binary(run_id) and is_binary(journey_id) do
    dir = log_dir()
    File.mkdir_p!(dir)

    run_dir = Path.join(dir, run_id)
    File.mkdir_p!(run_dir)

    filename = log_filename(sequence, journey_id)
    path = Path.join(run_dir, filename)
    File.write!(path, content)
    {:ok, path}
  end

  def read_log(path) when is_binary(path) do
    with {:ok, expanded} <- expand_log_path(path) do
      case File.read(expanded) do
        {:ok, content} ->
          {:ok, content}

        {:error, :enoent} ->
          {:error, :log_unavailable}

        {:error, reason} ->
          {:error, {:read_failed, reason}}
      end
    end
  end

  def delete_log(nil), do: :ok

  def delete_log(path) when is_binary(path) do
    with {:ok, expanded} <- expand_log_path(path) do
      case File.rm(expanded) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, {:delete_failed, reason}}
      end
    end
  end

  def delete_run_dir(run_id) when is_binary(run_id) do
    allowed_log_dirs()
    |> Enum.reduce(:ok, fn base_dir, acc ->
      case acc do
        :ok -> delete_run_dir_in_base(base_dir, run_id)
        {:error, _reason} = error -> error
      end
    end)
  end

  def log_dir do
    config = Application.get_env(:nixstasis, :e2e, [])
    raw = Keyword.get(config, :log_dir, "priv/e2e/logs")
    expand_path(raw)
  end

  def allowed_log_dirs do
    server_dir = log_dir()
    client_dir = Path.expand("../client/tmp/e2e/logs", File.cwd!())
    Enum.uniq([server_dir, client_dir])
  end

  def expand_log_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    if allowed_log_path?(expanded) do
      {:ok, expanded}
    else
      {:error, :outside_allowed_dirs}
    end
  end

  def log_size(path) when is_binary(path) do
    with {:ok, expanded} <- expand_log_path(path) do
      case File.stat(expanded) do
        {:ok, %File.Stat{size: size}} -> {:ok, size}
        {:error, :enoent} -> {:error, :log_unavailable}
        {:error, reason} -> {:error, {:stat_failed, reason}}
      end
    end
  end

  defp expand_path(path) do
    case Path.type(path) do
      :absolute -> path
      :relative -> Path.expand(path, File.cwd!())
    end
  end

  defp allowed_log_path?(expanded) do
    Enum.any?(allowed_log_dirs(), fn dir ->
      expanded == dir or String.starts_with?(expanded, dir <> "/")
    end)
  end

  defp delete_run_dir_in_base(base_dir, run_id) do
    run_dir = Path.expand(Path.join(base_dir, run_id))

    with {:ok, expanded} <- expand_log_path(run_dir) do
      case File.rm_rf(expanded) do
        {:ok, _paths} -> :ok
        {:error, reason, _path} -> {:error, {:delete_failed, reason}}
      end
    end
  end

  defp log_filename(nil, journey_id), do: "#{journey_id}.log"
  defp log_filename(sequence, journey_id) when is_integer(sequence), do: "#{pad_sequence(sequence)}-#{journey_id}.log"
  defp log_filename(sequence, journey_id) when is_binary(sequence), do: "#{sequence}-#{journey_id}.log"

  defp pad_sequence(sequence) when sequence < 0, do: "000"
  defp pad_sequence(sequence), do: sequence |> Integer.to_string() |> String.pad_leading(3, "0")
end
