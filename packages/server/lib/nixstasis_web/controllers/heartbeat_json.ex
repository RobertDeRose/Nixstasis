defmodule NixstasisWeb.HeartbeatJSON do
  alias Nixstasis.Devices.FrpsToken

  def show(%{commands: commands, device: device}) do
    %{
      data:
        device
        |> response_data(commands)
        |> maybe_put_remote_access_token(FrpsToken.for_heartbeat(device))
    }
  end

  defp response_data(_device, commands) do
    %{
      commands:
        for(
          cmd <- commands,
          do: command_data(cmd)
        )
    }
  end

  defp maybe_put_remote_access_token(data, nil), do: data
  defp maybe_put_remote_access_token(data, token), do: Map.put(data, :remote_access_token, token)

  defp command_data(cmd) do
    payload = cmd.command_payload || %{}
    payload_ref = payload["payload_ref"] || payload[:payload_ref]
    inline_payload = normalize_inline_payload(payload, payload_ref)

    %{
      command_id: cmd.id,
      type: payload["type"] || payload[:type] || "unknown",
      args: payload["args"] || payload[:args] || [],
      payload: inline_payload,
      payload_ref: payload_ref,
      queued_at: cmd.queued_at
    }
  end

  defp normalize_inline_payload(_payload, payload_ref) when not is_nil(payload_ref), do: nil

  defp normalize_inline_payload(payload, _payload_ref) do
    payload
    |> nested_payload()
    |> case do
      %{} = nested -> nested
      _ -> fallback_inline_payload(payload)
    end
  end

  defp nested_payload(payload) do
    payload["payload"] || payload[:payload]
  end

  defp fallback_inline_payload(payload) do
    if has_transport_shape?(payload) do
      transport_payload(payload)
    else
      payload
    end
  end

  defp has_transport_shape?(payload) do
    not is_nil(payload["content_type"] || payload[:content_type]) or
      not is_nil(payload["name"] || payload[:name]) or
      not is_nil(payload["data"] || payload[:data])
  end

  defp transport_payload(payload) do
    %{
      "content_type" => payload["content_type"] || payload[:content_type],
      "name" => payload["name"] || payload[:name],
      "data" => payload["data"] || payload[:data]
    }
  end
end
