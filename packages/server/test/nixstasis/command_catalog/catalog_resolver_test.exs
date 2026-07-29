defmodule Nixstasis.CommandCatalog.CatalogResolverTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  describe "catalog resources and compatibility" do
    test "persists catalog entries, mappings, categories, and inventory snapshots" do
      {:ok, category} =
        Domain.create_command_catalog_category(%{slug: "storage", display_name: "Storage"})

      {:ok, command} =
        Domain.create_command_catalog_command(%{
          name: "df",
          display_name: "Disk free",
          description: "Inspect filesystem usage",
          category_slugs: ["storage"],
          risk_notes: "Read-only filesystem usage inspection",
          install_guidance: "Install coreutils for the target OS."
        })

      {:ok, mapping} =
        Domain.create_command_catalog_mapping(%{
          catalog_command_id: command.id,
          os_family: "debian",
          package_manager: "apt",
          package_name: "coreutils",
          command_path: "/usr/bin/df",
          install_hint: "apt install coreutils"
        })

      {:ok, device} = Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:10", product_name: "atom"})
      observed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, snapshot} =
        Domain.create_device_command_inventory_snapshot(%{
          device_id: device.id,
          schema_version: 1,
          probe_catalog_version: "catalog-v1",
          observed_at: observed_at,
          architecture: "x86_64",
          os_release: %{"ID" => "ubuntu", "ID_LIKE" => "debian", "VERSION_ID" => "24.04"},
          os_family: "debian",
          package_manager: "apt",
          packages: %{"coreutils" => %{"installed" => true}},
          commands: %{"df" => %{"path" => "/usr/bin/df"}}
        })

      assert category.slug == "storage"
      assert command.category_slugs == ["storage"]
      assert mapping.package_name == "coreutils"
      assert snapshot.schema_version == 1
      assert snapshot.probe_catalog_version == "catalog-v1"
      assert snapshot.observed_at == observed_at
    end

    test "resolves compatible catalog commands from matching inventory evidence" do
      {:ok, command} = catalog_command("df")
      {:ok, _mapping} = debian_mapping(command, package_name: "coreutils", command_path: "/usr/bin/df")

      {:ok, device} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => true}, %{"df" => "/usr/bin/df"})

      assert {:ok, preview} =
               Domain.preview_catalog_command_compatibility(%{
                 device_ids: [device.id],
                 catalog_command_ids: [command.id]
               })

      assert get_in(preview, [:devices, device.id, :commands, command.name, :status]) == :command_path_resolved
      assert get_in(preview, [:devices, device.id, :commands, command.name, :command_path]) == "/usr/bin/df"
      assert get_in(preview, [:devices, device.id, :commands, command.name, :package_name]) == "coreutils"
    end

    test "resolves Debian, Fedora, and NixOS OS-family mappings" do
      {:ok, command} = catalog_command("df")

      for {os_family, package_manager, os_release} <- [
            {"debian", "apt", %{"ID" => "ubuntu", "ID_LIKE" => "debian"}},
            {"fedora", "dnf", %{"ID" => "rocky", "ID_LIKE" => "rhel fedora"}},
            {"nixos", "nix", %{"ID" => "nixos", "ID_LIKE" => ""}}
          ] do
        {:ok, _mapping} =
          Domain.create_command_catalog_mapping(%{
            catalog_command_id: command.id,
            os_family: os_family,
            package_manager: package_manager,
            package_name: "coreutils",
            command_path: "/usr/bin/df"
          })

        {:ok, device} = inventory_device(os_release, %{"coreutils" => true}, %{"df" => "/usr/bin/df"})

        assert {:ok, preview} =
                 Domain.preview_catalog_command_compatibility(%{
                   device_ids: [device.id],
                   catalog_command_ids: [command.id]
                 })

        assert get_in(preview, [:devices, device.id, :commands, command.name, :status]) == :command_path_resolved
        assert get_in(preview, [:devices, device.id, :commands, command.name, :os_family]) == os_family
      end
    end

    test "treats unsupported OS families as unsupported" do
      {:ok, command} = catalog_command("df")
      {:ok, _mapping} = debian_mapping(command, package_name: "coreutils", command_path: "/usr/bin/df")
      {:ok, device} = inventory_device(%{"ID" => "alpine"}, %{"coreutils" => true}, %{"df" => "/usr/bin/df"})

      assert {:ok, preview} =
               Domain.preview_catalog_command_compatibility(%{
                 device_ids: [device.id],
                 catalog_command_ids: [command.id]
               })

      assert get_in(preview, [:devices, device.id, :commands, command.name, :status]) == :unsupported_os
    end

    test "reports stale inventory for missing, old, or mismatched probe versions" do
      {:ok, command} = catalog_command("df")
      {:ok, _mapping} = debian_mapping(command, package_name: "coreutils", command_path: "/usr/bin/df")
      {:ok, missing_device} = Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:11", product_name: "atom"})

      {:ok, old_device} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => true}, %{"df" => "/usr/bin/df"},
          observed_at: DateTime.utc_now() |> DateTime.add(-11, :minute) |> DateTime.truncate(:second)
        )

      {:ok, mismatch_device} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => true}, %{"df" => "/usr/bin/df"},
          probe_catalog_version: "old-catalog"
        )

      assert {:ok, preview} =
               Domain.preview_catalog_command_compatibility(%{
                 device_ids: [missing_device.id, old_device.id, mismatch_device.id],
                 catalog_command_ids: [command.id]
               })

      for device <- [missing_device, old_device, mismatch_device] do
        assert get_in(preview, [:devices, device.id, :commands, command.name, :status]) == :stale_inventory
      end
    end

    test "rejects client-only commands and reports supported, missing package, or path conflicts" do
      {:ok, command} = catalog_command("df")
      {:ok, _mapping} = debian_mapping(command, package_name: "coreutils", command_path: "/usr/bin/df")

      {:ok, supported} = inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{}, %{})

      {:ok, missing_package} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => false}, %{"df" => "/usr/bin/df"})

      {:ok, conflict} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => true}, %{"df" => "/tmp/df"})

      {:ok, client_only} =
        inventory_device(%{"ID" => "ubuntu", "ID_LIKE" => "debian"}, %{"coreutils" => true}, %{"evil" => "/bin/sh"})

      assert {:ok, preview} =
               Domain.preview_catalog_command_compatibility(%{
                 device_ids: [supported.id, missing_package.id, conflict.id, client_only.id],
                 catalog_command_ids: [command.id]
               })

      assert get_in(preview, [:devices, supported.id, :commands, command.name, :status]) == :supported
      assert get_in(preview, [:devices, missing_package.id, :commands, command.name, :status]) == :missing_package
      assert get_in(preview, [:devices, conflict.id, :commands, command.name, :status]) == :conflict
      assert get_in(preview, [:devices, client_only.id, :commands, command.name, :status]) == :package_installed
      refute Map.has_key?(preview.devices[client_only.id].commands, "evil")
    end

    test "normalizes inventory and ignores unprobed or unsafe evidence" do
      {:ok, command} = catalog_command("df")
      {:ok, _mapping} = debian_mapping(command, package_name: "coreutils", command_path: "/usr/bin/df")
      {:ok, device} = Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:12", product_name: "atom"})

      {:ok, snapshot} =
        Domain.create_device_command_inventory_snapshot(%{
          device_id: device.id,
          schema_version: 1,
          probe_catalog_version: "catalog-v1",
          observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          architecture: String.duplicate("x", 300),
          os_family: "debian",
          os_release: %{"ID" => "alpine", "UNTRUSTED" => "ignored"},
          package_manager: "apt",
          packages: %{"coreutils" => true, "client-only" => true},
          commands: %{
            "df" => %{"path" => "/usr/bin/df"},
            "evil" => %{"path" => "/bin/sh"},
            "unsafe" => %{"path" => "/bin/sh;rm"}
          }
        })

      assert snapshot.os_family == "unsupported"
      assert snapshot.os_release == %{"ID" => "alpine"}
      assert snapshot.packages == %{"coreutils" => %{"installed" => true}}
      assert snapshot.commands == %{"df" => %{"path" => "/usr/bin/df"}}
      assert String.length(snapshot.architecture) == 256
    end

    test "seed data creates catalog commands and the probe manifest exposes them" do
      {_, _binding} = Code.eval_file("priv/repo/seeds.exs")

      assert {:ok, commands} = Domain.list_command_catalog_commands()
      assert Enum.any?(commands, &(&1.name == "df"))
      assert Enum.any?(commands, &(&1.name == "uname"))
      assert Enum.any?(commands, &(&1.name == "journalctl"))

      assert {:ok, manifest} = Domain.command_inventory_probe_manifest()
      assert "coreutils" in manifest.package_names
      assert Enum.any?(manifest.command_probes, &(&1.name == "df" and &1.command_path == "/usr/bin/df"))
    end
  end

  defp catalog_command(name) do
    Domain.create_command_catalog_command(%{
      name: name,
      display_name: String.upcase(name),
      category_slugs: ["diagnostics"]
    })
  end

  defp debian_mapping(command, opts) do
    Domain.create_command_catalog_mapping(%{
      catalog_command_id: command.id,
      os_family: "debian",
      package_manager: "apt",
      package_name: Keyword.fetch!(opts, :package_name),
      command_path: Keyword.fetch!(opts, :command_path)
    })
  end

  defp inventory_device(os_release, packages, commands, opts \\ []) do
    {:ok, device} = Devices.create_device(%{mac_address: unique_mac(), product_name: "atom"})

    {:ok, _snapshot} =
      Domain.create_device_command_inventory_snapshot(%{
        device_id: device.id,
        schema_version: 1,
        probe_catalog_version: Keyword.get(opts, :probe_catalog_version, "catalog-v1"),
        observed_at: Keyword.get(opts, :observed_at, DateTime.utc_now() |> DateTime.truncate(:second)),
        architecture: "x86_64",
        os_release: os_release,
        package_manager: "apt",
        packages: Map.new(packages, fn {name, installed?} -> {name, %{"installed" => installed?}} end),
        commands: Map.new(commands, fn {name, path} -> {name, %{"path" => path}} end)
      })

    {:ok, device}
  end

  defp unique_mac do
    <<a::16>> = :crypto.strong_rand_bytes(2)

    "AA:BB:CC:DD:#{Integer.to_string(div(a, 256), 16) |> String.pad_leading(2, "0")}:#{Integer.to_string(rem(a, 256), 16) |> String.pad_leading(2, "0")}"
  end
end
