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
        if setting_not_found?(error) do
          Domain.create_setting(%{key: key, value: value})
        else
          {:error, error}
        end
    end
  end

  def get_offline_window do
    get_setting("offline_window", %{"minutes" => 10})
    |> Map.get("minutes")
    |> parse_positive_integer(10)
  end

  def get_notifications_config do
    get_setting("notifications", %{"email" => nil, "webhook_url" => nil})
  end

  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  defp parse_positive_integer(_value, default), do: default

  defp setting_not_found?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &setting_not_found?/1)
  end

  defp setting_not_found?(%Ash.Error.Query.NotFound{}), do: true
  defp setting_not_found?(_error), do: false
end
