defmodule Nixstasis.CommandAllowlists.PolicyResolverTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain

  test "preview resolves selected entries and category tags with provenance and diff" do
    {:ok, df} = Domain.create_command_allowlist_entry(%{name: "df", command_path: "/usr/bin/df"})
    {:ok, ip} = Domain.create_command_allowlist_entry(%{name: "ip", command_path: "/usr/sbin/ip"})
    {:ok, category} = Domain.create_command_allowlist_category(%{slug: "network", display_name: "Network"})
    {:ok, _} = Domain.create_command_allowlist_entry_category(%{command_entry_id: ip.id, category_id: category.id})

    assert {:ok, preview} =
             Domain.preview_command_policy(%{
               entry_ids: [df.id],
               category_ids: [category.id],
               current_commands: %{"df" => "/usr/bin/df", "old" => "/bin/old"}
             })

    assert preview.commands == %{"df" => "/usr/bin/df", "ip" => "/usr/sbin/ip"}
    assert preview.conflicts == []
    assert preview.diff.added == %{"ip" => "/usr/sbin/ip"}
    assert preview.diff.removed == %{"old" => "/bin/old"}
    assert preview.diff.unchanged == %{"df" => "/usr/bin/df"}
    assert [%{source_kind: :category, source_id: category_id}] = preview.provenance["ip"]
    assert category_id == category.id
    assert preview.payload == %{"commands" => preview.commands}
  end

  test "preview ignores archived entries" do
    {:ok, entry} = Domain.create_command_allowlist_entry(%{name: "old", command_path: "/bin/old"})
    {:ok, _entry} = Domain.update_command_allowlist_entry(entry, %{archived_at: DateTime.utc_now()})

    assert {:ok, preview} = Domain.preview_command_policy(%{entry_ids: [entry.id]})
    assert preview.commands == %{}
  end
end
