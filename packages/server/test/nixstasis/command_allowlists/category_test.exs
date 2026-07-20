defmodule Nixstasis.CommandAllowlists.CategoryTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain

  test "categories persist with normalized unique slugs" do
    assert {:ok, category} =
             Domain.create_command_allowlist_category(%{
               display_name: "Network Tools",
               description: "Network diagnostics"
             })

    assert category.slug == "network-tools"

    assert {:error, _} =
             Domain.create_command_allowlist_category(%{
               slug: "NETWORK-TOOLS",
               display_name: "Network Tools Duplicate"
             })
  end

  test "command entries can be tagged with categories" do
    assert {:ok, entry} =
             Domain.create_command_allowlist_entry(%{
               name: "ip",
               command_path: "/usr/sbin/ip"
             })

    assert {:ok, category} =
             Domain.create_command_allowlist_category(%{
               slug: "networking",
               display_name: "Networking"
             })

    assert {:ok, link} =
             Domain.create_command_allowlist_entry_category(%{
               command_entry_id: entry.id,
               category_id: category.id
             })

    assert link.command_entry_id == entry.id
    assert link.category_id == category.id

    assert {:error, _} =
             Domain.create_command_allowlist_entry_category(%{
               command_entry_id: entry.id,
               category_id: category.id
             })
  end
end
