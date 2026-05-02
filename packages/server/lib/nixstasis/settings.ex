defmodule Nixstasis.Settings do
  @moduledoc """
  Context for system settings.
  """

  alias Nixstasis.Domain

  def get_setting(key, default \\ nil) do
    case Domain.get_setting_by_key(key) do
      {:ok, nil} -> default
      {:ok, setting} -> setting.value
      {:error, _} -> default
    end
  end

  def put_setting(key, value) do
    case Domain.get_setting_by_key(key) do
      {:ok, nil} ->
        Domain.create_setting(%{key: key, value: value})

      {:ok, setting} ->
        Domain.update_setting(setting, %{value: value})

      {:error, error} ->
        {:error, error}
    end
  end

  def get_offline_window do
    get_setting("offline_window", %{"minutes" => 10})
    |> Map.get("minutes")
    |> case do
      v when is_binary(v) -> String.to_integer(v)
      v when is_integer(v) -> v
      _ -> 10
    end
  end

  def get_notifications_config do
    get_setting("notifications", %{"email" => nil, "webhook_url" => nil})
  end
end
