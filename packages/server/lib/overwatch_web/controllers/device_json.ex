defmodule NixstasisWeb.DeviceJSON do
  alias Nixstasis.Devices.Device

  @doc """
  Renders a list of devices.
  """
  def index(%{devices: devices}) do
    %{data: for(device <- devices, do: data(device))}
  end

  @doc """
  Renders a single device.
  """
  def show(%{device: device}) do
    %{data: data(device)}
  end

  defp data(%Device{} = device) do
    %{
      id: device.id,
      mac_address: device.mac_address,
      product_name: device.product_name,
      approval_status: device.approval_status,
      schema_definition: device.schema_definition,
      last_seen_at: device.last_seen_at,
      metadata: device.metadata
    }
  end
end
