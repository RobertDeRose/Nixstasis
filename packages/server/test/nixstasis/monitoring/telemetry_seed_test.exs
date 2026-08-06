defmodule Nixstasis.Monitoring.TelemetrySeedTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.Telemetry

  test "checks one deterministic telemetry sample with a bounded query" do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => unique_mac(),
        "product_name" => "seed-test-device"
      })

    payload = %{
      "temperature" => 19.5,
      "status" => "ok",
      "deploy_dev_seed_sample" => "schema-builder-v1-1"
    }

    Repo.insert!(%Telemetry{
      device_id: device.id,
      payload: Map.put(payload, "deploy_dev_seed", "schema-builder-v1"),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    handler_id = "telemetry-seed-query-count-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, _metadata, test_pid ->
          send(test_pid, :telemetry_seed_query)
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert Monitoring.telemetry_seed_sample_exists?("schema-builder-v1", device.id, payload)

    assert_receive :telemetry_seed_query
    refute_receive :telemetry_seed_query, 20
  end

  test "serializes callbacks for the same telemetry seed marker" do
    parent = self()

    first =
      Task.async(fn ->
        Monitoring.with_telemetry_seed_lock("schema-builder-lock-test", fn ->
          send(parent, :first_entered)

          receive do
            :release -> :first
          end
        end)
      end)

    assert_receive :first_entered, 1_000

    second =
      Task.async(fn ->
        send(parent, :second_started)

        Monitoring.with_telemetry_seed_lock("schema-builder-lock-test", fn ->
          send(parent, :second_entered)
          :second
        end)
      end)

    assert_receive :second_started, 1_000
    refute_receive :second_entered, 200

    send(first.pid, :release)
    assert {:ok, :first} = Task.await(first, 1_000)
    assert_receive :second_entered, 1_000
    assert {:ok, :second} = Task.await(second, 1_000)
  end

  test "recognizes the legacy batch marker for partial-batch repair" do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => unique_mac(),
        "product_name" => "seed-test-device"
      })

    payload = %{"temperature" => 21.0, "status" => "ok"}

    Repo.insert!(%Telemetry{
      device_id: device.id,
      payload: Map.put(payload, "deploy_dev_seed", "schema-builder-v1"),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    assert Monitoring.telemetry_seed_sample_exists?("schema-builder-v1", device.id, payload)

    refute Monitoring.telemetry_seed_sample_exists?("schema-builder-v1-2", device.id, payload)
  end

  defp unique_mac do
    suffix =
      System.unique_integer([:positive])
      |> rem(0xFFFFFF)
      |> Integer.to_string(16)
      |> String.pad_leading(6, "0")
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.join(":")

    "02:00:00:" <> suffix
  end
end
