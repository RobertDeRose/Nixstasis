defmodule Nixstasis.CommandAllowlists.PolicyResolverTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain
  alias Nixstasis.Repo

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

  test "combined preflight rejects more than 2,500 manual and catalog command names" do
    entry_ids = Enum.map(1..2_500, fn _index -> Ecto.UUID.generate() end)
    catalog_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    entry_rows =
      Enum.zip(entry_ids, 1..2_500)
      |> Enum.map(fn {id, index} ->
        name = "combined-manual-#{index}"

        %{
          id: Ecto.UUID.dump!(id),
          name: name,
          name_key: name,
          description: "",
          command_path: "/usr/bin/#{name}",
          current_version: 1,
          archived_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    {2_500, nil} = Repo.insert_all("command_allowlist_entries", entry_rows)

    {1, nil} =
      Repo.insert_all("command_catalog_commands", [
        %{
          id: Ecto.UUID.dump!(catalog_id),
          name: "combined-catalog",
          name_key: "combined-catalog",
          display_name: "combined-catalog",
          description: "",
          category_slugs: [],
          risk_notes: "",
          install_guidance: "",
          current_version: 1,
          active: true,
          inserted_at: now,
          updated_at: now
        }
      ])

    assert {:error, {:command_policy_limit_exceeded, %{kind: :commands, limit: 2_500, actual: 2_501}}} =
             Domain.preflight_command_policy(%{entry_ids: entry_ids, catalog_command_ids: [catalog_id]})
  end

  test "preview ignores archived entries" do
    {:ok, entry} = Domain.create_command_allowlist_entry(%{name: "old", command_path: "/bin/old"})
    {:ok, _entry} = Domain.update_command_allowlist_entry(entry, %{archived_at: DateTime.utc_now()})

    assert {:ok, preview} = Domain.preview_command_policy(%{entry_ids: [entry.id]})
    assert preview.commands == %{}
  end

  test "preview rejects more than 2,500 resolved command names before loading entries" do
    ids = Enum.map(1..2_501, fn _index -> Ecto.UUID.generate() end)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.zip(ids, 1..2_501)
      |> Enum.map(fn {id, index} ->
        name = "bounded-#{index}"

        %{
          id: Ecto.UUID.dump!(id),
          name: name,
          name_key: name,
          description: "",
          command_path: "/usr/bin/#{name}",
          current_version: 1,
          archived_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    {2_501, nil} = Repo.insert_all("command_allowlist_entries", rows)

    assert {:error, {:command_policy_limit_exceeded, %{kind: :commands, limit: 2_500, actual: 2_501}}} =
             Domain.preview_command_policy(%{entry_ids: ids})
  end
end
