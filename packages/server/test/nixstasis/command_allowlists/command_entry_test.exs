defmodule Nixstasis.CommandAllowlists.CommandEntryTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain

  test "command entries persist with case-insensitive name keys and archive state" do
    assert {:ok, entry} =
             Domain.create_command_allowlist_entry(%{
               name: "disk_usage",
               description: "Read disk usage",
               command_path: "/usr/bin/df"
             })

    assert entry.current_version == 1
    assert is_nil(entry.archived_at)

    assert {:ok, _version} =
             Domain.create_command_allowlist_entry_version(%{
               command_entry_id: entry.id,
               version: entry.current_version,
               name: entry.name,
               description: entry.description,
               command_path: entry.command_path
             })

    assert {:error, _} =
             Domain.create_command_allowlist_entry(%{
               name: "DISK_USAGE",
               command_path: "/bin/df"
             })

    archived_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, archived} =
             Domain.update_command_allowlist_entry(entry, %{
               archived_at: archived_at,
               current_version: 2
             })

    assert archived.archived_at == archived_at
    assert archived.current_version == 2
  end

  test "entry versions are immutable through the public domain" do
    assert {:ok, entry} =
             Domain.create_command_allowlist_entry(%{
               name: "uptime",
               command_path: "/usr/bin/uptime"
             })

    assert {:ok, version} =
             Domain.create_command_allowlist_entry_version(%{
               command_entry_id: entry.id,
               version: 1,
               name: entry.name,
               command_path: entry.command_path
             })

    refute function_exported?(Domain, :update_command_allowlist_entry_version, 2)
    assert version.version == 1
  end
end
