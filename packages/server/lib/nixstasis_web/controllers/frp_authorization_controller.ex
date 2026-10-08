defmodule NixstasisWeb.FrpAuthorizationController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Devices.FrpsToken

  def authorize(conn, %{"op" => "Login", "content" => content}) do
    with {:ok, claims} <- verify_metadata(content["metas"]),
         true <- content["user"] == claims["device_name"] do
      allow(conn)
    else
      _ -> reject(conn, "invalid device authorization")
    end
  end

  def authorize(conn, %{"op" => "NewProxy", "content" => content}) do
    user = content["user"] || %{}

    with {:ok, claims} <- verify_metadata(user["metas"]),
         true <- user["user"] == claims["device_name"],
         true <- authorized_proxy?(claims["device_name"], content) do
      allow(conn)
    else
      _ -> reject(conn, "proxy is not authorized for this device")
    end
  end

  def authorize(conn, _params), do: reject(conn, "unsupported FRP operation")

  defp verify_metadata(metadata) when is_map(metadata) do
    with {:ok, claims} <- FrpsToken.verify(metadata["nixstasis_token"]),
         {:ok, device_id} <- Ecto.UUID.cast(claims["device_id"]),
         {:ok, device} <- Devices.get_device(device_id),
         true <- Devices.remote_access_active?(device) do
      {:ok, claims}
    else
      _ -> {:error, :inactive_authorization}
    end
  end

  defp verify_metadata(_metadata), do: {:error, :invalid}

  defp authorized_proxy?(device_name, content) when is_binary(device_name) do
    proxy_name = strip_user_prefix(content["proxy_name"], device_name)

    owned_proxy_name?(device_name, proxy_name) and
      case content["proxy_type"] do
        "http" ->
          content["subdomain"] == proxy_name and empty_domains?(content["custom_domains"])

        "tcpmux" ->
          content["multiplexer"] == "httpconnect" and
            content["custom_domains"] == [proxy_name] and blank?(content["subdomain"])

        _ ->
          false
      end
  end

  defp authorized_proxy?(_device_name, _content), do: false

  defp strip_user_prefix(name, user) when is_binary(name), do: String.replace_prefix(name, user <> ".", "")
  defp strip_user_prefix(name, _user), do: name

  defp owned_proxy_name?(device_name, proxy_name) when is_binary(proxy_name) do
    proxy_name == device_name or String.starts_with?(proxy_name, device_name <> "-")
  end

  defp owned_proxy_name?(_device_name, _proxy_name), do: false

  defp empty_domains?(nil), do: true
  defp empty_domains?([]), do: true
  defp empty_domains?(_domains), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp allow(conn), do: json(conn, %{reject: false, unchange: true})

  defp reject(conn, reason) do
    json(conn, %{reject: true, reject_reason: reason})
  end
end
