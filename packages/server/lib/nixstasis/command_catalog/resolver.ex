defmodule Nixstasis.CommandCatalog.Resolver do
  @moduledoc """
  Resolves server-curated catalog commands against untrusted device inventory evidence.

  Preview reads are scoped to the requested devices, commands, and categories.
  SQL count queries enforce the command and source-row bounds before catalog
  rows, mappings, or inventory evidence are materialized.
  """

  require Ash.Query

  alias Nixstasis.CommandCatalog.CatalogCommand
  alias Nixstasis.CommandCatalog.Category
  alias Nixstasis.CommandCatalog.DeviceInventorySnapshot
  alias Nixstasis.CommandCatalog.PackageMapping
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain
  alias Nixstasis.Settings

  @catalog_version "catalog-v1"
  @command_limit 2_500
  @source_row_limit 10_000

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

  def preflight(attrs) when is_map(attrs) do
    command_ids = normalize_ids(Map.get(attrs, :catalog_command_ids, Map.get(attrs, "catalog_command_ids", [])))
    category_ids = normalize_ids(Map.get(attrs, :catalog_category_ids, Map.get(attrs, "catalog_category_ids", [])))

    with {:ok, category_slugs, valid_category_ids} <- selected_category_slugs(category_ids),
         {:ok, source_row_count, command_count} <- selected_catalog_counts(command_ids, category_slugs),
         :ok <- enforce_limits(source_row_count, command_count) do
      {:ok,
       %{
         command_ids: selected_catalog_command_ids(command_ids, category_slugs),
         direct_command_ids: active_direct_catalog_command_ids(command_ids),
         category_ids: category_ids,
         valid_category_ids: valid_category_ids,
         category_slugs: category_slugs,
         source_row_count: source_row_count,
         resolved_command_count: command_count
       }}
    end
  end

  def preview(attrs) when is_map(attrs) do
    device_ids = normalize_ids(Map.get(attrs, :device_ids, Map.get(attrs, "device_ids", [])))

    with {:ok, bounds} <- preflight(attrs),
         {:ok, selected_commands} <- selected_catalog_commands(bounds.command_ids),
         {:ok, mappings} <- selected_mappings(selected_commands),
         {:ok, devices} <- selected_devices(device_ids),
         {:ok, snapshots} <- selected_snapshots(device_ids) do
      snapshots_by_device = latest_snapshots(snapshots)

      {:ok,
       %{
         catalog_version: catalog_version(),
         selected_catalog_command_ids: Enum.map(selected_commands, & &1.id),
         source_row_count: bounds.source_row_count,
         resolved_command_count: bounds.resolved_command_count,
         devices:
           Map.new(devices, fn device ->
             snapshot = Map.get(snapshots_by_device, device.id)

             {device.id,
              %{
                inventory_status: inventory_status(snapshot),
                commands:
                  Map.new(selected_commands, fn command ->
                    {command.name, compatibility(command, snapshot, mappings)}
                  end)
              }}
           end)
       }}
    end
  end

  defp selected_category_slugs([]), do: {:ok, [], []}

  defp selected_category_slugs(category_ids) do
    categories =
      Category
      |> Ash.Query.filter(id in ^category_ids)
      |> Ash.Query.select([:id, :slug])
      |> Ash.read!(domain: Domain)

    {:ok, Enum.map(categories, & &1.slug) |> Enum.uniq(), Enum.map(categories, & &1.id)}
  end

  defp selected_catalog_query([], []), do: nil

  defp selected_catalog_query(command_ids, category_slugs) do
    CatalogCommand
    |> Ash.Query.filter(
      active == true and
        (id in ^command_ids or intersects(category_slugs, ^category_slugs))
    )
  end

  defp selected_catalog_counts(command_ids, category_slugs) do
    case selected_catalog_query(command_ids, category_slugs) do
      nil ->
        {:ok, 0, 0}

      query ->
        {:ok, Ash.count!(query, domain: Domain), query |> Ash.Query.distinct(:name) |> Ash.count!(domain: Domain)}
    end
  end

  defp enforce_limits(source_row_count, command_count) do
    cond do
      source_row_count > @source_row_limit ->
        limit_error(:source_rows, @source_row_limit, source_row_count)

      command_count > @command_limit ->
        limit_error(:commands, @command_limit, command_count)

      true ->
        :ok
    end
  end

  defp selected_catalog_command_ids(command_ids, category_slugs) do
    case selected_catalog_query(command_ids, category_slugs) do
      nil -> []
      query -> query |> Ash.Query.select([:id]) |> Ash.read!(domain: Domain) |> Enum.map(& &1.id)
    end
  end

  defp active_direct_catalog_command_ids([]), do: []

  defp active_direct_catalog_command_ids(command_ids) do
    CatalogCommand
    |> Ash.Query.filter(id in ^command_ids and active == true)
    |> Ash.Query.select([:id])
    |> Ash.read!(domain: Domain)
    |> Enum.map(& &1.id)
  end

  defp selected_catalog_commands([]), do: {:ok, []}

  defp selected_catalog_commands(command_ids) do
    commands =
      CatalogCommand
      |> Ash.Query.filter(id in ^command_ids and active == true)
      |> Ash.Query.sort(name: :asc)
      |> Ash.Query.select([:id, :name])
      |> Ash.read!(domain: Domain)

    {:ok, commands}
  end

  defp selected_mappings([]), do: {:ok, []}

  defp selected_mappings(commands) do
    command_ids = Enum.map(commands, & &1.id)

    mappings =
      PackageMapping
      |> Ash.Query.filter(catalog_command_id in ^command_ids and supported == true)
      |> Ash.Query.select([
        :catalog_command_id,
        :os_family,
        :package_manager,
        :package_name,
        :command_path,
        :install_hint,
        :supported
      ])
      |> Ash.read!(domain: Domain)

    {:ok, mappings}
  end

  defp selected_devices([]), do: {:ok, []}

  defp selected_devices(device_ids) do
    devices =
      Device
      |> Ash.Query.filter(id in ^device_ids)
      |> Ash.Query.select([:id])
      |> Ash.read!(domain: Domain)

    {:ok, devices}
  end

  defp selected_snapshots([]), do: {:ok, []}

  defp selected_snapshots(device_ids) do
    snapshots =
      DeviceInventorySnapshot
      |> Ash.Query.filter(device_id in ^device_ids)
      |> Ash.Query.select([
        :device_id,
        :probe_catalog_version,
        :observed_at,
        :os_release,
        :packages,
        :commands
      ])
      |> Ash.read!(domain: Domain)

    {:ok, snapshots}
  end

  defp limit_error(kind, limit, actual),
    do: {:error, {:command_policy_limit_exceeded, %{kind: kind, limit: limit, actual: actual}}}

  defp compatibility(command, snapshot, mappings) do
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

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.flat_map(fn id ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> [uuid]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp normalize_ids(_), do: []
end
