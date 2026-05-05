defmodule Nixstasis.Devices do
  @moduledoc """
  The Devices context.
  """

  use GenServer

  require Ash.Query

  import Ecto.Query, only: [from: 2]

  alias Ash.Error.Changes.InvalidAttribute
  alias Ash.Error.Invalid
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.PendingCommand
  alias Nixstasis.Devices.SchemaValidator
  alias Nixstasis.Domain
  alias Nixstasis.Repo

  @remote_access_leases_name __MODULE__.RemoteAccessLeases
  @remote_access_lease_ttl_ms 60 * 60 * 1000

  @impl true
  def init(:remote_access_leases) do
    {:ok, %{leases: %{}, device_refs: %{}}}
  end

  @impl true
  def handle_call({:open_remote_access_lease, device_id, owner, ttl_ms}, _from, state) do
    lease_ref = Ecto.UUID.generate()
    timer = Process.send_after(self(), {:remote_access_lease_expired, lease_ref}, ttl_ms)
    monitor = monitor_remote_access_owner(owner)

    lease = %{device_id: device_id, owner: owner, timer: timer, monitor: monitor}

    state = put_remote_access_lease(state, lease_ref, lease)
    {:reply, lease_ref, state}
  end

  def handle_call({:close_remote_access_lease, lease_ref}, _from, state) do
    {reply, state} = pop_remote_access_lease(state, lease_ref)
    {:reply, reply, state}
  end

  def handle_call({:close_remote_access_leases_for, owner}, _from, state) do
    lease_refs =
      state.leases
      |> Enum.filter(fn {_lease_ref, lease} -> lease.owner == owner end)
      |> Enum.map(fn {lease_ref, _lease} -> lease_ref end)

    {replies, state} =
      Enum.reduce(lease_refs, {[], state}, fn lease_ref, {replies, state} ->
        case pop_remote_access_lease(state, lease_ref) do
          {{:ok, device_id, _owner, clear_device?}, state} -> {[{device_id, clear_device?} | replies], state}
          {:ok, state} -> {replies, state}
        end
      end)

    {:reply, replies, state}
  end

  def handle_call({:remote_access_lease_active?, lease_ref}, _from, state) do
    {:reply, Map.has_key?(state.leases, lease_ref), state}
  end

  def handle_call(:sync_remote_access_leases, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:remote_access_lease_expired, lease_ref}, state) do
    case pop_remote_access_lease(state, lease_ref) do
      {{:ok, device_id, owner, clear_device?}, state} ->
        send(owner, {:remote_access_lease_expired, lease_ref})

        if clear_device? do
          clear_remote_access_device(device_id)
        end

        {:noreply, state}

      {:ok, state} ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case find_remote_access_lease_by_monitor(state, monitor) do
      {lease_ref, %{device_id: device_id}} -> handle_remote_access_owner_down(state, lease_ref, device_id)
      nil -> {:noreply, state}
    end
  end

  defp handle_remote_access_owner_down(state, lease_ref, device_id) do
    case pop_remote_access_lease(state, lease_ref) do
      {{:ok, ^device_id, _owner, clear_device?}, state} ->
        if clear_device?, do: clear_remote_access_device(device_id)
        {:noreply, state}

      {:ok, state} ->
        {:noreply, state}
    end
  end

  @default_pending_command_limit 50

  @doc """
  Counts all devices.
  """
  def count_all do
    Device
    |> Ash.count!(domain: Domain)
  end

  @doc """
  Counts devices by online/offline status.
  Online is defined as seen within the last 5 minutes.
  """
  def count_by_status(:online) do
    threshold = DateTime.add(DateTime.utc_now(), -5, :minute)

    Device
    |> Ash.Query.filter(last_seen_at >= ^threshold)
    |> Ash.count!(domain: Domain)
  end

  def count_by_status(:offline) do
    threshold = DateTime.add(DateTime.utc_now(), -5, :minute)

    Device
    |> Ash.Query.filter(last_seen_at < ^threshold or is_nil(last_seen_at))
    |> Ash.count!(domain: Domain)
  end

  @doc """
  Counts devices pending approval.
  """
  def count_pending_approvals do
    Device
    |> Ash.Query.filter(approval_status == :pending)
    |> Ash.count!(domain: Domain)
  end

  @doc """
  Registers a device.
  """
  def register_device(attrs) do
    safe_attrs =
      if is_map(attrs) do
        attrs
        |> Map.delete("approval_status")
        |> Map.delete(:approval_status)
        |> Map.delete("schema_definition")
        |> Map.delete(:schema_definition)
      else
        attrs
      end

    schema_def =
      if is_map(attrs) do
        attrs["schema_definition"] || attrs[:schema_definition] || %{}
      else
        %{}
      end

    case SchemaValidator.validate(schema_def) do
      :ok ->
        case Domain.register_device(safe_attrs) do
          {:ok, device} = result ->
            broadcast_device(:device_registered, device)
            result

          result ->
            result
        end

      {:error, msg} ->
        {:error,
         Ash.Error.Invalid.exception(
           errors: [
             Ash.Error.Changes.InvalidAttribute.exception(field: :schema_definition, message: msg)
           ]
         )}
    end
  end

  def update_last_seen(%Device{} = device) do
    case Domain.update_device(device, %{last_seen_at: DateTime.utc_now()}) do
      {:ok, device} = result ->
        broadcast_device(:device_last_seen_updated, device)
        result

      result ->
        result
    end
  end

  @doc """
  Lists pending devices.
  """
  def list_pending_devices do
    Device
    |> Ash.Query.filter(approval_status == :pending)
    |> Ash.read!(domain: Domain)
  end

  @doc """
  Approves a device.
  """
  def approve_device(%Device{} = device) do
    with {:ok, approved} <- Domain.update_device(device, %{approval_status: :approved}),
         {:ok, updated} <- update_device_token_hash(approved.id, nil) do
      broadcast_device(:device_approval_status_changed, updated)
      {:ok, updated}
    end
  end

  def issue_device_token(%Device{approval_status: :approved} = device) do
    token = generate_device_token()

    case update_device_token_hash(device.id, hash_device_token(token)) do
      {:ok, updated_device} -> {:ok, updated_device, token}
      {:error, reason} -> {:error, reason}
    end
  end

  def issue_device_token(%Device{}), do: {:error, :device_not_approved}

  def authenticate_device(%Device{approval_status: :approved, api_token_hash: hash}, token)
      when is_binary(hash) and is_binary(token) do
    candidate = hash_device_token(token)

    if Plug.Crypto.secure_compare(hash, candidate) do
      :ok
    else
      {:error, :invalid_token}
    end
  end

  def authenticate_device(%Device{approval_status: status}, _token) when status != :approved,
    do: {:error, :device_not_approved}

  def authenticate_device(%Device{approval_status: :approved, api_token_hash: nil}, _token),
    do: {:error, :missing_token}

  def authenticate_device(%Device{}, _token), do: {:error, :missing_token}

  @doc """
  Returns the list of devices.

  ## Options
    * `:sort_by` - The field to sort by. Defaults to `:inserted_at`.
    * `:sort_order` - The sort order, `:asc` or `:desc`. Defaults to `:desc`.
    * `:filter` - A map of filters (e.g., `%{approval_status: :pending}`).
    * `:search` - A search string for mac_address or account_number.
  """
  def list_devices(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, :inserted_at)
    sort_order = Keyword.get(opts, :sort_order, :desc)
    filter = Keyword.get(opts, :filter, %{})
    search = Keyword.get(opts, :search)

    Device
    |> filter_by_approval_status(filter_value(filter, :approval_status))
    |> filter_by_connectivity_status(filter_value(filter, :connectivity_status))
    |> filter_by_product(filter_value(filter, :product))
    |> filter_by_account_number(filter_value(filter, :account_number))
    |> search_devices(search)
    |> Ash.Query.sort([{sort_by, sort_order}])
    |> Ash.read!(domain: Domain)
  end

  @doc """
  Check if a device is requesting remote access by MAC address.
  """
  def requesting_remote_access?(mac) do
    case Domain.get_device_by_mac(mac) do
      {:ok, nil} -> false
      {:ok, device} -> device.remote_access_requested
      {:error, _} -> false
    end
  end

  @doc """
  Normalizes approval status filters to known status atoms.
  """
  def normalize_approval_status_filter(status) when status in [:pending, :approved, :rejected], do: status

  def normalize_approval_status_filter(status) when is_binary(status) do
    case String.trim(status) do
      "pending" -> :pending
      "approved" -> :approved
      "rejected" -> :rejected
      _ -> nil
    end
  end

  def normalize_approval_status_filter(_), do: nil

  @doc """
  Normalizes connectivity filters to `:online` or `:offline`.
  """
  def normalize_connectivity_status_filter(status) when status in [:online, :offline], do: status

  def normalize_connectivity_status_filter(status) when is_binary(status) do
    case String.trim(status) do
      "online" -> :online
      "offline" -> :offline
      _ -> nil
    end
  end

  def normalize_connectivity_status_filter(_), do: nil

  defp filter_by_approval_status(query, nil), do: query

  defp filter_by_approval_status(query, status) do
    case normalize_approval_status_filter(status) do
      nil -> query
      normalized_status -> Ash.Query.filter(query, approval_status == ^normalized_status)
    end
  end

  defp filter_by_connectivity_status(query, nil), do: query

  defp filter_by_connectivity_status(query, status) do
    threshold = DateTime.add(DateTime.utc_now(), -5, :minute)

    case normalize_connectivity_status_filter(status) do
      nil -> query
      :online -> Ash.Query.filter(query, last_seen_at >= ^threshold)
      :offline -> Ash.Query.filter(query, last_seen_at < ^threshold or is_nil(last_seen_at))
    end
  end

  defp filter_by_product(query, nil), do: query

  defp filter_by_product(query, product) do
    case Device.normalize_filter_value(product) do
      nil -> query
      value -> Ash.Query.filter(query, product_name == ^value)
    end
  end

  defp filter_by_account_number(query, nil), do: query

  defp filter_by_account_number(query, account_number) do
    case Device.normalize_filter_value(account_number) do
      nil -> query
      value -> Ash.Query.filter(query, account_number == ^value)
    end
  end

  defp search_devices(query, nil), do: query

  defp search_devices(query, term) do
    term = String.trim(to_string(term))

    if term == "" do
      query
    else
      Ash.Query.filter(query, contains(mac_address, ^term) or contains(account_number, ^term))
    end
  end

  @doc """
  Approves multiple devices by ID.
  """
  def approve_devices(ids) when is_list(ids) do
    result =
      Device
      |> Ash.Query.filter(id in ^ids)
      |> Ash.bulk_update!(:update, %{approval_status: :approved}, domain: Domain, strategy: :stream)

    clear_device_token_hashes(ids)

    ids
    |> list_devices_by_ids()
    |> Enum.each(&broadcast_device(:device_approval_status_changed, &1))

    result
  end

  @doc """
  Rejects multiple devices by ID.
  """
  def reject_devices(ids) when is_list(ids) do
    result =
      Device
      |> Ash.Query.filter(id in ^ids)
      |> Ash.bulk_update!(:update, %{approval_status: :rejected}, domain: Domain, strategy: :stream)

    ids
    |> list_devices_by_ids()
    |> Enum.each(&broadcast_device(:device_approval_status_changed, &1))

    result
  end

  @doc """
  Sets the remote_access_requested flag.
  """
  def set_remote_access(%Device{} = device, requested?) do
    case Domain.update_device(device, %{remote_access_requested: requested?}) do
      {:ok, device} = result ->
        broadcast_device(:device_remote_access_changed, device)
        result

      result ->
        result
    end
  end

  @doc """
  Opens a leased remote-access session and marks the device as requesting access.
  """
  def open_remote_access_lease(%Device{} = device, opts \\ []) do
    ensure_remote_access_leases_manager!()
    owner = Keyword.get(opts, :owner, self())
    ttl_ms = Keyword.get(opts, :ttl_ms, @remote_access_lease_ttl_ms)

    with {:ok, updated} <- set_remote_access(device, true) do
      lease_ref = GenServer.call(@remote_access_leases_name, {:open_remote_access_lease, device.id, owner, ttl_ms})
      {:ok, updated, lease_ref}
    end
  end

  @doc """
  Closes a remote-access lease and clears access when no leases remain.
  """
  def close_remote_access_lease(nil), do: :ok

  def close_remote_access_lease(lease_ref) when is_binary(lease_ref) do
    ensure_remote_access_leases_manager!()

    case GenServer.call(@remote_access_leases_name, {:close_remote_access_lease, lease_ref}) do
      {:ok, device_id, _owner, true} -> clear_remote_access_device(device_id)
      {:ok, _device_id, _owner, false} -> :ok
      :ok -> :ok
    end
  end

  def close_remote_access_lease(_lease_ref), do: :ok

  @doc """
  Closes all leases owned by a process.
  """
  def close_remote_access_leases_for(owner) when is_pid(owner) do
    ensure_remote_access_leases_manager!()

    @remote_access_leases_name
    |> GenServer.call({:close_remote_access_leases_for, owner})
    |> Enum.each(fn {device_id, clear_device?} ->
      if clear_device? do
        clear_remote_access_device(device_id)
      end
    end)

    :ok
  end

  def close_remote_access_leases_for(_owner), do: :ok

  @doc """
  Returns true when a lease ref is active.
  """
  def remote_access_lease_active?(lease_ref) when is_binary(lease_ref) do
    ensure_remote_access_leases_manager!()
    GenServer.call(@remote_access_leases_name, {:remote_access_lease_active?, lease_ref})
  end

  def remote_access_lease_active?(_lease_ref), do: false

  @doc false
  def sync_remote_access_leases do
    ensure_remote_access_leases_manager!()
    GenServer.call(@remote_access_leases_name, :sync_remote_access_leases)
  end

  @doc """
  Expires a remote-access lease. Intended for lease timeout messages.
  """
  def expire_remote_access_lease(lease_ref) when is_binary(lease_ref) do
    ensure_remote_access_leases_manager!()

    case GenServer.call(@remote_access_leases_name, {:close_remote_access_lease, lease_ref}) do
      {:ok, device_id, _owner, true} -> clear_remote_access_device(device_id)
      {:ok, _device_id, _owner, false} -> :ok
      :ok -> :ok
    end
  end

  def expire_remote_access_lease(_lease_ref), do: :ok

  @doc """
  Gets a single device.

  Raises `Ash.Error.Invalid` if the Device does not exist.
  """
  def get_device!(id), do: Domain.get_device!(id)

  def get_device(id), do: Domain.get_device(id)

  @doc """
  Creates a device.
  """
  def create_device(attrs \\ %{}) do
    case Domain.create_device(attrs) do
      {:ok, device} = result ->
        broadcast_device(:device_created, device)
        result

      result ->
        result
    end
  end

  @doc """
  Updates a device.
  """
  def update_device(%Device{} = device, attrs) do
    case Domain.update_device(device, attrs) do
      {:ok, device} = result ->
        broadcast_update_for_attrs(device, attrs)
        result

      result ->
        result
    end
  end

  @doc """
  Deletes a device.
  """
  def delete_device(%Device{} = device) do
    Domain.destroy_device(device)
  end

  @doc """
  Returns an AshPhoenix form for tracking device changes.
  """
  def change_device(device, attrs \\ %{})

  def change_device(%Device{id: nil} = _device, attrs) do
    Device
    |> AshPhoenix.Form.for_create(:create, domain: Domain, params: attrs)
  end

  def change_device(%Device{} = device, attrs) do
    device
    |> AshPhoenix.Form.for_update(:update, domain: Domain, params: attrs)
  end

  def queue_command(%Device{} = device, payload) do
    Domain.create_pending_command(%{
      device_id: device.id,
      command_payload: payload,
      status: :queued,
      queued_at: DateTime.utc_now()
    })
  end

  def pop_pending_commands(%Device{} = device) do
    Repo.transaction(fn ->
      ids = claim_pending_command_ids(device.id)

      if ids == [] do
        []
      else
        PendingCommand
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(domain: Domain)
      end
    end)
    |> case do
      {:ok, commands} -> commands
      _ -> []
    end
  end

  defp claim_pending_command_ids(device_id) do
    now = DateTime.utc_now()

    %{rows: rows} =
      Repo.query!(
        """
        UPDATE pending_commands
        SET status = 'delivered', delivered_at = $2, updated_at = $2
        WHERE id IN (
          SELECT id
          FROM pending_commands
          WHERE device_id = $1::uuid AND status = 'queued'
          ORDER BY queued_at ASC, id ASC
          LIMIT $3
          FOR UPDATE SKIP LOCKED
        )
        RETURNING id
        """,
        [Ecto.UUID.dump!(device_id), now, @default_pending_command_limit]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  def acknowledge_command_results(%Device{} = device, results) when is_list(results) do
    now = DateTime.utc_now()
    acknowledged_count = Enum.reduce(results, 0, &acknowledge_command_result(device, &1, &2, now))

    {:ok, acknowledged_count}
  end

  def acknowledge_command_results(_device, _results), do: {:error, "results must be a list"}

  defp acknowledge_command_result(device, result, count, now) do
    command_id = Map.get(result, "command_id") || Map.get(result, :command_id)

    case fetch_pending_command(device.id, command_id) do
      nil -> count
      command -> update_acknowledged_command(command, result, count, now)
    end
  end

  defp update_acknowledged_command(command, result, count, now) do
    status = command_result_status(result)
    updated_payload = merge_command_result(command.command_payload, result, now, status)

    case Domain.update_pending_command(command, %{status: :acked, command_payload: updated_payload}) do
      {:ok, _} -> count + 1
      {:error, _reason} -> count
    end
  end

  def get_command_payload(%Device{} = device, ref) when is_binary(ref) do
    with {:ok, command_payload} <- find_payload_by_ref(device.id, ref),
         {:ok, payload} <- extract_command_payload(command_payload) do
      {:ok, payload}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_command_payload(_device, _ref), do: {:error, :not_found}

  @doc """
  Checks if a device is online.
  Online is defined as seen within the last 5 minutes.
  """
  def online?(%Device{} = device) do
    case device.last_seen_at do
      nil -> false
      time -> DateTime.diff(DateTime.utc_now(), time, :minute) < 5
    end
  end

  defp ensure_remote_access_leases_manager! do
    case Process.whereis(@remote_access_leases_name) do
      nil ->
        case GenServer.start(__MODULE__, :remote_access_leases, name: @remote_access_leases_name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp put_remote_access_lease(state, lease_ref, lease) do
    device_refs = Map.update(state.device_refs, lease.device_id, MapSet.new([lease_ref]), &MapSet.put(&1, lease_ref))
    leases = Map.put(state.leases, lease_ref, lease)
    %{state | leases: leases, device_refs: device_refs}
  end

  defp pop_remote_access_lease(state, lease_ref) do
    case Map.pop(state.leases, lease_ref) do
      {nil, _leases} ->
        {:ok, state}

      {%{device_id: device_id, owner: owner, timer: timer, monitor: monitor}, leases} ->
        Process.cancel_timer(timer)
        demonitor_remote_access_owner(monitor)

        {device_refs, clear_device?} = delete_remote_access_device_ref(state.device_refs, device_id, lease_ref)

        {{:ok, device_id, owner, clear_device?}, %{state | leases: leases, device_refs: device_refs}}
    end
  end

  defp delete_remote_access_device_ref(device_refs, device_id, lease_ref) do
    refs =
      device_refs
      |> Map.get(device_id, MapSet.new())
      |> MapSet.delete(lease_ref)

    if MapSet.size(refs) == 0 do
      {Map.delete(device_refs, device_id), true}
    else
      {Map.put(device_refs, device_id, refs), false}
    end
  end

  defp find_remote_access_lease_by_monitor(state, monitor) do
    Enum.find(state.leases, fn {_lease_ref, lease} -> lease.monitor == monitor end)
  end

  defp monitor_remote_access_owner(owner) when is_pid(owner), do: Process.monitor(owner)
  defp monitor_remote_access_owner(_owner), do: nil

  defp demonitor_remote_access_owner(nil), do: false
  defp demonitor_remote_access_owner(monitor), do: Process.demonitor(monitor, [:flush])

  defp clear_remote_access_device(device_id) do
    device_id
    |> get_device!()
    |> set_remote_access(false)

    :ok
  rescue
    error ->
      Logger.warning("Failed to clear remote access flag for #{device_id}: #{Exception.message(error)}")
      :ok
  catch
    :exit, {{:shutdown, "owner " <> _}, {DBConnection.Holder, :checkout, _}} ->
      :ok
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  defp filter_value(filter, key) when is_map(filter) do
    Map.get(filter, key) || Map.get(filter, to_string(key))
  end

  defp filter_value(_filter, _key), do: nil

  defp list_devices_by_ids([]), do: []

  defp list_devices_by_ids(ids) do
    Device
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(domain: Domain)
  end

  defp broadcast_update_for_attrs(%Device{} = device, attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :approval_status) or Map.has_key?(attrs, "approval_status") ->
        broadcast_device(:device_approval_status_changed, device)

      Map.has_key?(attrs, :last_seen_at) or Map.has_key?(attrs, "last_seen_at") ->
        broadcast_device(:device_last_seen_updated, device)

      Map.has_key?(attrs, :remote_access_requested) or Map.has_key?(attrs, "remote_access_requested") ->
        broadcast_device(:device_remote_access_changed, device)

      true ->
        :ok
    end
  end

  defp broadcast_update_for_attrs(_device, _attrs), do: :ok

  defp broadcast_device(event, %Device{} = device) do
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, "devices", {event, device_broadcast_payload(device)})
  end

  defp device_broadcast_payload(%Device{} = device) do
    %{
      id: device.id,
      approval_status: device.approval_status,
      last_seen_at: device.last_seen_at,
      remote_access_requested: device.remote_access_requested
    }
  end

  defp fetch_pending_command(_device_id, command_id) when is_nil(command_id) or command_id == "", do: nil

  defp fetch_pending_command(device_id, command_id) do
    PendingCommand
    |> Ash.Query.filter(device_id == ^device_id and id == ^command_id)
    |> Ash.read_one!(domain: Domain)
  rescue
    _ -> nil
  end

  defp command_result_status(result) do
    status = Map.get(result, "status") || Map.get(result, :status)
    if status in ["OK", :OK], do: "ok", else: "failed"
  end

  defp merge_command_result(command_payload, result, now, status) do
    payload =
      if is_map(command_payload) do
        command_payload
      else
        %{}
      end

    payload
    |> Map.put("result", result)
    |> Map.put("result_status", status)
    |> Map.put("result_received_at", now)
  end

  defp find_payload_by_ref(device_id, ref) do
    payload_map =
      Repo.one(
        from command in PendingCommand,
          where: command.device_id == ^device_id,
          where: fragment("?->>? = ?", command.command_payload, "payload_ref", ^ref),
          order_by: [desc: command.inserted_at],
          limit: 1,
          select: command.command_payload
      )

    case payload_map do
      nil -> {:error, :not_found}
      payload when is_map(payload) -> {:ok, payload}
      _ -> {:error, :not_found}
    end
  end

  defp generate_device_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp update_device_token_hash(device_id, token_hash) do
    {count, _} =
      Repo.update_all(
        from(device in Device, where: device.id == ^device_id),
        set: [api_token_hash: token_hash]
      )

    if count == 1 do
      get_device(device_id)
    else
      {:error, :not_found}
    end
  end

  defp clear_device_token_hashes([]), do: :ok

  defp clear_device_token_hashes(ids) do
    Repo.update_all(
      from(device in Device, where: device.id in ^ids),
      set: [api_token_hash: nil]
    )

    :ok
  end

  defp hash_device_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  defp extract_command_payload(payload) do
    command_payload =
      payload["payload"] || payload[:payload] ||
        %{
          "content_type" => payload["content_type"] || payload[:content_type],
          "name" => payload["name"] || payload[:name],
          "data" => payload["data"] || payload[:data]
        }

    case command_payload do
      %{} = map -> {:ok, map}
      _ -> {:error, :not_found}
    end
  end
end
