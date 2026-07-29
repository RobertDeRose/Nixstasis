defmodule Nixstasis.CommandCatalog.Changes.NormalizeInventory do
  @moduledoc """
  Bounds and normalizes untrusted device inventory snapshots before persistence.
  """

  use Ash.Resource.Change

  alias Nixstasis.Domain

  @os_release_keys ~w(ID ID_LIKE VERSION_ID PRETTY_NAME)
  @max_string_length 256
  @safe_path ~r/^\/[^\s;&|`$<>(){}\[\]*?!'"]+$/

  @impl true
  def change(changeset, _opts, _context) do
    probe = probe_manifest()
    os_release = changeset_value(changeset, :os_release) |> sanitize_os_release()

    changeset
    |> Ash.Changeset.change_attribute(:os_release, os_release)
    |> Ash.Changeset.change_attribute(:os_family, os_family(os_release))
    |> Ash.Changeset.change_attribute(
      :architecture,
      sanitize_string(changeset_value(changeset, :architecture), "unknown")
    )
    |> Ash.Changeset.change_attribute(
      :package_manager,
      sanitize_string(changeset_value(changeset, :package_manager), "unknown")
    )
    |> Ash.Changeset.change_attribute(
      :probe_catalog_version,
      sanitize_string(changeset_value(changeset, :probe_catalog_version), "unknown")
    )
    |> Ash.Changeset.change_attribute(
      :packages,
      sanitize_packages(changeset_value(changeset, :packages), probe.package_names)
    )
    |> Ash.Changeset.change_attribute(
      :commands,
      sanitize_commands(changeset_value(changeset, :commands), probe.command_names)
    )
  end

  def os_family(os_release) when is_map(os_release) do
    ids =
      [Map.get(os_release, "ID"), Map.get(os_release, "ID_LIKE")]
      |> Enum.flat_map(fn
        value when is_binary(value) -> String.split(String.downcase(value), ~r/[\s,]+/, trim: true)
        _ -> []
      end)

    cond do
      "nixos" in ids -> "nixos"
      Enum.any?(ids, &(&1 in ["debian", "ubuntu"])) -> "debian"
      Enum.any?(ids, &(&1 in ["fedora", "rhel", "centos", "rocky", "almalinux", "redhat"])) -> "fedora"
      true -> "unsupported"
    end
  end

  def os_family(_), do: "unsupported"

  defp probe_manifest do
    case Domain.command_inventory_probe_manifest() do
      {:ok, manifest} ->
        %{
          package_names: MapSet.new(manifest.package_names),
          command_names: manifest.command_probes |> Enum.map(& &1.name) |> MapSet.new()
        }

      _ ->
        %{package_names: MapSet.new(), command_names: MapSet.new()}
    end
  end

  defp changeset_value(changeset, attribute) do
    case Ash.Changeset.fetch_change(changeset, attribute) do
      {:ok, value} -> value
      :error -> Ash.Changeset.get_attribute(changeset, attribute)
    end
  end

  defp sanitize_os_release(value) when is_map(value) do
    value
    |> Map.take(@os_release_keys)
    |> Map.new(fn {key, value} -> {key, sanitize_string(value, "")} end)
  end

  defp sanitize_os_release(_), do: %{}

  defp sanitize_packages(value, allowed_packages) when is_map(value) do
    value
    |> Enum.filter(fn {name, _evidence} -> is_binary(name) and MapSet.member?(allowed_packages, name) end)
    |> Map.new(fn {name, evidence} -> {name, %{"installed" => installed?(evidence)}} end)
  end

  defp sanitize_packages(_value, _allowed_packages), do: %{}

  defp sanitize_commands(value, allowed_commands) when is_map(value) do
    value
    |> Enum.filter(fn {name, evidence} ->
      is_binary(name) and MapSet.member?(allowed_commands, name) and safe_path?(command_path(evidence))
    end)
    |> Map.new(fn {name, evidence} -> {name, %{"path" => command_path(evidence)}} end)
  end

  defp sanitize_commands(_value, _allowed_commands), do: %{}

  defp installed?(true), do: true
  defp installed?(%{"installed" => true}), do: true
  defp installed?(%{installed: true}), do: true
  defp installed?(_), do: false

  defp command_path(path) when is_binary(path), do: path
  defp command_path(%{"path" => path}) when is_binary(path), do: path
  defp command_path(%{path: path}) when is_binary(path), do: path
  defp command_path(_), do: nil

  defp safe_path?(path) when is_binary(path), do: String.length(path) <= @max_string_length and path =~ @safe_path
  defp safe_path?(_), do: false

  defp sanitize_string(value, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, @max_string_length)
    |> case do
      "" -> default
      sanitized -> sanitized
    end
  end

  defp sanitize_string(_value, default), do: default
end
