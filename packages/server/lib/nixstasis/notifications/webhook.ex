defmodule Nixstasis.Notifications.Webhook do
  @moduledoc """
  Sends alert notifications to configured HTTPS webhooks.

  Destinations are resolved before each request. Every resolved address must be
  public, and the request is pinned to one of those addresses while retaining
  the original hostname for HTTP Host, TLS SNI, and certificate verification.
  Redirects are disabled so a public endpoint cannot redirect into a private
  network.
  """

  import Bitwise

  @network_timeout_ms 5_000

  def send_alert_webhook(url, _alert) when url in [nil, ""], do: :ok

  def send_alert_webhook(url, alert) do
    with {:ok, target} <- validate_url(url) do
      Req.post(target.request_url,
        headers: [{"host", target.host_header}],
        connect_options: connect_options(target),
        redirect: false,
        retry: false,
        receive_timeout: @network_timeout_ms,
        json: %{
          id: alert.id,
          type: alert.type,
          message: alert.message,
          triggered_at: alert.triggered_at
        }
      )
    end
  end

  @doc """
  Validates and resolves a webhook destination.

  The two-argument form exists for deterministic tests; production callers use
  the system resolver through `validate_url/1`.
  """
  def validate_url(url, resolver \\ &resolve_host/1)

  def validate_url(url, resolver) when is_binary(url) and is_function(resolver, 1) do
    with {:ok, uri} <- parse_https_url(url),
         {:ok, addresses} <- resolve_uri_host(uri, resolver),
         :ok <- require_public_addresses(addresses),
         [address | _] <- addresses do
      {:ok,
       %{
         hostname: uri.host,
         host_header: host_header(uri),
         address: address,
         request_url: pinned_url(uri, address)
       }}
    else
      [] -> {:error, :unresolvable_host}
      {:error, _reason} = error -> error
    end
  end

  def validate_url(_url, _resolver), do: {:error, :invalid_url}

  defp parse_https_url(url) do
    uri = url |> String.trim() |> URI.parse()

    cond do
      String.downcase(uri.scheme || "") != "https" -> {:error, :https_required}
      not is_binary(uri.host) or uri.host == "" -> {:error, :missing_host}
      uri.port != nil and (uri.port < 1 or uri.port > 65_535) -> {:error, :invalid_port}
      true -> {:ok, %{uri | scheme: "https", fragment: nil}}
    end
  rescue
    ArgumentError -> {:error, :invalid_url}
  end

  defp resolve_uri_host(%URI{host: host}, resolver) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, [address]}
      {:error, :einval} -> resolver.(host)
    end
  end

  defp resolve_host(host) do
    host = String.to_charlist(host)

    addresses =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(host, family) do
          {:ok, values} -> values
          {:error, _reason} -> []
        end
      end)
      |> Enum.uniq()

    case addresses do
      [] -> {:error, :unresolvable_host}
      values -> {:ok, values}
    end
  end

  defp require_public_addresses(addresses) when is_list(addresses) and addresses != [] do
    if Enum.all?(addresses, &public_address?/1), do: :ok, else: {:error, :non_public_address}
  end

  defp require_public_addresses(_addresses), do: {:error, :unresolvable_host}

  defp public_address?({a, b, c, _d}) do
    cond do
      a == 0 -> false
      a == 10 -> false
      a == 100 and b in 64..127 -> false
      a == 127 -> false
      a == 169 and b == 254 -> false
      a == 172 and b in 16..31 -> false
      a == 192 and b == 0 and c == 0 -> false
      a == 192 and b == 0 and c == 2 -> false
      a == 192 and b == 88 and c == 99 -> false
      a == 192 and b == 168 -> false
      a == 198 and b in 18..19 -> false
      a == 198 and b == 51 and c == 100 -> false
      a == 203 and b == 0 and c == 113 -> false
      a >= 224 -> false
      true -> true
    end
  end

  defp public_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  defp public_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  defp public_address?({0, 0, 0, 0, 0, 0, _high, _low}), do: false

  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    public_address?({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})
  end

  defp public_address?({first, second, _c, _d, _e, _f, _g, _h}) do
    cond do
      first == 0x64 and second == 0xFF9B -> false
      first == 0x100 -> false
      first == 0x2001 and second == 0xDB8 -> false
      first == 0x2002 -> false
      (first &&& 0xFE00) == 0xFC00 -> false
      (first &&& 0xFFC0) == 0xFE80 -> false
      (first &&& 0xFFC0) == 0xFEC0 -> false
      (first &&& 0xFF00) == 0xFF00 -> false
      true -> true
    end
  end

  defp public_address?(_address), do: false

  defp host_header(uri) do
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    if uri.port in [nil, 443], do: host, else: "#{host}:#{uri.port}"
  end

  defp pinned_url(uri, address) do
    %{uri | host: address |> :inet.ntoa() |> List.to_string()}
    |> URI.to_string()
  end

  defp connect_options(%{hostname: hostname, address: address}) do
    options = [hostname: hostname, timeout: @network_timeout_ms]

    case address do
      {_a, _b, _c, _d} -> options
      {_a, _b, _c, _d, _e, _f, _g, _h} -> Keyword.put(options, :transport_opts, inet6: true)
    end
  end
end
