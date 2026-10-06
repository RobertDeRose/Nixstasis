defmodule Nixstasis.Settings do
  @moduledoc """
  Context for system settings.
  """

  alias Nixstasis.Domain
  alias Nixstasis.Notifications.Webhook

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

  def put_offline_window(%{"can_manage" => true}, minutes) do
    put_setting("offline_window", %{"minutes" => minutes})
  end

  def put_offline_window(_permissions, _minutes), do: {:error, :forbidden}

  def put_notifications_config(%{"can_manage" => true}, params) when is_map(params) do
    existing = get_notifications_config()

    with {:ok, webhook_url} <- next_webhook_url(existing, params) do
      put_setting("notifications", %{
        "email" => normalize_optional_string(Map.get(params, "email")),
        "webhook_url" => webhook_url
      })
    end
  end

  def put_notifications_config(_permissions, _params), do: {:error, :forbidden}

  def get_offline_window do
    get_setting("offline_window", %{"minutes" => 10})
    |> Map.get("minutes")
    |> parse_positive_integer(10)
  end

  def get_notifications_config do
    get_setting("notifications", %{"email" => nil, "webhook_url" => nil})
  end

  defp next_webhook_url(existing, params) do
    current = Map.get(existing, "webhook_url")
    candidate = normalize_optional_string(Map.get(params, "webhook_url"))

    cond do
      truthy?(Map.get(params, "clear_webhook_url")) ->
        {:ok, nil}

      is_nil(candidate) ->
        {:ok, current}

      true ->
        case Webhook.validate_url(candidate) do
          {:ok, _target} -> {:ok, candidate}
          {:error, reason} -> {:error, {:invalid_webhook_url, reason}}
        end
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp truthy?(value), do: value in [true, "true", "on", "1", 1]

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
