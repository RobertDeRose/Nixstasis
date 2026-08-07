defmodule Nixstasis.Provisioning do
  @moduledoc """
  Delivers one complete first-boot AtomixOS artifact through the authorized FRP route.

  The action never unpacks or mutates an artifact locally. It owns operator
  authorization, the leased `atomixos-bootstrap` route, bounded submission and
  polling, durable delivery state, and lease withdrawal after a terminal result.
  """

  use GenServer

  require Ash.Query
  require Logger

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain
  alias Nixstasis.Provisioning.Artifact
  alias Nixstasis.Provisioning.Audit
  alias Nixstasis.Provisioning.Delivery
  alias Nixstasis.Provisioning.HTTPClient
  alias NixstasisWeb.Permissions

  @name __MODULE__
  @route_profile "atomixos-bootstrap"
  @default_base_domain "example.com"
  @default_poll_timeout_ms 5 * 60 * 1_000
  @default_poll_interval_ms 500
  @default_retry_backoff_ms 250
  @default_request_timeout_ms 30_000
  @default_conflict_retries 2
  @max_job_payload_size 1 * 1024 * 1024
  @server_call_timeout_ms @default_poll_timeout_ms + @default_request_timeout_ms + 10_000
  @active_states [:submitting, :submitted, :running]
  @job_states ~w(submitted running succeeded failed)

  @type delivery_result :: {:ok, Delivery.t()} | {:error, term()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc "Starts or resumes one explicitly authorized bootstrap attempt."
  @spec deliver(map(), String.t(), binary(), keyword()) :: delivery_result()
  def deliver(session, device_id, artifact, opts \\ []) do
    timeout =
      opts
      |> Keyword.get(:call_timeout, @server_call_timeout_ms)
      |> max(1)
      |> min(@server_call_timeout_ms)

    GenServer.call(@name, {:deliver, session, device_id, artifact, opts}, timeout)
  end

  @doc "Returns a delivery visible to the authorized operator."
  def get_delivery(session, delivery_id) do
    with {:ok, delivery} <- fetch_delivery(delivery_id),
         {:ok, _device} <- authorized_device(session, delivery.device_id) do
      {:ok, delivery}
    end
  end

  @doc "Withdraws a retained indeterminate lease without submitting another artifact."
  def withdraw_delivery(session, delivery_id) do
    with {:ok, delivery} <- get_delivery(session, delivery_id) do
      GenServer.call(@name, {:withdraw, delivery})
    end
  end

  @doc false
  def reset do
    GenServer.call(@name, :reset)
  end

  @doc false
  def max_artifact_size, do: Artifact.max_size()

  @doc "Serializes a delivery without exposing artifact bytes."
  def data(%Delivery{} = delivery) do
    %{
      id: delivery.id,
      device_id: delivery.device_id,
      attempt_id: delivery.attempt_id,
      artifact_sha256: delivery.artifact_sha256,
      artifact_filename: delivery.artifact_filename,
      artifact_size: delivery.artifact_size,
      state: Atom.to_string(delivery.state),
      job_id: delivery.job_id,
      job_url: delivery.job_url,
      job_state: delivery.job_state,
      current_step: delivery.current_step,
      events: Map.get(delivery.job_payload, "events", []),
      result: delivery.result,
      error: delivery.error,
      rollback_status: delivery.rollback_status,
      started_at: delivery.started_at,
      completed_at: delivery.completed_at,
      lease_withdrawn_at: delivery.lease_withdrawn_at
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc false
  def route_url(%Device{} = device) do
    case Application.get_env(:nixstasis, :provisioning_base_url) do
      base when is_binary(base) and base != "" ->
        String.trim_trailing(base, "/")

      _ ->
        normalized_mac =
          device.mac_address
          |> String.replace(~r/[^a-fA-F0-9]/, "")
          |> String.downcase()

        base_domain = Application.get_env(:nixstasis, :base_domain, @default_base_domain)
        "https://atom-#{normalized_mac}.#{String.trim(to_string(base_domain), ".")}"
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{leases: %{}}}

  @impl true
  def handle_call({:deliver, session, device_id, bytes, opts}, _from, state) do
    {reply, state} = deliver_request(session, device_id, bytes, opts, state)
    {:reply, reply, state}
  end

  def handle_call({:withdraw, %Delivery{} = delivery}, _from, state) do
    if delivery.lease_withdrawn_at do
      {:reply, :ok, state}
    else
      {lease_ref, leases} = Map.pop(state.leases, delivery.id)
      state = %{state | leases: leases}

      if lease_ref do
        :ok = Devices.close_remote_access_lease(lease_ref)
      end

      updated = update_delivery(delivery, %{lease_withdrawn_at: DateTime.utc_now()})
      Audit.emit(:bootstrap_lease_withdrawn, delivery.actor_id, delivery_attributes(updated))
      {:reply, :ok, state}
    end
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.leases, fn {_delivery_id, lease_ref} ->
      Devices.close_remote_access_lease(lease_ref)
    end)

    {:reply, :ok, %{leases: %{}}}
  end

  @impl true
  def handle_info({:remote_access_lease_expired, lease_ref}, state) do
    case Enum.find(state.leases, fn {_delivery_id, ref} -> ref == lease_ref end) do
      {delivery_id, _lease_ref} ->
        state = %{state | leases: Map.delete(state.leases, delivery_id)}
        record_lease_expiry(delivery_id)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp deliver_request(session, device_id, bytes, opts, state) do
    with {:ok, device} <- fetch_device(device_id),
         {:ok, _authorized_device} <- authorized_device(session, device.id),
         :ok <- ensure_approved(device),
         :ok <- ensure_online(device),
         {:ok, actor_id} <- Permissions.actor_id(session),
         {:ok, artifact} <- Artifact.prepare(bytes, Keyword.get(opts, :filename, "config.toml")),
         {:ok, attempt_id} <- normalize_attempt_id(Keyword.get(opts, :attempt_id)) do
      choose_delivery(device, artifact, attempt_id, actor_id, session, opts, state)
    else
      {:error, reason} ->
        Audit.emit(:bootstrap_rejected, actor_id(session), %{device_id: device_id, reason: inspect(reason)})
        {{:error, reason}, state}
    end
  end

  defp choose_delivery(device, artifact, attempt_id, actor_id, session, opts, state) do
    deliveries = list_deliveries(device.id, artifact.sha256)

    case existing_action(deliveries, attempt_id) do
      {:return, delivery} -> {{:ok, delivery}, state}
      {:error, reason} -> {{:error, reason}, state}
      {:resume, delivery} -> resume_delivery(delivery, device, actor_id, opts, state)
      :new -> start_delivery(device, artifact, attempt_id, actor_id, session, opts, state)
    end
  end

  defp existing_action(deliveries, attempt_id) do
    matching = Enum.find(deliveries, &(not is_nil(attempt_id) and &1.attempt_id == attempt_id))

    cond do
      matching && matching.state in [:succeeded, :failed, :indeterminate] ->
        {:return, matching}

      matching && matching.state in @active_states ->
        {:resume, matching}

      matching ->
        {:error, {:existing_delivery, matching}}

      Enum.find(deliveries, &(&1.state == :succeeded)) ->
        {:return, Enum.find(deliveries, &(&1.state == :succeeded))}

      active = Enum.find(deliveries, &(&1.state in @active_states)) ->
        {:resume, active}

      indeterminate = Enum.find(deliveries, &(&1.state == :indeterminate)) ->
        if is_binary(attempt_id) do
          :new
        else
          {:error, {:reconciliation_required, indeterminate}}
        end

      true ->
        require_new_attempt(deliveries, attempt_id)
    end
  end

  defp require_new_attempt([], _attempt_id), do: :new
  defp require_new_attempt(_deliveries, nil), do: {:error, :new_attempt_required}
  defp require_new_attempt(_deliveries, _attempt_id), do: :new

  defp start_delivery(device, artifact, attempt_id, actor_id, _session, opts, state) do
    attrs = %{
      device_id: device.id,
      attempt_id: attempt_id || Ecto.UUID.generate(),
      artifact_sha256: artifact.sha256,
      artifact_filename: artifact.filename,
      artifact_size: artifact.size,
      state: :submitting,
      actor_id: actor_id,
      started_at: DateTime.utc_now()
    }

    case Domain.create_provisioning_delivery(attrs) do
      {:ok, delivery} ->
        case open_bootstrap_lease(device, opts) do
          {:ok, _updated_device, lease_ref} ->
            state = put_in(state.leases[delivery.id], lease_ref)
            Audit.emit(:bootstrap_started, actor_id, delivery_attributes(delivery))

            if lease_active?(state, delivery.id) do
              execute_delivery(delivery, device, artifact, actor_id, opts, state)
            else
              finish_failed(state, delivery, actor_id, "remote-access lease expired before upload")
            end

          {:error, reason} ->
            finish_failed(state, delivery, actor_id, "could not open remote-access lease: #{inspect(reason)}")
        end

      {:error, reason} ->
        Audit.emit(:bootstrap_rejected, actor_id, %{device_id: device.id, reason: inspect(reason)})
        {{:error, reason}, state}
    end
  end

  defp resume_delivery(%Delivery{state: :succeeded} = delivery, _device, _actor_id, _opts, state),
    do: {{:ok, delivery}, state}

  defp resume_delivery(%Delivery{state: :failed} = delivery, _device, _actor_id, _opts, state),
    do: {{:ok, delivery}, state}

  defp resume_delivery(%Delivery{state: :indeterminate} = delivery, _device, _actor_id, _opts, state),
    do: {{:error, {:reconciliation_required, delivery}}, state}

  defp resume_delivery(delivery, device, actor_id, opts, state) do
    case ensure_lease(delivery, device, opts, state) do
      {:ok, lease_state} when is_binary(delivery.job_url) ->
        get_job_fun = Keyword.get(opts, :get_job_fun, default_get_job_fun(opts))
        poll_delivery(delivery, actor_id, get_job_fun, opts, lease_state)

      {:ok, lease_state} ->
        finish_indeterminate(lease_state, delivery, actor_id, "delivery has no job URL to poll")

      {:error, reason, lease_state} ->
        {{:error, reason}, lease_state}
    end
  end

  defp execute_delivery(delivery, device, artifact, actor_id, opts, state) do
    base_url = Keyword.get(opts, :base_url, route_url(device))
    post_url = join_url(base_url, "/api/config")
    submit_fun = Keyword.get(opts, :submit_fun, default_submit_fun(opts))
    get_job_fun = Keyword.get(opts, :get_job_fun, default_get_job_fun(opts))

    case submit_with_conflict_retries(submit_fun, post_url, artifact, opts) do
      {:ok, response} ->
        case normalize_submission(response, base_url) do
          {:ok, submission} ->
            delivery =
              update_delivery(delivery, %{
                state: delivery_state(submission.state),
                job_id: submission.job_id,
                job_url: submission.job_url,
                job_state: submission.state,
                job_payload: submission.payload
              })

            if is_binary(submission.job_url) do
              poll_delivery(delivery, actor_id, get_job_fun, opts, state)
            else
              case submission.state do
                "succeeded" -> finish_succeeded(state, delivery, actor_id)
                "failed" -> finish_failed(state, delivery, actor_id, submission_error(submission.payload))
                _ -> finish_indeterminate(state, delivery, actor_id, "accepted response did not include job_url")
              end
            end

          {:error, reason} ->
            finish_indeterminate(state, delivery, actor_id, "invalid accepted response: #{inspect(reason)}")
        end

      {:error, {:http, 409, message}} ->
        finish_failed(state, delivery, actor_id, "AtomixOS rejected the submission: #{message}")

      {:error, {:http, status, message}} when status >= 500 ->
        finish_indeterminate(state, delivery, actor_id, "ambiguous AtomixOS HTTP #{status}: #{message}")

      {:error, {:transport, reason}} ->
        finish_indeterminate(state, delivery, actor_id, "ambiguous upload transport error: #{inspect(reason)}")

      {:error, reason} ->
        finish_failed(state, delivery, actor_id, "submission failed: #{inspect(reason)}")
    end
  end

  defp submit_with_conflict_retries(submit_fun, url, artifact, opts, attempt \\ 0) do
    case submit_fun.(url, artifact.bytes, artifact.filename) do
      {:error, {:http, 409, _message}} = error ->
        max_retries =
          opts
          |> Keyword.get(:conflict_retries, @default_conflict_retries)
          |> max(0)
          |> min(@default_conflict_retries)

        if attempt < max_retries do
          sleep_fun(opts).(retry_delay(attempt, opts))
          submit_with_conflict_retries(submit_fun, url, artifact, opts, attempt + 1)
        else
          error
        end

      result ->
        result
    end
  end

  defp poll_delivery(delivery, actor_id, get_job_fun, opts, state) do
    deadline = monotonic_ms() + poll_timeout(opts)
    poll_delivery_until_deadline(delivery, actor_id, get_job_fun, opts, state, deadline)
  end

  defp poll_delivery_until_deadline(delivery, actor_id, get_job_fun, opts, state, deadline) do
    if lease_active?(state, delivery.id) do
      poll_delivery_request(delivery, actor_id, get_job_fun, opts, state, deadline)
    else
      finish_expired(state, delivery, actor_id, "remote-access lease expired while polling")
    end
  end

  defp poll_delivery_request(delivery, actor_id, get_job_fun, opts, state, deadline) do
    case get_job_fun.(delivery.job_url, request_timeout_ms: request_timeout(opts)) do
      {:ok, payload} ->
        case normalize_job(payload, delivery.job_id) do
          {:ok, job} ->
            delivery = update_delivery(delivery, job_attributes(job))

            case job.state do
              "succeeded" ->
                finish_succeeded(state, delivery, actor_id)

              "failed" ->
                finish_failed(state, delivery, actor_id, job_error(job))

              job_state when job_state in ["submitted", "running"] ->
                if monotonic_ms() >= deadline do
                  finish_indeterminate(state, delivery, actor_id, "job polling deadline exceeded")
                else
                  sleep_fun(opts).(poll_delay(opts))
                  poll_delivery_until_deadline(delivery, actor_id, get_job_fun, opts, state, deadline)
                end

              _ ->
                finish_indeterminate(state, delivery, actor_id, "AtomixOS returned an unknown job state")
            end

          {:error, reason} ->
            poll_or_mark_indeterminate(delivery, actor_id, get_job_fun, opts, state, deadline, reason)
        end

      {:error, {:http, 404, message}} ->
        finish_failed(state, delivery, actor_id, "AtomixOS job was not found: #{message}")

      {:error, reason} ->
        poll_or_mark_indeterminate(delivery, actor_id, get_job_fun, opts, state, deadline, reason)
    end
  end

  defp poll_or_mark_indeterminate(delivery, actor_id, get_job_fun, opts, state, deadline, reason) do
    if monotonic_ms() >= deadline do
      finish_indeterminate(state, delivery, actor_id, "job polling outcome is unknown: #{inspect(reason)}")
    else
      sleep_fun(opts).(poll_delay(opts))
      poll_delivery_until_deadline(delivery, actor_id, get_job_fun, opts, state, deadline)
    end
  end

  defp lease_active?(state, delivery_id) do
    case Map.get(state.leases, delivery_id) do
      lease_ref when is_binary(lease_ref) -> Devices.remote_access_lease_active?(lease_ref)
      _ -> false
    end
  end

  defp finish_expired(state, delivery, actor_id, message) do
    updated = update_delivery(delivery, %{state: :indeterminate, error: truncate(message)})
    {updated, state} = close_lease(state, updated)
    Audit.emit(:bootstrap_lease_expired, actor_id, delivery_attributes(updated))
    Audit.emit(:bootstrap_indeterminate, actor_id, delivery_attributes(updated))
    {{:ok, updated}, state}
  end

  defp record_lease_expiry(delivery_id) do
    with {:ok, delivery} <- fetch_delivery(delivery_id),
         false <- delivery.lease_withdrawn_at != nil do
      attrs =
        if delivery.state in @active_states do
          %{state: :indeterminate, error: "remote-access lease expired while provisioning"}
        else
          %{}
        end

      updated = update_delivery(delivery, Map.put(attrs, :lease_withdrawn_at, DateTime.utc_now()))
      Audit.emit(:bootstrap_lease_expired, delivery.actor_id, delivery_attributes(updated))
    else
      _ -> :ok
    end
  end

  defp open_bootstrap_lease(device, opts) do
    lease_opts = [owner: self(), profile: @route_profile]

    lease_opts =
      case Keyword.fetch(opts, :lease_ttl_ms) do
        {:ok, ttl_ms} when is_integer(ttl_ms) -> Keyword.put(lease_opts, :ttl_ms, max(1, min(ttl_ms, 3_600_000)))
        _ -> lease_opts
      end

    Devices.open_remote_access_lease(device, lease_opts)
  end

  defp ensure_lease(delivery, device, opts, state) do
    case Map.has_key?(state.leases, delivery.id) do
      true ->
        {:ok, state}

      false ->
        case open_bootstrap_lease(device, opts) do
          {:ok, _updated, lease_ref} -> {:ok, put_in(state.leases[delivery.id], lease_ref)}
          {:error, reason} -> {:error, reason, state}
        end
    end
  end

  defp finish_succeeded(state, delivery, actor_id) do
    result = Map.get(delivery.result, "reapply")

    if result == true do
      finish_failed(state, delivery, actor_id, "AtomixOS reported reapply=true for an initial bootstrap")
    else
      updated = update_delivery(delivery, %{state: :succeeded, completed_at: DateTime.utc_now()})
      {updated, state} = close_lease(state, updated)
      Audit.emit(:bootstrap_succeeded, actor_id, delivery_attributes(updated))
      {{:ok, updated}, state}
    end
  end

  defp finish_failed(state, delivery, actor_id, message) do
    updated =
      update_delivery(delivery, %{
        state: :failed,
        error: truncate(message),
        completed_at: DateTime.utc_now()
      })

    {updated, state} = close_lease(state, updated)
    Audit.emit(:bootstrap_failed, actor_id, delivery_attributes(updated))
    {{:ok, updated}, state}
  end

  defp finish_indeterminate(state, delivery, actor_id, message) do
    updated = update_delivery(delivery, %{state: :indeterminate, error: truncate(message)})
    Audit.emit(:bootstrap_indeterminate, actor_id, delivery_attributes(updated))
    {{:ok, updated}, state}
  end

  defp close_lease(state, delivery) do
    {lease_ref, leases} = Map.pop(state.leases, delivery.id)
    state = %{state | leases: leases}

    if lease_ref do
      :ok = Devices.close_remote_access_lease(lease_ref)
    end

    updated = update_delivery(delivery, %{lease_withdrawn_at: DateTime.utc_now()})
    {updated, state}
  end

  defp fetch_device(device_id) do
    case Devices.get_device(device_id) do
      {:ok, %Device{} = device} -> {:ok, device}
      _ -> {:error, :not_found}
    end
  end

  defp authorized_device(session, device_id) do
    case Devices.get_device(device_id) do
      {:ok, %Device{} = device} ->
        if Permissions.can_remote_access_device?(Permissions.device_permissions(session), device.id) do
          {:ok, device}
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp ensure_approved(%Device{approval_status: :approved}), do: :ok
  defp ensure_approved(_device), do: {:error, :device_not_approved}

  defp ensure_online(%Device{} = device) do
    if Devices.online?(device), do: :ok, else: {:error, :device_offline}
  end

  defp actor_id(session) do
    case Permissions.actor_id(session) do
      {:ok, actor_id} -> actor_id
      {:error, _reason} -> "unknown-operator"
    end
  end

  defp normalize_attempt_id(nil), do: {:ok, nil}

  defp normalize_attempt_id(attempt_id) when is_binary(attempt_id) do
    case Ecto.UUID.cast(attempt_id) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, :invalid_attempt_id}
    end
  end

  defp normalize_attempt_id(_attempt_id), do: {:error, :invalid_attempt_id}

  defp fetch_delivery(delivery_id) do
    case Domain.get_provisioning_delivery(delivery_id) do
      {:ok, %Delivery{} = delivery} -> {:ok, delivery}
      _ -> {:error, :not_found}
    end
  end

  defp list_deliveries(device_id, sha256) do
    Delivery
    |> Ash.Query.filter(device_id == ^device_id and artifact_sha256 == ^sha256)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(domain: Domain)
  end

  defp update_delivery(%Delivery{} = delivery, attrs) do
    case Domain.update_provisioning_delivery(delivery, attrs) do
      {:ok, updated} ->
        updated

      {:error, reason} ->
        Logger.error("failed to update provisioning delivery", delivery_id: delivery.id, error: inspect(reason))
        raise "provisioning delivery update failed: #{inspect(reason)}"
    end
  end

  defp normalize_submission(payload, base_url) when is_map(payload) do
    job_id = value(payload, "job_id", :job_id)
    state = normalize_job_state(value(payload, "state", :state))
    job_url = value(payload, "job_url", :job_url)

    cond do
      not bounded_payload?(payload) ->
        {:error, :job_payload_too_large}

      not valid_job_id?(job_id) ->
        {:error, :invalid_job_id}

      state not in @job_states ->
        {:error, :invalid_job_state}

      is_nil(job_url) ->
        {:ok, %{job_id: job_id, job_url: nil, state: state, payload: payload}}

      true ->
        case resolve_job_url(base_url, job_url, job_id) do
          {:ok, resolved} -> {:ok, %{job_id: job_id, job_url: resolved, state: state, payload: payload}}
          error -> error
        end
    end
  end

  defp normalize_submission(_payload, _base_url), do: {:error, :invalid_submission}

  defp normalize_job(payload, fallback_job_id) when is_map(payload) do
    state = normalize_job_state(value(payload, "state", :state))
    payload_job_id = value(payload, "id", :id)
    job_id = payload_job_id || fallback_job_id
    current_step = value(payload, "current_step", :current_step)
    result = value(payload, "result", :result)
    error = value(payload, "error", :error)
    rollback_status = value(payload, "rollback_status", :rollback_status)
    events = value(payload, "events", :events)

    if bounded_payload?(payload) and valid_job_id?(job_id) and
         (is_nil(payload_job_id) or payload_job_id == fallback_job_id) and state in @job_states and
         optional_string?(current_step) and optional_map?(result) and optional_string?(error) and
         optional_string?(rollback_status) and optional_list?(events) do
      {:ok,
       %{
         job_id: job_id,
         state: state,
         payload: payload,
         job_state: state,
         current_step: normalize_optional_string(current_step),
         result: result || %{},
         error: normalize_optional_string(error),
         rollback_status: normalize_optional_string(rollback_status)
       }}
    else
      {:error, :invalid_job_payload}
    end
  end

  defp normalize_job(_payload, _fallback_job_id), do: {:error, :invalid_job_payload}

  defp job_attributes(job) do
    %{
      state: delivery_state(job.state),
      job_id: job.job_id,
      job_state: job.job_state,
      current_step: job.current_step,
      job_payload: job.payload,
      result: job.result,
      error: job.error,
      rollback_status: job.rollback_status
    }
  end

  defp submission_error(payload), do: value(payload, "error", :error) || "AtomixOS reported a failed submission"
  defp job_error(job), do: job.error || "AtomixOS reported a failed provisioning job"

  defp resolve_job_url(base_url, job_url, job_id) when is_binary(job_url) do
    uri = URI.parse(job_url)
    expected_path = "/api/jobs/#{job_id}"

    cond do
      uri.scheme || uri.host || uri.userinfo || uri.query || uri.fragment -> {:error, :invalid_job_url}
      uri.path != expected_path -> {:error, :invalid_job_url}
      true -> {:ok, URI.merge(String.trim_trailing(base_url, "/") <> "/", job_url) |> to_string()}
    end
  end

  defp resolve_job_url(_base_url, _job_url, _job_id), do: {:error, :invalid_job_url}

  defp delivery_state("submitted"), do: :submitted
  defp delivery_state("running"), do: :running
  defp delivery_state("succeeded"), do: :succeeded
  defp delivery_state("failed"), do: :failed

  defp normalize_job_state(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_job_state(value) when is_binary(value), do: value
  defp normalize_job_state(_value), do: nil

  defp valid_job_id?(value) when is_binary(value) do
    byte_size(value) in 1..128 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value)
  end

  defp valid_job_id?(_value), do: false

  defp optional_string?(nil), do: true
  defp optional_string?(value), do: is_binary(value)

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value), do: truncate(value)

  defp optional_map?(nil), do: true
  defp optional_map?(value), do: is_map(value)

  defp optional_list?(nil), do: true
  defp optional_list?(value), do: is_list(value)

  defp bounded_payload?(payload) when is_map(payload) do
    case Jason.encode(payload) do
      {:ok, encoded} -> byte_size(encoded) <= @max_job_payload_size
      {:error, _reason} -> false
    end
  end

  defp bounded_payload?(_payload), do: false

  defp value(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp join_url(base_url, path), do: String.trim_trailing(base_url, "/") <> path

  defp default_submit_fun(opts) do
    fn url, bytes, filename ->
      HTTPClient.submit(url, bytes, filename, request_timeout_ms: request_timeout(opts))
    end
  end

  defp default_get_job_fun(opts) do
    fn url, request_opts ->
      HTTPClient.get_job(url, Keyword.put(request_opts, :request_timeout_ms, request_timeout(opts)))
    end
  end

  defp request_timeout(opts) do
    opts
    |> Keyword.get(:request_timeout_ms, @default_request_timeout_ms)
    |> max(1)
    |> min(@default_request_timeout_ms)
  end

  defp poll_timeout(opts) do
    opts
    |> Keyword.get(:poll_timeout_ms, @default_poll_timeout_ms)
    |> max(0)
    |> min(@default_poll_timeout_ms)
  end

  defp sleep_fun(opts), do: Keyword.get(opts, :sleep_fun, &Process.sleep/1)

  defp poll_delay(opts) do
    opts
    |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
    |> max(0)
    |> min(10_000)
  end

  defp retry_delay(attempt, opts) do
    backoff =
      opts
      |> Keyword.get(:retry_backoff_ms, @default_retry_backoff_ms)
      |> max(0)
      |> min(10_000)

    backoff * (attempt + 1)
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp truncate(message) when is_binary(message), do: String.slice(message, 0, 2_000)
  defp truncate(message), do: truncate(inspect(message))

  defp delivery_attributes(%Delivery{} = delivery) do
    %{
      delivery_id: delivery.id,
      device_id: delivery.device_id,
      attempt_id: delivery.attempt_id,
      artifact_sha256: delivery.artifact_sha256,
      state: delivery.state,
      job_id: delivery.job_id,
      error: delivery.error
    }
  end
end
