defmodule Nixstasis.Settings do
  @moduledoc """
  Context for system settings.
  """
  import Ecto.Query, warn: false
  alias Nixstasis.Repo
  alias Nixstasis.SystemSetting

  def get_setting(key, default \\ nil) do
    case Repo.get_by(SystemSetting, key: key) do
      nil -> default
      setting -> setting.value
    end
  end

  def put_setting(key, value) do
    case Repo.get_by(SystemSetting, key: key) do
      nil ->
        %SystemSetting{}
        |> SystemSetting.changeset(%{key: key, value: value})
        |> Repo.insert()

      setting ->
        setting
        |> SystemSetting.changeset(%{value: value})
        |> Repo.update()
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
