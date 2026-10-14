defmodule Nixstasis.Deployment do
  @moduledoc false

  alias Nixstasis.Devices

  @default_port 4000
  @reserved_subdomains ~w(nixstasis auth frp-admin)

  def default_port, do: @default_port

  def required_env!(name) do
    System.get_env(name) ||
      raise """
      environment variable #{name} is missing.
      """
  end

  def optional_env(name, default \\ nil) do
    System.get_env(name) || default
  end

  def enabled?(name, default \\ false) do
    case System.get_env(name) do
      nil -> default
      value -> String.downcase(String.trim(value)) in ~w(1 true yes on)
    end
  end

  def strict_boolean_env!(name, default) when is_boolean(default) do
    case System.get_env(name) do
      nil -> default
      value -> parse_strict_boolean!(name, value)
    end
  end

  def port do
    case Integer.parse(optional_env("PORT", Integer.to_string(@default_port))) do
      {port, ""} when port > 0 -> port
      _ -> raise "environment variable PORT must be a positive integer"
    end
  end

  def base_domain do
    Application.get_env(:nixstasis, :base_domain) || System.get_env("BASE_DOMAIN")
  end

  def approved_tls_domain?(domain, remote_access_requested? \\ &active_device_authorization?/1)

  def approved_tls_domain?(domain, remote_access_requested?) when is_binary(domain) do
    case subdomain_for(domain) do
      {:ok, subdomain} when subdomain in @reserved_subdomains ->
        true

      {:ok, "tls-validate-" <> _nonce} ->
        Nixstasis.TLSObservations.enabled?() and base_domain() == "localhost"

      {:ok, "atom-" <> normalized_device_id} ->
        with [_, hex_id] <- Regex.run(~r/^([0-9a-f]{32})(?:-[a-z][a-z0-9-]*)?$/, normalized_device_id),
             {:ok, bytes} <- Base.decode16(hex_id, case: :lower),
             {:ok, device_id} <- Ecto.UUID.cast(bytes) do
          remote_access_requested?.(device_id)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  def approved_tls_domain?(_, _), do: false

  defp active_device_authorization?(device_id) do
    case Devices.get_device(device_id) do
      {:ok, device} -> Devices.remote_access_active?(device)
      _ -> false
    end
  end

  def subdomain_for(domain) when is_binary(domain) do
    normalized_domain =
      domain
      |> String.trim()
      |> String.trim_trailing(".")
      |> String.downcase()

    normalized_base_domain =
      base_domain()
      |> to_string()
      |> String.trim()
      |> String.trim_trailing(".")
      |> String.downcase()

    suffix = "." <> normalized_base_domain

    cond do
      normalized_base_domain == "" ->
        :error

      not String.ends_with?(normalized_domain, suffix) ->
        :error

      true ->
        subdomain = String.replace_suffix(normalized_domain, suffix, "")

        if subdomain == "" or String.contains?(subdomain, ".") do
          :error
        else
          {:ok, subdomain}
        end
    end
  end

  def subdomain_for(_), do: :error

  defp parse_strict_boolean!(name, value) do
    case String.downcase(String.trim(value)) do
      value when value in ~w(1 true yes on) -> true
      value when value in ~w(0 false no off) -> false
      _ -> raise "environment variable #{name} must be a boolean value"
    end
  end
end
