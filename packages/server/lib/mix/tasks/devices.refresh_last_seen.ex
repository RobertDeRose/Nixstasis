defmodule Mix.Tasks.Devices.RefreshLastSeen do
  @shortdoc "Refreshes device last_seen_at timestamps for local UI testing"

  @moduledoc """
  Updates `last_seen_at` to current UTC time so devices appear online in the UI.

  Default behavior updates the seed devices from `priv/repo/seeds.exs`:
    - AA:BB:CC:00:00:11
    - AA:BB:CC:00:00:12
    - AA:BB:CC:00:00:13

  Options:
    --all        Update all devices
    --minutes N  Set `last_seen_at` to now minus N minutes (default: 0)

  Examples:
    mix devices.refresh_last_seen
    mix devices.refresh_last_seen --all
    mix devices.refresh_last_seen --minutes 2
  """

  use Mix.Task

  @seed_macs [
    "AA:BB:CC:00:00:11",
    "AA:BB:CC:00:00:12",
    "AA:BB:CC:00:00:13"
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [all: :boolean, minutes: :integer])

    all? = Keyword.get(opts, :all, false)
    minutes = max(0, Keyword.get(opts, :minutes, 0))
    timestamp = DateTime.add(DateTime.utc_now(), -minutes, :minute) |> DateTime.truncate(:second)

    devices = list_target_devices(all?)

    updated_count =
      Enum.reduce(devices, 0, fn device, acc ->
        case Nixstasis.Devices.update_device(device, %{last_seen_at: timestamp}) do
          {:ok, _updated} ->
            Mix.shell().info("Updated #{device.mac_address} -> #{DateTime.to_iso8601(timestamp)}")
            acc + 1

          {:error, reason} ->
            Mix.shell().error("Failed #{device.mac_address}: #{inspect(reason)}")
            acc
        end
      end)

    Mix.shell().info("Done. Updated #{updated_count} device(s).")
  end

  defp list_target_devices(true), do: Nixstasis.Devices.list_devices()

  defp list_target_devices(false) do
    Nixstasis.Devices.list_devices()
    |> Enum.filter(&(&1.mac_address in @seed_macs))
  end
end
