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

  test "generated provisioning URL matches the UUID-bound bootstrap proxy" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:09"})
    host = Nixstasis.Devices.FrpsToken.device_name(device.id) <> "-provisioning"

    assert URI.parse(Provisioning.route_url(device)).host ==
             host <> "." <> Application.get_env(:nixstasis, :base_domain)
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
               readiness_fun: readiness_success_fun(),
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
    assert refreshed_device.remote_access_profile == "default"
    refute refreshed_device.remote_access_requested
  end

  test "waits for the route before posting the bootstrap artifact" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:30"})
    parent = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    assert {:ok, %{state: :succeeded}} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               readiness_timeout_ms: 1_000,
               readiness_interval_ms: 0,
               readiness_backoff_ms: 0,
               readiness_fun: fn url, request_opts ->
                 send(parent, {:readiness_probe, url, request_opts})

                 attempt = Agent.get_and_update(attempts, &{&1, &1 + 1})

                 case attempt do
                   0 -> {:ok, 404}
                   1 -> {:error, :econnrefused}
                   _ -> {:ok, 405}
                 end
               end,
               submit_fun: fn _url, _body, _filename ->
                 send(parent, :artifact_submitted)
                 {:ok, %{job_id: "job-ready", job_url: "/api/jobs/job-ready", state: "submitted"}}
               end,
               get_job_fun: fn _url, _opts ->
                 {:ok, %{"id" => "job-ready", "state" => "succeeded", "result" => %{}}}
               end,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert_receive {:readiness_probe, _url, _opts}
    assert_receive {:readiness_probe, _url, _opts}
    assert_receive {:readiness_probe, _url, _opts}
    assert_received :artifact_submitted
  end

  test "fails and withdraws access when the route never becomes ready" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:31"})
    readiness_state = start_supervised!({Agent, fn -> %{clock: 0, max_request_timeout: 0} end})

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               readiness_timeout_ms: 5,
               readiness_interval_ms: 0,
               readiness_backoff_ms: 0,
               readiness_clock_fun: fn ->
                 Agent.get_and_update(readiness_state, fn state ->
                   {state.clock, %{state | clock: state.clock + 1}}
                 end)
               end,
               readiness_fun: fn _url, request_opts ->
                 request_timeout = Keyword.fetch!(request_opts, :request_timeout_ms)

                 Agent.update(readiness_state, fn state ->
                   %{state | max_request_timeout: max(state.max_request_timeout, request_timeout)}
                 end)

                 {:error, :econnrefused}
               end,
               submit_fun: fn _url, _body, _filename -> flunk("must not post before route readiness") end,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert delivery.state == :failed
    assert delivery.error =~ "route readiness"
    assert delivery.error =~ "timeout"
    assert delivery.lease_withdrawn_at
    refute Devices.get_device!(device.id).remote_access_requested
    readiness_state = Agent.get(readiness_state, & &1)
    assert readiness_state.clock > 0
    assert readiness_state.max_request_timeout <= 5
  end

  test "keeps the lease when a success submission omits its job URL" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:08"})
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "provisioning_audit")

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               readiness_fun: readiness_success_fun(),
               submit_fun: fn _url, _body, _filename ->
                 {:ok, %{job_id: "job-no-url", state: "succeeded"}}
               end,
               get_job_fun: fn _url, _opts -> flunk("must not poll without a job URL") end
             )

    assert delivery.state == :indeterminate
    assert delivery.error =~ "invalid accepted response"
    assert is_nil(delivery.lease_withdrawn_at)
    assert Devices.get_device!(device.id).remote_access_requested
    assert_receive {:provisioning_audit, %{action: :bootstrap_indeterminate, delivery_id: delivery_id}}
    assert delivery_id == delivery.id
  end

  test "keeps the lease when a job response omits its id" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:09"})
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "provisioning_audit")

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               poll_timeout_ms: 0,
               readiness_fun: readiness_success_fun(),
               submit_fun: fn _url, _body, _filename ->
                 {:ok, %{job_id: "job-missing-id", job_url: "/api/jobs/job-missing-id", state: "submitted"}}
               end,
               get_job_fun: fn _url, _opts ->
                 {:ok, %{"state" => "succeeded", "result" => %{"reapply" => false}}}
               end,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert delivery.state == :indeterminate
    assert delivery.error =~ "job polling outcome is unknown"
    assert delivery.error =~ "invalid_job_payload"
    assert is_nil(delivery.lease_withdrawn_at)
    assert Devices.get_device!(device.id).remote_access_requested
    assert_receive {:provisioning_audit, %{action: :bootstrap_indeterminate, delivery_id: delivery_id}}
    assert delivery_id == delivery.id
  end

  test "keeps the lease when a job response id does not match the submitted job" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:10"})
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "provisioning_audit")

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               poll_timeout_ms: 0,
               readiness_fun: readiness_success_fun(),
               submit_fun: fn _url, _body, _filename ->
                 {:ok, %{job_id: "job-expected", job_url: "/api/jobs/job-expected", state: "submitted"}}
               end,
               get_job_fun: fn _url, _opts ->
                 {:ok,
                  %{
                    "id" => "job-other",
                    "state" => "succeeded",
                    "result" => %{"reapply" => false}
                  }}
               end,
               sleep_fun: fn _milliseconds -> :ok end
             )

    assert delivery.state == :indeterminate
    assert delivery.error =~ "job polling outcome is unknown"
    assert delivery.error =~ "invalid_job_payload"
    assert is_nil(delivery.lease_withdrawn_at)
    assert Devices.get_device!(device.id).remote_access_requested
    assert_receive {:provisioning_audit, %{action: :bootstrap_indeterminate, delivery_id: delivery_id}}
    assert delivery_id == delivery.id
  end

  test "keeps the lease for every invalid initial bootstrap reapply value" do
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "provisioning_audit")

    for {invalid_reapply, index} <- Enum.with_index([true, "false", nil, 1]) do
      device =
        device_fixture(%{
          mac_address: "AA:BB:CC:DD:EE:" <> String.pad_leading(to_string(index + 11), 2, "0")
        })

      job_id = "job-reapply-#{index}"

      assert {:ok, delivery} =
               Provisioning.deliver(operator_session(device), device.id, "bundle",
                 filename: "config-bundle.tar.gz",
                 readiness_fun: readiness_success_fun(),
                 submit_fun: fn _url, _body, _filename ->
                   {:ok, %{job_id: job_id, job_url: "/api/jobs/#{job_id}", state: "submitted"}}
                 end,
                 get_job_fun: fn _url, _opts ->
                   {:ok,
                    %{
                      "id" => job_id,
                      "state" => "succeeded",
                      "result" => %{"reapply" => invalid_reapply}
                    }}
                 end,
                 sleep_fun: fn _milliseconds -> :ok end
               )

      assert delivery.state == :indeterminate
      assert delivery.error =~ "invalid result.reapply"
      assert is_nil(delivery.lease_withdrawn_at)
      assert Devices.get_device!(device.id).remote_access_requested
      assert_receive {:provisioning_audit, %{action: :bootstrap_indeterminate, delivery_id: delivery_id}}
      assert delivery_id == delivery.id
    end
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
               readiness_fun: readiness_success_fun(),
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
               readiness_fun: readiness_success_fun(),
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
               readiness_fun: readiness_success_fun(),
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

  test "withdrawal after restart closes the original delivery lease" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:40"})

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               readiness_fun: readiness_success_fun(),
               submit_fun: fn _, _, _ -> {:error, {:transport, :timeout}} end
             )

    restart_process(Devices.RemoteAccessLeases)
    Devices.sync_remote_access_leases()
    restart_process(Provisioning)
    assert Devices.remote_access_active?(Devices.get_device!(device.id))
    assert :ok = Provisioning.withdraw_delivery(operator_session(device), delivery.id)
    refute Devices.remote_access_active?(Devices.get_device!(device.id))
  end

  test "withdrawal after restart preserves another operator's lease and profile" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:41"})

    {:ok, original, operator_lease} =
      Devices.open_remote_access_lease(device, profile: "default", audit_owner: "another-operator", ttl_ms: 120_000)

    assert {:ok, delivery} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               readiness_fun: readiness_success_fun(),
               submit_fun: fn _, _, _ -> {:error, {:transport, :timeout}} end,
               lease_ttl_ms: 60_000
             )

    restart_process(Devices.RemoteAccessLeases)
    Devices.sync_remote_access_leases()
    restart_process(Provisioning)
    assert :ok = Provisioning.withdraw_delivery(operator_session(device), delivery.id)
    remaining = Devices.get_device!(device.id)
    assert Devices.remote_access_lease_active?(operator_lease)
    assert remaining.remote_access_profile == "default"
    assert remaining.remote_access_expires_at == original.remote_access_expires_at
    assert remaining.remote_access_owner == "another-operator"
  end

  test "a new browser lease cannot interrupt an active bootstrap delivery" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:42"})

    {:ok, delivery} =
      Provisioning.deliver(operator_session(device), device.id, "bundle",
        readiness_fun: readiness_success_fun(),
        submit_fun: fn _, _, _ -> {:error, {:transport, :timeout}} end
      )

    bootstrap = Nixstasis.Devices.RemoteAccess.for_owner("provisioning", delivery.id)
    {:ok, selected, browser_id} = Devices.open_remote_access_lease(Devices.get_device!(device.id), profile: "default")
    assert selected.remote_access_profile == "atomixos-bootstrap"
    assert Nixstasis.Devices.RemoteAccess.selected(device.id).id == bootstrap.id
    assert Devices.remote_access_lease_active?(browser_id)
    Provisioning.withdraw_delivery(operator_session(device), delivery.id)
    assert Devices.get_device!(device.id).remote_access_profile == "default"
  end

  test "resume after restart keeps the original lease and closes only that lease on completion" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:43"})
    {:ok, original, operator_id} = Devices.open_remote_access_lease(device, profile: "default", ttl_ms: 120_000)
    {delivery, lease} = running_delivery(device)
    restart_process(Devices.RemoteAccessLeases)
    Devices.sync_remote_access_leases()
    restart_process(Provisioning)

    assert {:ok, finished} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               submit_fun: fn _, _, _ -> flunk("resume must not upload again") end,
               get_job_fun: fn _, _ ->
                 current = Nixstasis.Devices.RemoteAccess.for_owner("provisioning", delivery.id)
                 assert current.id == lease.id
                 assert current.expires_at == lease.expires_at
                 {:ok, %{"id" => "job-resume", "state" => "succeeded", "result" => %{}}}
               end
             )

    assert finished.id == delivery.id
    assert finished.lease_withdrawn_at
    refute Devices.remote_access_lease_active?(lease.id)
    assert Devices.remote_access_lease_active?(operator_id)
    assert Repo.aggregate(Nixstasis.Devices.RemoteAccessLease, :count) == 2
    assert Devices.get_device!(device.id).remote_access_expires_at == original.remote_access_expires_at
  end

  test "resume cannot renew an expired original lease" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:44"})
    {delivery, lease} = running_delivery(device)

    Repo.update_all(from(l in Nixstasis.Devices.RemoteAccessLease, where: l.id == ^lease.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    restart_process(Devices.RemoteAccessLeases)
    Devices.sync_remote_access_leases()
    restart_process(Provisioning)

    assert {:error, :inactive_authorization} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               submit_fun: fn _, _, _ -> flunk("must not upload") end,
               get_job_fun: fn _, _ -> flunk("must not poll without the original authorization") end
             )

    assert Repo.aggregate(Nixstasis.Devices.RemoteAccessLease, :count) == 1
    refute Devices.remote_access_active?(Devices.get_device!(device.id))
    {:ok, updated} = Provisioning.get_delivery(operator_session(device), delivery.id)
    assert updated.lease_withdrawn_at
  end

  test "a terminal delivery invalidates its credential before lease cleanup" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:45"})
    {delivery, lease} = running_delivery(device)
    token = Nixstasis.Devices.FrpsToken.for_heartbeat(Devices.get_device!(device.id))
    {:ok, _} = Nixstasis.Domain.update_provisioning_delivery(delivery, %{state: :succeeded})
    refute Devices.remote_access_lease_active?(lease.id)
    assert {:error, :inactive_authorization} = Nixstasis.Devices.FrpsToken.verify(token)
    restart_process(Devices.RemoteAccessLeases)
    Devices.sync_remote_access_leases()
    refute Devices.get_device!(device.id).remote_access_requested
  end

  test "marks a delivery indeterminate when its route lease expires while polling" do
    device = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:06"})

    assert {:ok, %{state: :indeterminate, lease_withdrawn_at: withdrawn_at}} =
             Provisioning.deliver(operator_session(device), device.id, "bundle",
               filename: "config-bundle.tar.gz",
               lease_ttl_ms: 50,
               readiness_fun: readiness_success_fun(),
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

  defp running_delivery(device) do
    {:ok, delivery} =
      Nixstasis.Domain.create_provisioning_delivery(%{
        device_id: device.id,
        attempt_id: Ecto.UUID.generate(),
        artifact_sha256: Base.encode16(:crypto.hash(:sha256, "bundle"), case: :lower),
        artifact_filename: "config.toml",
        artifact_size: 6,
        state: :running,
        actor_id: "operator@example.invalid",
        started_at: DateTime.utc_now()
      })

    {:ok, delivery} =
      Nixstasis.Domain.update_provisioning_delivery(
        delivery,
        %{job_id: "job-resume", job_url: "https://bootstrap.example/api/jobs/job-resume", job_state: "running"}
      )

    {:ok, _, ref} =
      Devices.open_remote_access_lease(device,
        owner_kind: "provisioning",
        owner_id: delivery.id,
        owner: Process.whereis(Provisioning),
        audit_owner: delivery.actor_id,
        profile: "atomixos-bootstrap",
        ttl_ms: 60_000
      )

    {delivery, Nixstasis.Devices.RemoteAccess.get(ref)}
  end

  defp restart_process(name) do
    child = if name == Devices.RemoteAccessLeases, do: Devices, else: name
    :ok = Supervisor.terminate_child(Nixstasis.Supervisor, child)
    {:ok, _} = Supervisor.restart_child(Nixstasis.Supervisor, child)
  end

  defp readiness_success_fun do
    fn _url, _opts -> {:ok, 405} end
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
