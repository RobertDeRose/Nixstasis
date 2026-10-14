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

  @doc """
  Saves the offline detection window for a caller with settings-management permission.

  `minutes` must be a positive integer or a trimmed whole-number string. Shared
  resource validation stores an integer and rejects invalid values without a
  write. Returns the setting mutation result, or `{:error, :forbidden}` when the
  permissions map does not explicitly grant management.
  """
  def put_offline_window(%{"can_manage" => true}, minutes) do
    put_setting("offline_window", %{"minutes" => minutes})
  end

  def put_offline_window(_permissions, _minutes), do: {:error, :forbidden}

  @doc """
  Saves notification destinations for a caller with settings-management permission.

  `params` uses string keys for `email`, `webhook_url`, and `clear_webhook_url`.
  Blank webhook input keeps the current destination; an explicit clear removes
  it. Non-string input is rejected even when clearing. New URLs must use HTTPS
  and resolve only to public addresses; unchanged URLs are rechecked at delivery.
  Returns the resource mutation result or `{:error, :forbidden}`.
  """
  def put_notifications_config(%{"can_manage" => true}, params) when is_map(params) do
    existing = get_notifications_config()

    put_setting("notifications", %{
      "email" => normalize_optional_string(Map.get(params, "email")),
      "webhook_url" => next_webhook_url(existing, params)
    })
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

  # Select the replacement URL, explicit removal, or existing destination.
  # Preserve invalid input so shared validation rejects it instead of silently
  # clearing or keeping the webhook, even if removal was also requested.
  defp next_webhook_url(existing, params) do
    current = Map.get(existing, "webhook_url")
    candidate = Map.get(params, "webhook_url")

    cond do
      not (is_nil(candidate) or is_binary(candidate)) -> candidate
      truthy?(Map.get(params, "clear_webhook_url")) -> nil
      true -> normalize_optional_string(candidate) || current
    end
  end

  @doc """
  Validates and normalizes a value before a system setting is created or updated.

  Offline windows require positive whole minutes. Notification values trim email
  and URL strings, allow a blank or null URL to clear the destination, and check
  new URLs against the webhook network boundary. `previous_value` lets unchanged
  stored URLs survive a settings edit; delivery still validates them separately.
  Unknown setting keys pass through unchanged. Returns `{:ok, value}` or
  `{:error, message}` for the resource change to attach as a validation error.
  """
  def normalize_value(key, value, previous_value)

  def normalize_value("offline_window", value, _previous_value) when is_map(value) do
    case parse_positive_integer(Map.get(value, "minutes"), nil) do
      nil -> {:error, "minutes must be a positive whole number"}
      minutes -> {:ok, Map.put(value, "minutes", minutes)}
    end
  end

  def normalize_value("notifications", value, previous_value) when is_map(value) do
    url = Map.get(value, "webhook_url")
    previous_url = if is_map(previous_value), do: Map.get(previous_value, "webhook_url")

    with {:ok, url} <- validate_webhook_url(url, previous_url) do
      {:ok,
       value
       |> Map.put("email", normalize_optional_string(Map.get(value, "email")))
       |> Map.put("webhook_url", url)}
    end
  end

  def normalize_value(_key, value, _previous_value), do: {:ok, value}

  # Normalize strings, accept null/blank removal or an unchanged destination,
  # and validate replacements. Other value types produce a clear input error.
  defp validate_webhook_url(url, previous_url) when is_binary(url) do
    url = normalize_optional_string(url)

    cond do
      is_nil(url) or url == previous_url -> {:ok, url}
      true -> validate_new_webhook_url(url)
    end
  end

  defp validate_webhook_url(nil, _previous_url), do: {:ok, nil}
  defp validate_webhook_url(_url, _previous_url), do: {:error, "webhook URL must be a string"}

  # Resolve and validate a replacement destination without delivering an alert.
  # Convert network-validation reasons into a user-facing settings error.
  defp validate_new_webhook_url(url) do
    case Webhook.validate_url(url) do
      {:ok, _target} -> {:ok, url}
      {:error, _reason} -> {:error, "webhook URL must use HTTPS and resolve only to public network addresses"}
    end
  end

  # Trim optional form strings and represent blank or non-string values as nil.
  # Webhook type validation runs separately so invalid URLs are not discarded here.
  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  # Recognize the boolean and checkbox values accepted for explicit URL removal.
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
