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

  @doc """
  Sends an alert's ID, type, message, and timestamp to an HTTPS webhook.

  A missing or empty URL disables delivery and returns `:ok`. Otherwise, the
  destination is resolved and checked before the request, which is pinned to a
  public address while retaining the hostname for TLS and HTTP. Redirects and
  retries are disabled. Returns Req's response tuple or a validation error.
  """
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
  Checks that a webhook URL uses HTTPS and resolves only to public addresses.

  Returns `{:ok, target}` with the original hostname and Host header, the chosen
  IP address, and an IP-pinned request URL. Invalid URLs, unresolved hosts, or
  any rejected DNS answer return `{:error, reason}` without sending a request.

  The optional resolver receives a hostname and returns `{:ok, addresses}` or
  `{:error, reason}`. It makes tests deterministic; normal callers use the system
  resolver, with a five-second timeout for each sequential IPv4/IPv6 lookup
  (up to ten seconds for DNS resolution). Literal IP addresses are checked
  directly without a DNS lookup. Connection and response timeouts are separate.
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

  # Trim and parse the URL, require an HTTPS hostname and valid port, and remove
  # the fragment. Parsing failures become validation errors rather than exceptions.
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

  # Use a literal IPv4/IPv6 address directly; only hostnames need the supplied
  # resolver. Both paths return the same address-list or error tuple.
  defp resolve_uri_host(%URI{host: host}, resolver) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, [address]}
      {:error, :einval} -> resolver.(host)
    end
  end

  # Collect and deduplicate both IPv4 and IPv6 DNS answers. A failed lookup for
  # one family, including timeout, is harmless if the other succeeds; no answers
  # means a host error. Each sequential lookup has its own five-second budget.
  defp resolve_host(host) do
    host = String.to_charlist(host)

    addresses =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(host, family, @network_timeout_ms) do
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

  # Reject the whole destination if any DNS answer is not public. Empty or
  # malformed answer lists are unresolved hosts, never permission to connect.
  defp require_public_addresses(addresses) when is_list(addresses) and addresses != [] do
    if Enum.all?(addresses, &public_address?/1), do: :ok, else: {:error, :non_public_address}
  end

  defp require_public_addresses(_addresses), do: {:error, :unresolvable_host}

  # Classify addresses for outbound HTTPS, not merely by whether they parse.
  # Reject private, local, reserved, and special-purpose IPv4 ranges; mapped IPv6
  # uses these same checks. Native IPv6 must be global unicast, excluding unsafe
  # special-purpose prefixes, with narrow exceptions for routable public services.
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

  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    public_address?({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})
  end

  # Globally routable service exceptions within IANA's 2001::/23 protocol block:
  # https://www.iana.org/assignments/iana-ipv6-special-registry/
  defp public_address?({0x2001, 1, 0, 0, 0, 0, 0, service}) when service in [1, 2, 3], do: true
  defp public_address?({0x2001, 3, _c, _d, _e, _f, _g, _h}), do: true
  defp public_address?({0x2001, 4, 0x112, _d, _e, _f, _g, _h}), do: true

  defp public_address?({first, second, _c, _d, _e, _f, _g, _h}) do
    cond do
      (first &&& 0xE000) != 0x2000 -> false
      first == 0x2001 and (second &&& 0xFE00) == 0 -> false
      first == 0x2001 and second == 0xDB8 -> false
      first == 0x2002 -> false
      first == 0x3FFF and (second &&& 0xF000) == 0 -> false
      true -> true
    end
  end

  defp public_address?(_address), do: false

  # Preserve the URL's HTTP authority after IP pinning: bracket IPv6 hosts and
  # include non-default ports, but omit the default HTTPS port.
  defp host_header(uri) do
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    if uri.port in [nil, 443], do: host, else: "#{host}:#{uri.port}"
  end

  # Replace only the URL hostname with the validated IP address, retaining its
  # path, query, credentials, and port so delivery cannot perform a new DNS lookup.
  defp pinned_url(uri, address) do
    %{uri | host: address |> :inet.ntoa() |> List.to_string()}
    |> URI.to_string()
  end

  # Keep the original hostname for TLS SNI and certificate verification, limit
  # connection time, and ask Mint to use IPv6 when the pinned address requires it.
  defp connect_options(%{hostname: hostname, address: address}) do
    options = [hostname: hostname, timeout: @network_timeout_ms]

    case address do
      {_a, _b, _c, _d} -> options
      {_a, _b, _c, _d, _e, _f, _g, _h} -> Keyword.put(options, :transport_opts, inet6: true)
    end
  end
end
