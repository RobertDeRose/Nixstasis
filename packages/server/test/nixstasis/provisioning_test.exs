defmodule Nixstasis.ProvisioningTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Provisioning

  setup do
    :ok = Provisioning.reset()

    on_exit(fn ->
      :ok = Provisioning.reset()
    end)

    :ok
  end

  test "delivers a raw config through the bootstrap route and withdraws access" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:01"})
    parent = self()

    submit_fun = fn url, body, filename ->
      send(parent, {:submitted, url, body, filename})
      {:ok, %{job_id: "job-1", job_url: "/api/jobs/job-1", state: "submitted"}}
    end

    get_job_fun = fn url, _opts ->
      assert String.ends_with?(url, "/api/jobs/job-1")

      {:ok,
       %{
         "id" => "job-1",
         "state" => "succeeded",
         "current_step" => "complete",
         "events" => [%{"step" => "activate", "status" => "ok"}],
         "result" => %{"reapply" => false, "warnings" => []}
       }}
    end

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "config = true\n",
               filename: "config.toml",
               submit_fun: submit_fun,
               get_job_fun: get_job_fun,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert delivery.state == :succeeded
    assert delivery.job_id == "job-1"
    assert delivery.artifact_filename == "config.toml"
    assert delivery.artifact_size == 14
    assert delivery.result == %{"reapply" => false, "warnings" => []}
    assert_received {:submitted, url, "config = true\n", "config.toml"}
    assert url =~ "/api/config"

    refreshed_device = Devices.get_device!(device.id)
    assert refreshed_device.remote_access_profile == "atomixos-bootstrap"
    refute refreshed_device.remote_access_requested
  end

  test "returns a terminal success idempotently without reposting" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:07"})

    submit_fun = fn _url, _body, _filename ->
      {:ok, %{job_id: "job-idempotent", job_url: "/api/jobs/job-idempotent", state: "submitted"}}
    end

    get_job_fun = fn _url, _opts ->
      {:ok, %{"id" => "job-idempotent", "state" => "succeeded", "result" => %{"reapply" => false}}}
    end

    assert {:ok, %{state: :succeeded} = delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               submit_fun: submit_fun,
               get_job_fun: get_job_fun,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert {:ok, replayed} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               submit_fun: fn _url, _body, _filename -> flunk("must not repost a terminal success") end
             )

    assert replayed.id == delivery.id
    assert replayed.state == :succeeded
  end

  test "retries only a queue-full response before submitting once" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:02"})
    counter = start_supervised!({Agent, fn -> 0 end})

    submit_fun = fn _url, _body, _filename ->
      attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)

      if attempt == 1 do
        {:error, {:http, 409, "the provision queue is full"}}
      else
        {:ok, %{job_id: "job-2", job_url: "/api/jobs/job-2", state: "running"}}
      end
    end

    get_job_fun = fn url, _opts ->
      assert String.ends_with?(url, "/api/jobs/job-2")
      {:ok, %{"id" => "job-2", "state" => "succeeded", "result" => %{"reapply" => false}}}
    end

    assert {:ok, %{state: :succeeded}} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               submit_fun: submit_fun,
               get_job_fun: get_job_fun,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert Agent.get(counter, & &1) == 2
  end

  test "keeps access and records an indeterminate delivery after an ambiguous upload" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:03"})

    assert {:ok, %{state: :indeterminate} = delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               submit_fun: fn _url, _body, _filename -> {:error, {:transport, :timeout}} end,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert Devices.get_device!(device.id).remote_access_requested

    assert {:error, {:reconciliation_required, reconciliation}} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               submit_fun: fn _url, _body, _filename -> flunk("must not resubmit") end
             )

    assert reconciliation.id == delivery.id
    assert reconciliation.state == :indeterminate

    assert :ok = Provisioning.withdraw_delivery(operator_session(device), delivery.id)
    refute Devices.get_device!(device.id).remote_access_requested
  end

  test "marks a delivery indeterminate when its route lease expires while polling" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:06"})

    assert {:ok, %{state: :indeterminate, lease_withdrawn_at: withdrawn_at}} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               lease_ttl_ms: 50,
               submit_fun: fn _url, _body, _filename ->
                 Process.sleep(100)
                 {:ok, %{job_id: "job-expiring", job_url: "/api/jobs/job-expiring", state: "running"}}
               end,
               get_job_fun: fn _url, _opts -> flunk("must not poll after lease expiry") end
             )

    assert withdrawn_at
    refute Devices.get_device!(device.id).remote_access_requested
  end

  test "rejects unauthorized and unapproved devices before opening a lease" do
    pending = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:04", approval_status: :pending})
    unauthorized = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:05"})

    assert {:error, :device_not_approved} =
             Provisioning.deliver(operator_session(pending), pending.id, "config = true\n")

    assert {:error, :unauthorized} =
             Provisioning.deliver(operator_session(pending), unauthorized.id, "config = true\n")

    refute Devices.get_device!(pending.id).remote_access_requested
    refute Devices.get_device!(unauthorized.id).remote_access_requested
  end

  defp device_fixture(attrs) do
    {:ok, device} =
      Devices.create_device(
        Map.merge(
          %{
            mac_address: "AA:BB:CC:DD:EE:FF",
            product_name: "atom-bootstrap",
            approval_status: :approved,
            last_seen_at: DateTime.utc_now()
          },
          attrs
        )
      )

    device
  end

  defp operator_session(device) do
    %{
      "device_permissions" => %{
        "can_remote_access" => true,
        "device_ids" => [device.id]
      },
      "operator_context" => %{"subject" => "operator@example.invalid"}
    }
  end
end
