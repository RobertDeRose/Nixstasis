defmodule NixstasisWeb.HeartbeatJSON do
  alias Nixstasis.Monitoring

  def show(%{commands: commands, device: device}) do
    %{data: Monitoring.heartbeat_response_data(device, commands)}
  end
end
