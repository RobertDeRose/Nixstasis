defmodule Nixstasis.CommandCatalog.Resolver do
  @moduledoc """
  Resolves server-curated catalog commands against untrusted device inventory evidence.
  """

  alias Nixstasis.Domain
  alias Nixstasis.Settings

  @catalog_version "catalog-v1"

  def catalog_version, do: @catalog_version

  def probe_manifest do
    with {:ok, commands} <- Domain.list_command_catalog_commands(),
         {:ok, mappings} <- Domain.list_command_catalog_mappings() do
      active_commands = Enum.filter(commands, & &1.active)
      active_ids = MapSet.new(active_commands, & &1.id)
      mappings = Enum.filter(mappings, &(&1.catalog_command_id in active_ids and &1.supported))
      commands_by_id = Map.new(active_commands, &{&1.id, &1})

      {:ok,
       %{
         catalog_version: catalog_version(),
         package_names: mappings |> Enum.map(& &1.package_name) |> Enum.uniq() |> Enum.sort(),
         command_probes:
           mappings
           |> Enum.map(fn mapping ->
             command = Map.fetch!(commands_by_id, mapping.catalog_command_id)

             %{
               name: command.name,
               os_family: mapping.os_family,
               package_name: mapping.package_name,
               command_path: mapping.command_path
             }
           end)
           |> Enum.sort_by(&{&1.name, &1.os_family, &1.command_path})
       }}
    end
  end

  def preview(attrs) when is_map(attrs) do
    device_ids = normalize_ids(Map.get(attrs, :device_ids, Map.get(attrs, "device_ids", [])))
    catalog_command_ids = normalize_ids(Map.get(attrs, :catalog_command_ids, Map.get(attrs, "catalog_command_ids", [])))

    with {:ok, devices} <- Domain.list_devices(),
         {:ok, commands} <- Domain.list_command_catalog_commands(),
         {:ok, mappings} <- Domain.list_command_catalog_mappings(),
         {:ok, snapshots} <- Domain.list_device_command_inventory_snapshots() do
      selected_devices = Enum.filter(devices, &(&1.id in device_ids))

      selected_commands =
        commands |> Enum.filter(&(&1.id in catalog_command_ids and &1.active)) |> Enum.sort_by(& &1.name)

      snapshots_by_device = latest_snapshots(snapshots)

      {:ok,
       %{
         catalog_version: catalog_version(),
         devices:
           Map.new(selected_devices, fn device ->
             snapshot = Map.get(snapshots_by_device, device.id)

             {device.id,
              %{
                inventory_status: inventory_status(snapshot),
                commands:
                  Map.new(selected_commands, fn command ->
                    {command.name, compatibility(command, device, snapshot, mappings)}
                  end)
              }}
           end)
       }}
    end
  end

  defp compatibility(command, _device, snapshot, mappings) do
    if stale_inventory?(snapshot) do
      base_result(command, :stale_inventory)
    else
      os_family = snapshot_os_family(snapshot)
      mapping = mapping_for(command, os_family, mappings)

      cond do
        is_nil(mapping) ->
          base_result(command, :unsupported_os, os_family: os_family)

        package_status(snapshot, mapping.package_name) == :unknown ->
          mapping_result(command, mapping, :supported, os_family)

        package_status(snapshot, mapping.package_name) == :missing ->
          mapping_result(command, mapping, :missing_package, os_family)

        path_conflict?(snapshot, command.name, mapping.command_path) ->
          mapping_result(command, mapping, :conflict, os_family)
          |> Map.put(:observed_path, command_path(snapshot, command.name))

        command_path(snapshot, command.name) == mapping.command_path ->
          mapping_result(command, mapping, :command_path_resolved, os_family)

        true ->
          mapping_result(command, mapping, :package_installed, os_family)
      end
    end
  end

  defp base_result(command, status, extra \\ []) do
    Map.merge(
      %{
        status: status,
        catalog_command_id: command.id,
        command_name: command.name
      },
      Map.new(extra)
    )
  end

  defp mapping_result(command, mapping, status, os_family) do
    base_result(command, status,
      os_family: os_family,
      package_name: mapping.package_name,
      package_manager: mapping.package_manager,
      command_path: mapping.command_path,
      install_hint: mapping.install_hint
    )
  end

  defp mapping_for(command, os_family, mappings) do
    Enum.find(mappings, &(&1.catalog_command_id == command.id and &1.os_family == os_family and &1.supported))
  end

  defp latest_snapshots(snapshots) do
    snapshots
    |> Enum.sort_by(& &1.observed_at, {:desc, DateTime})
    |> Map.new(&{&1.device_id, &1})
  end

  defp inventory_status(snapshot), do: if(stale_inventory?(snapshot), do: :stale_inventory, else: :current)

  defp stale_inventory?(nil), do: true

  defp stale_inventory?(snapshot) do
    snapshot.probe_catalog_version != catalog_version() or old_inventory?(snapshot.observed_at)
  end

  defp old_inventory?(observed_at) do
    cutoff = DateTime.utc_now() |> DateTime.add(-Settings.get_offline_window(), :minute)
    DateTime.compare(observed_at, cutoff) == :lt
  end

  defp snapshot_os_family(snapshot) do
    Nixstasis.CommandCatalog.Changes.NormalizeInventory.os_family(snapshot.os_release)
  end

  defp package_status(snapshot, package_name) do
    case Map.get(snapshot.packages || %{}, package_name) do
      nil -> :unknown
      true -> :installed
      %{"installed" => true} -> :installed
      %{installed: true} -> :installed
      _ -> :missing
    end
  end

  defp path_conflict?(snapshot, command_name, expected_path) do
    case command_path(snapshot, command_name) do
      nil -> false
      ^expected_path -> false
      _ -> true
    end
  end

  defp command_path(snapshot, command_name) do
    case Map.get(snapshot.commands || %{}, command_name) do
      path when is_binary(path) -> path
      %{"path" => path} when is_binary(path) -> path
      %{path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  defp normalize_ids(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp normalize_ids(_), do: []
end
