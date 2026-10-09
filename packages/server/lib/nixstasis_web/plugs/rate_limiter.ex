defmodule NixstasisWeb.Plugs.RateLimiter do
  @moduledoc false

  import Plug.Conn

  alias NixstasisWeb.RateLimiterStore

  @default_preauth_limit 1_000
  @default_preauth_global_limit 50_000
  @default_preauth_max_keys 4_096
  @default_device_limit 120
  @heartbeat_limit 30
  @default_window_ms 60_000

  @proxy_auth_header "x-nixstasis-proxy-token"
  @client_ip_header "x-nixstasis-client-ip"

  @device_actions [:heartbeat, :command_results, :command_payload]

  def init(opts), do: opts

  def call(conn, opts) do
    window_ms = rate_limit(opts, :window_ms, @default_window_ms)
    global_limit = rate_limit(opts, :preauth_global_limit, @default_preauth_global_limit)
    origin_limit = rate_limit(opts, :preauth_limit, rate_limit(opts, :limit, @default_preauth_limit))
    max_keys = rate_limit(opts, :preauth_max_keys, @default_preauth_max_keys)
    route = preauth_route(conn)
    origin = client_origin(conn)

    with :ok <- RateLimiterStore.check_rate({:preauth, :global}, global_limit, window_ms),
         :ok <-
           RateLimiterStore.check_bounded_rate(
             {:preauth, :origin, route, origin},
             origin_limit,
             window_ms,
             max_keys
           ) do
      conn
    else
      :limited -> reject(conn)
    end
  end

  @doc false
  def check_authenticated_device(device_or_id, action, opts \\ []) when action in @device_actions do
    with {:ok, device_id} <- device_id(device_or_id) do
      limit = authenticated_device_limit(action, opts)
      window_ms = rate_limit(opts, :window_ms, @default_window_ms)
      RateLimiterStore.check_rate({:device, action, device_id}, limit, window_ms)
    else
      :error -> :limited
    end
  end

  @doc false
  def reject(conn) do
    body = Jason.encode!(%{error: %{code: "rate_limited", message: "Rate limit exceeded"}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, body)
    |> halt()
  end

  defp authenticated_device_limit(:heartbeat, opts) do
    rate_limit(opts, :heartbeat_limit, @heartbeat_limit)
  end

  defp authenticated_device_limit(_action, opts) do
    rate_limit(opts, :device_limit, rate_limit(opts, :limit, @default_device_limit))
  end

  defp device_id(%{id: id}), do: device_id(id)

  defp device_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> :error
    end
  end

  defp device_id(_id), do: :error

  defp preauth_route(%{method: "POST", path_info: ["api", "v1", "devices", "register"]}),
    do: :device_registration

  defp preauth_route(%{method: "POST", path_info: ["api", "v1", "devices", _id, "heartbeat"]}),
    do: :device_heartbeat

  defp preauth_route(%{
         method: "POST",
         path_info: ["api", "v1", "devices", _id, "command_results"]
       }),
       do: :device_command_results

  defp preauth_route(%{
         method: "GET",
         path_info: ["api", "v1", "devices", _id, "command_payloads", _ref]
       }),
       do: :device_command_payload

  defp preauth_route(%{
         method: "POST",
         path_info: ["api", "json", "device_runtime", "devices", "register"]
       }),
       do: :json_device_registration

  defp preauth_route(%{
         method: "POST",
         path_info: ["api", "json", "device_runtime", "devices", _id, "heartbeat"]
       }),
       do: :json_device_heartbeat

  defp preauth_route(%{
         method: "POST",
         path_info: ["api", "json", "device_runtime", "devices", _id, "command_results"]
       }),
       do: :json_device_command_results

  defp preauth_route(%{
         method: "GET",
         path_info: ["api", "json", "device_runtime", "devices", _id, "command_payloads", _ref]
       }),
       do: :json_device_command_payload

  defp preauth_route(%{path_info: ["api", "json" | _], method: method}),
    do: {:json_api, method_bucket(method)}

  defp preauth_route(%{path_info: ["api", "v1", "provisioning" | _], method: method}),
    do: {:provisioning, method_bucket(method)}

  defp preauth_route(%{path_info: ["api", "v1" | _], method: method}),
    do: {:api_v1, method_bucket(method)}

  defp preauth_route(%{path_info: ["_nixstasis", "laptop" | _], method: method}),
    do: {:laptop_api, method_bucket(method)}

  defp preauth_route(%{method: method}), do: {:other, method_bucket(method)}

  defp method_bucket(method) when method in ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    do: method

  defp method_bucket(_method), do: "OTHER"

  defp client_origin(conn) do
    if trusted_proxy?(conn) do
      trusted_client_ip(conn) || remote_ip(conn)
    else
      remote_ip(conn)
    end
  end

  defp trusted_client_ip(conn) do
    case get_req_header(conn, @client_ip_header) do
      [value] -> normalize_ip(value)
      _ -> nil
    end
  end

  defp trusted_proxy?(conn) do
    expected = Application.get_env(:nixstasis, :proxy_auth_token)

    provided =
      case get_req_header(conn, @proxy_auth_header) do
        [value] -> value
        _ -> nil
      end

    if valid_proxy_token?(expected) and valid_proxy_token?(provided) do
      expected_digest = :crypto.hash(:sha256, expected)
      provided_digest = :crypto.hash(:sha256, provided)
      Plug.Crypto.secure_compare(expected_digest, provided_digest)
    else
      false
    end
  end

  defp valid_proxy_token?(token), do: is_binary(token) and byte_size(token) >= 32

  defp normalize_ip(value) when is_binary(value) do
    value = String.trim(value)

    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> normalize_ip(address)
      {:error, _reason} -> nil
    end
  end

  defp normalize_ip({a, b, c, d, _, _, _, _}),
    do: {a, b, c, d, 0, 0, 0, 0} |> :inet.ntoa() |> to_string()

  defp normalize_ip({_, _, _, _} = address), do: address |> :inet.ntoa() |> to_string()

  defp normalize_ip(_value), do: nil

  defp remote_ip(conn), do: normalize_ip(conn.remote_ip)

  defp rate_limit(opts, key, default) do
    app_config = Application.get_env(:nixstasis, :rate_limit, [])
    Keyword.get(opts, key, Keyword.get(app_config, key, default))
  end
end
