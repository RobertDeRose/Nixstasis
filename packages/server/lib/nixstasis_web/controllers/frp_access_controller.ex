defmodule NixstasisWeb.FrpAccessController do
  use NixstasisWeb, :controller

  alias Nixstasis.Deployment
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  @requested_host_header "x-nixstasis-requested-host"
  @compact_uuid_size 32
  @compact_uuid_pattern ~r/^[0-9a-f]{32}$/

  def authorize(conn, _params) do
    with {:ok, context} <- OperatorContext.from_conn(conn),
         {:ok, device_id} <- requested_device_id(conn),
         true <- Permissions.can_remote_access_device?(context["device_permissions"], device_id) do
      send_resp(conn, :no_content, "")
    else
      _ -> send_resp(conn, :forbidden, "")
    end
  end

  defp requested_device_id(conn) do
    with [requested_host] <- get_req_header(conn, @requested_host_header),
         {:ok, subdomain} <- Deployment.subdomain_for(requested_host),
         {:ok, compact_device_id} <- compact_device_id(subdomain) do
      {:ok, expand_uuid(compact_device_id)}
    else
      _ -> :error
    end
  end

  defp compact_device_id("atom-" <> rest) do
    case rest do
      <<compact_device_id::binary-size(@compact_uuid_size), suffix::binary>> ->
        if Regex.match?(@compact_uuid_pattern, compact_device_id) and valid_route_suffix?(suffix) do
          {:ok, compact_device_id}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp compact_device_id(_subdomain), do: :error

  defp valid_route_suffix?(""), do: true
  defp valid_route_suffix?("-" <> route_name), do: route_name != ""
  defp valid_route_suffix?(_suffix), do: false

  defp expand_uuid(<<
         part1::binary-size(8),
         part2::binary-size(4),
         part3::binary-size(4),
         part4::binary-size(4),
         part5::binary-size(12)
       >>) do
    Enum.join([part1, part2, part3, part4, part5], "-")
  end
end
