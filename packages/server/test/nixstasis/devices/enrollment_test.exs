defmodule Nixstasis.Devices.EnrollmentTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  setup do
    attrs = %{
      "mac_address" => "02:00:00:10:00:01",
      "product_name" => "enrollment-device",
      "schema" => %{"product" => "enrollment-device", "type" => "object", "properties" => %{}},
      "registration_token" => token(),
      "replacement_token" => token(),
      "metadata" => %{"request" => "initial"}
    }

    %{attrs: attrs}
  end

  test "initial registration can retry after its committed response is lost", %{attrs: attrs} do
    assert {:ok, %{data: first}} = Devices.register_runtime_device(attrs)
    assert first.registration_token == attrs["registration_token"]
    assert {:ok, %{data: retry}} = Devices.register_runtime_device(attrs)
    assert retry.id == first.id
    assert Devices.get_device!(first.id).api_token_hash =~ "registration:"
    refute Map.has_key?(retry, :api_token)
    assert {:error, :forbidden} = Devices.register_runtime_device(Map.put(attrs, "registration_token", token()))
  end

  test "missing initial proof is rejected without creating a stranded record", %{attrs: attrs} do
    assert {:error, %Ash.Error.Invalid{}} = Devices.register_runtime_device(Map.delete(attrs, "registration_token"))
    assert Devices.list_devices() == []
  end

  test "approved exchange retries return the committed token without reapplying attributes", %{attrs: attrs} do
    device = approved(attrs)
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
    assert {:ok, %{data: first}} = Devices.register_runtime_device(attrs)
    assert first.api_token == attrs["replacement_token"]
    assert_receive {:device_registered, _}

    assert {:ok, %{data: retry}} =
             Devices.register_runtime_device(Map.put(attrs, "metadata", %{"request" => "retry"}))

    assert retry.api_token == first.api_token
    assert Devices.get_device!(device.id).metadata == attrs["metadata"]
    refute_receive {:device_registered, _}
    assert Devices.authenticate_device(Devices.get_device!(device.id), first.api_token) == :ok
    assert {:error, :forbidden} = Devices.register_runtime_device(Map.put(attrs, "replacement_token", token()))

    next_exchange = attrs |> Map.put("registration_token", first.api_token) |> Map.put("replacement_token", token())
    assert {:ok, %{data: next}} = Devices.register_runtime_device(next_exchange)
    assert {:error, :forbidden} = Devices.register_runtime_device(attrs)
    assert Devices.authenticate_device(Devices.get_device!(device.id), next.api_token) == :ok
  end

  test "a stale proof loses a competing exchange before attribute mutation", %{attrs: attrs} do
    device = approved(attrs)
    handler_id = "enrollment-exchange-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test_pid and metadata.source == "devices" and String.starts_with?(metadata.query, "SELECT") do
            :telemetry.detach(handler_id)
            send(test_pid, {:winner, Devices.register_runtime_device(attrs)})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    loser = attrs |> Map.put("replacement_token", token()) |> Map.put("metadata", %{"request" => "loser"})
    assert {:error, :forbidden} = Devices.register_runtime_device(loser)
    assert_receive {:winner, {:ok, %{data: winner}}}
    persisted = Devices.get_device!(device.id)
    assert persisted.metadata == attrs["metadata"]
    assert Devices.authenticate_device(persisted, winner.api_token) == :ok
  end

  test "failed exchange updates roll back credential rotation", %{attrs: attrs} do
    device = approved(attrs)
    assert {:error, %Ash.Error.Invalid{}} = Devices.register_runtime_device(Map.put(attrs, "last_seen_at", "invalid"))
    assert Devices.get_device!(device.id).api_token_hash == device.api_token_hash
    assert {:ok, %{data: data}} = Devices.register_runtime_device(attrs)
    assert data.api_token == attrs["replacement_token"]
  end

  test "competing identical exchanges return the same usable token", %{attrs: attrs} do
    device = approved(attrs)
    handler_id = "identical-enrollment-exchange-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test_pid and metadata.source == "devices" and String.starts_with?(metadata.query, "SELECT") do
            :telemetry.detach(handler_id)
            send(test_pid, {:winner, Devices.register_runtime_device(attrs)})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    assert {:ok, %{data: retry}} = Devices.register_runtime_device(attrs)
    assert_receive {:winner, {:ok, %{data: winner}}}
    assert retry.api_token == winner.api_token
    assert Devices.authenticate_device(Devices.get_device!(device.id), retry.api_token) == :ok
  end

  test "public registration preserves operator-owned remote access settings", %{attrs: attrs} do
    device = approved(attrs)
    assert {:ok, _} = Devices.set_remote_access(device, true, "bootstrap")

    params = attrs |> Map.put("remote_access_requested", false) |> Map.put("remote_access_profile", "default")
    assert {:ok, %{data: data}} = Devices.register_runtime_device(params)
    assert data.remote_access_requested
    assert data.remote_access_profile == "bootstrap"

    params = Map.new(params, fn {key, value} -> {String.to_existing_atom(key), value} end)
    params = %{params | registration_token: data.api_token, replacement_token: token()}
    assert {:ok, %{data: data}} = Devices.register_runtime_device(params)
    assert data.remote_access_requested
    assert data.remote_access_profile == "bootstrap"
  end

  test "approved exchange requires a distinct valid replacement", %{attrs: attrs} do
    device = approved(attrs)

    for replacement <- [nil, "short", attrs["registration_token"]] do
      assert {:error, %Ash.Error.Invalid{}} =
               Devices.register_runtime_device(Map.put(attrs, "replacement_token", replacement))

      assert Devices.get_device!(device.id).api_token_hash == device.api_token_hash
    end
  end

  defp approved(attrs) do
    {:ok, %{data: data}} = Devices.register_runtime_device(attrs)
    {:ok, device} = Devices.approve_device(Devices.get_device!(data.id))
    device
  end

  defp token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
