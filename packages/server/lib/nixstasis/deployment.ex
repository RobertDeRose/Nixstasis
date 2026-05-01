defmodule Nixstasis.Deployment do
  @moduledoc false

  import Nixstasis.Utilities, only: [format_mac_address: 1]

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

  def port do
    case Integer.parse(optional_env("PORT", Integer.to_string(@default_port))) do
      {port, ""} when port > 0 -> port
      _ -> raise "environment variable PORT must be a positive integer"
    end
  end

  def base_domain do
    Application.get_env(:nixstasis, :base_domain) || System.get_env("BASE_DOMAIN")
  end

  def approved_tls_domain?(domain, remote_access_requested? \\ &Nixstasis.Devices.requesting_remote_access?/1)

  def approved_tls_domain?(domain, remote_access_requested?) when is_binary(domain) do
    case subdomain_for(domain) do
      {:ok, subdomain} when subdomain in @reserved_subdomains -> true
      {:ok, "atom-" <> normalized_device_id} -> remote_access_requested?.(format_mac_address(normalized_device_id))
      _ -> false
    end
  end

  def approved_tls_domain?(_, _), do: false

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
end
