defmodule Nixstasis.Repo.Migrations.CommandAllowlistEntryConstraints do
  use Ecto.Migration

  @name_check "name ~ '^[a-z0-9_.-]+$'"
  @path_check "command_path ~ '^/[^[:space:];&|`$<>(){}\\[\\]*?!''\"]+$'"

  def up do
    create constraint(:command_allowlist_entries, :command_allowlist_entries_name_format, check: @name_check)
    create constraint(:command_allowlist_entries, :command_allowlist_entries_path_format, check: @path_check)

    create constraint(:command_allowlist_entry_versions, :command_allowlist_entry_versions_name_format,
             check: @name_check
           )

    create constraint(:command_allowlist_entry_versions, :command_allowlist_entry_versions_path_format,
             check: @path_check
           )
  end

  def down do
    drop constraint(:command_allowlist_entry_versions, :command_allowlist_entry_versions_path_format)
    drop constraint(:command_allowlist_entry_versions, :command_allowlist_entry_versions_name_format)
    drop constraint(:command_allowlist_entries, :command_allowlist_entries_path_format)
    drop constraint(:command_allowlist_entries, :command_allowlist_entries_name_format)
  end
end
