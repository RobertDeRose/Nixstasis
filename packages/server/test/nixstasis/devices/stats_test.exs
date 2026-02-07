defmodule Nixstasis.Devices.StatsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "dashboard stats" do
    test "count_all/0 returns correct count" do
      assert Devices.count_all() == 0

      {:ok, _} = Devices.register_device(%{mac_address: "AA:AA:AA:AA:AA:AA", product_name: "K"})
      {:ok, _} = Devices.register_device(%{mac_address: "BB:BB:BB:BB:BB:BB", product_name: "K"})

      assert Devices.count_all() == 2
    end

    test "count_by_status/1 counts online/offline devices" do
      # Online device (seen just now)
      {:ok, online} =
        Devices.register_device(%{mac_address: "11:11:11:11:11:11", product_name: "K"})

      {:ok, _} = Devices.update_last_seen(online)

      # Offline device (seen 10 mins ago)
      {:ok, offline} =
        Devices.register_device(%{mac_address: "22:22:22:22:22:22", product_name: "K"})

      # Manually update last_seen_at to be old
      # We need to hack this slightly or use repo directly as update_last_seen sets to now()
      offline
      |> Ecto.Changeset.change(
        last_seen_at: DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.truncate(:second)
      )
      |> Nixstasis.Repo.update()

      # Never seen device (offline)
      {:ok, _never} =
        Devices.register_device(%{mac_address: "33:33:33:33:33:33", product_name: "K"})

      assert Devices.count_by_status(:online) == 1
      assert Devices.count_by_status(:offline) == 2
    end

    test "count_pending_approvals/0 counts pending devices" do
      {:ok, _} =
        Devices.register_device(%{
          mac_address: "44:44:44:44:44:44",
          product_name: "K",
          approval_status: :pending
        })

      {:ok, _} =
        Devices.register_device(%{
          mac_address: "55:55:55:55:55:55",
          product_name: "K",
          approval_status: :pending
        })

      {:ok, app} =
        Devices.register_device(%{mac_address: "66:66:66:66:66:66", product_name: "K"})

      {:ok, _} = Devices.approve_device(app)

      assert Devices.count_pending_approvals() == 2
    end
  end
end
