defmodule Nixstasis.E2E.Reset do
  @moduledoc """
  Test helper for resetting E2E baseline data.
  """

  def reset!(environment_label) when is_binary(environment_label) do
    case seed_script_path(environment_label) do
      {:ok, path} ->
        Code.eval_file(path)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_script_path(environment_label) do
    config = Application.get_env(:nixstasis, :e2e, [])
    envs = Keyword.get(config, :environments, %{})

    case Map.fetch(envs, environment_label) do
      {:ok, env} ->
        seed = Map.get(env, :seed_script)

        path = seed && Path.join(Application.app_dir(:nixstasis, "priv"), seed)

        if path && File.exists?(path) do
          {:ok, path}
        else
          {:error, "Seed script not found for #{environment_label}"}
        end

      :error ->
        {:error, "Environment #{environment_label} not configured"}
    end
  end
end
