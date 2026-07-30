defmodule Nixstasis.Devices do
  @moduledoc """
  The Devices context.
  """

  use GenServer

  require Ash.Query
  require Logger
  import Ecto.Query, only: [from: 2]

  alias Ash.Error.Changes.InvalidAttribute
  alias Ash.Error.Invalid
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.DeviceGroup
  alias Nixstasis.Devices.DeviceGroupMembership
  alias Nixstasis.Devices.GroupAudit
  alias Nixstasis.Devices.GroupAuthorization
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

  def start_link(:remote_access_leases) do
    GenServer.start_link(__MODULE__, :remote_access_leases, name: @remote_access_leases_name)
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
  def register_public_device(attrs) do
    attrs
    |> normalize_registration_attrs()
    |> validate_registration_attrs(:public)
    |> persist_registered_device()
  end

  def register_device(attrs) do
    attrs
    |> normalize_registration_attrs()
    |> validate_registration_attrs(:internal)
    |> persist_registered_device()
  end

  defp validate_registration_attrs({:error, _} = error, _scope), do: error

  defp validate_registration_attrs({safe_attrs, schema_def}, scope) do
    case validate_registration_schema(schema_def, scope) do
      :ok -> {:ok, safe_attrs}
      {:error, msg} -> {:error, invalid_registration_schema_error(msg)}
    end
  end

  defp validate_registration_schema(schema_def, :internal) when schema_def in [nil, %{}], do: :ok

  defp validate_registration_schema(schema_def, :public) when schema_def in [nil, %{}],
    do: {:error, "schema must include product"}

  defp validate_registration_schema(schema_def, scope) when scope in [:internal, :public],
    do: SchemaValidator.validate_registration(schema_def, scope)

  defp normalize_registration_attrs(attrs) when is_map(attrs) do
    safe_attrs =
      attrs
      |> put_schema_definition()
      |> put_ipv4_address()
      |> Map.delete("approval_status")
      |> Map.delete(:approval_status)
      |> Map.delete("schema_definition")
      |> Map.delete(:schema_definition)

    {safe_attrs, registration_schema(attrs)}
  end

  defp normalize_registration_attrs(_attrs), do: {%{}, nil}

  defp registration_schema(attrs) when is_map(attrs) do
    attrs["schema_definition"] || attrs[:schema_definition] || attrs["schema"] || attrs[:schema]
  end

  defp registration_schema(_attrs), do: nil

  defp persist_registered_device({:ok, safe_attrs}) do
    case Domain.register_device(safe_attrs) do
      {:ok, device} = result ->
        broadcast_device(:device_registered, device)
        result

      result ->
        result
    end
  end

  defp persist_registered_device({:error, _} = error), do: error

  defp invalid_registration_schema_error(message) do
    Invalid.exception(errors: [InvalidAttribute.exception(field: :schema_definition, message: message)])
  end

  defp put_schema_definition(attrs) do
    schema_def = attrs["schema_definition"] || attrs[:schema_definition]

    if is_map(schema_def) and map_size(schema_def) > 0 do
      Map.put(attrs, "schema", schema_def)
    else
      attrs
    end
  end

  defp put_ipv4_address(attrs) do
    direct_ipv4 = attrs["ipv4_address"] || attrs[:ipv4_address]
    metadata = attrs["metadata"] || attrs[:metadata] || %{}

    metadata_ipv4 =
      if is_map(metadata), do: metadata["ip_address"] || metadata[:ip_address], else: nil

    case Device.normalize_filter_value(direct_ipv4 || metadata_ipv4) do
      nil -> attrs
      ipv4_address -> Map.put(attrs, "ipv4_address", ipv4_address)
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
    authorized_device_ids = Keyword.get(opts, :authorized_device_ids)

    Device
    |> filter_by_authorized_device_ids(authorized_device_ids)
    |> filter_by_group(filter_value(filter, :group_id))
    |> filter_by_approval_status(filter_value(filter, :approval_status))
    |> filter_by_connectivity_status(filter_value(filter, :connectivity_status))
    |> filter_by_product(filter_value(filter, :product))
    |> filter_by_account_number(filter_value(filter, :account_number))
    |> filter_by_ipv4_address(filter_value(filter, :ipv4_address))
    |> search_devices(search)
    |> Ash.Query.sort([{sort_by, sort_order}])
    |> Ash.read!(domain: Domain)
  end

  @doc "Returns active groups visible within the trusted device scope."
  def list_device_groups(%GroupAuthorization{} = authorization, opts \\ []) do
    include_archived? =
      Keyword.get(opts, :include_archived?, false) and global_group_visibility?(authorization)

    if global_group_visibility?(authorization) do
      list_global_group_rows(include_archived?)
    else
      list_scoped_group_rows(authorization.authorized_device_ids, include_archived?)
    end
  end

  @doc "Returns visible device IDs belonging to a group."
  def list_group_memberships(group_id, %GroupAuthorization{} = authorization) do
    case Ecto.UUID.cast(group_id) do
      {:ok, group_id} ->
        group_id
        |> membership_device_ids(authorization.authorized_device_ids)
        |> Enum.sort()

      :error ->
        []
    end
  end

  @doc "Creates group metadata for an unscoped device manager."
  def create_device_group(attrs, %GroupAuthorization{} = authorization) when is_map(attrs) do
    result =
      with :ok <- authorize_group_metadata(authorization) do
        run_group_transaction(fn -> Domain.create_device_group(metadata_attrs(attrs), return_notifications?: true) end)
      end

    publish_metadata_result(result, :create, authorization)
  end

  @doc "Updates group metadata for an unscoped device manager."
  def update_device_group(group_id, attrs, %GroupAuthorization{} = authorization) when is_map(attrs) do
    group_id
    |> mutate_group(authorization, fn group ->
      Domain.update_device_group(group, metadata_attrs(attrs), return_notifications?: true)
    end)
    |> publish_metadata_result(:update, authorization)
  end

  @doc "Archives a group while preserving memberships."
  def archive_device_group(group_id, %GroupAuthorization{} = authorization) do
    group_id
    |> mutate_group(authorization, fn group ->
      if group.archived_at do
        {:error, :group_archived}
      else
        Domain.update_device_group(group, %{archived_at: DateTime.utc_now()}, return_notifications?: true)
      end
    end)
    |> publish_metadata_result(:archive, authorization)
  end

  @doc "Restores an archived group."
  def restore_device_group(group_id, %GroupAuthorization{} = authorization) do
    group_id
    |> mutate_group(authorization, fn group ->
      if group.archived_at do
        Domain.update_device_group(group, %{archived_at: nil}, return_notifications?: true)
      else
        {:error, :group_not_archived}
      end
    end)
    |> publish_metadata_result(:restore, authorization)
  end

  @doc "Permanently deletes an archived empty group."
  def permanently_delete_device_group(group_id, %GroupAuthorization{} = authorization) do
    group_id
    |> mutate_group(authorization, &delete_archived_group/1)
    |> publish_delete_result(group_id, authorization)
  end

  @doc "Adds authorized devices to an active group as one transaction."
  def add_devices_to_group(group_id, device_ids, %GroupAuthorization{} = authorization) do
    :add
    |> mutate_group_memberships(group_id, device_ids, authorization)
    |> publish_membership_result(:membership_add, authorization)
  end

  @doc "Removes authorized devices from an active group as one transaction."
  def remove_devices_from_group(group_id, device_ids, %GroupAuthorization{} = authorization) do
    :remove
    |> mutate_group_memberships(group_id, device_ids, authorization)
    |> publish_membership_result(:membership_remove, authorization)
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

  defp filter_by_authorized_device_ids(query, nil), do: query

  defp filter_by_authorized_device_ids(query, %MapSet{} = ids) do
    Ash.Query.filter(query, id in ^MapSet.to_list(ids))
  end

  defp filter_by_authorized_device_ids(query, ids) when is_list(ids) do
    Ash.Query.filter(query, id in ^ids)
  end

  defp filter_by_authorized_device_ids(query, _ids), do: Ash.Query.filter(query, false)

  defp filter_by_group(query, nil), do: query

  defp filter_by_group(query, group_id) do
    case Ecto.UUID.cast(group_id) do
      {:ok, group_id} ->
        Ash.Query.filter(
          query,
          exists(device_group_memberships, group_id == ^group_id and is_nil(group.archived_at))
        )

      :error ->
        Ash.Query.filter(query, false)
    end
  end

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

  defp filter_by_ipv4_address(query, nil), do: query

  defp filter_by_ipv4_address(query, ipv4_address) do
    case Device.normalize_filter_value(ipv4_address) do
      nil -> query
      value -> Ash.Query.filter(query, ipv4_address == ^value)
    end
  end

  defp search_devices(query, nil), do: query

  defp search_devices(query, term) do
    term = String.trim(to_string(term))

    if term == "" do
      query
    else
      Ash.Query.filter(
        query,
        contains(mac_address, ^term) or contains(account_number, ^term) or
          contains(ipv4_address, ^term)
      )
    end
  end

  @doc "Lists distinct schema references without materializing every device."
  def list_schema_references do
    from(d in "devices",
      where:
        not is_nil(d.product_name) and d.product_name != "" and
          fragment("? <> '{}'::jsonb", d.schema),
      distinct: true,
      select: %{
        schema_id: d.product_name,
        schema_version: fragment("COALESCE(NULLIF(?->>'version', ''), 'v1')", d.schema),
        product_name: d.product_name,
        readable: true
      },
      order_by: [
        asc: d.product_name,
        asc: fragment("COALESCE(NULLIF(?->>'version', ''), 'v1')", d.schema)
      ]
    )
    |> Repo.all()
  end

  @doc "Returns one schema map for a product/version pair."
  def get_schema_definition(schema_id, schema_version)
      when is_binary(schema_id) and is_binary(schema_version) do
    from(d in "devices",
      where: d.product_name == ^schema_id,
      where: fragment("COALESCE(NULLIF(?->>'version', ''), 'v1') = ?", d.schema, ^schema_version),
      where: fragment("? <> '{}'::jsonb", d.schema),
      select: d.schema,
      limit: 1
    )
    |> Repo.one()
  end

  def get_schema_definition(_, _), do: nil

  @doc """
  Approves multiple devices by ID.
  """
  def approve_devices([]), do: {:error, :no_devices_selected}

  def approve_devices(ids) when is_list(ids) do
    case Repo.transaction(fn ->
           pending_ids = pending_device_ids(ids)

           result =
             Device
             |> Ash.Query.filter(id in ^ids and approval_status == :pending)
             |> Ash.bulk_update!(:update, %{approval_status: :approved}, domain: Domain, strategy: :stream)

           clear_device_token_hashes(pending_ids)
           {result, list_devices_by_ids(ids)}
         end) do
      {:ok, {result, devices}} ->
        Enum.each(devices, &broadcast_device(:device_approval_status_changed, &1))
        result

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Rejects multiple devices by ID.
  """
  def reject_devices([]), do: {:error, :no_devices_selected}

  def reject_devices(ids) when is_list(ids) do
    case Repo.transaction(fn ->
           result =
             Device
             |> Ash.Query.filter(id in ^ids and approval_status == :pending)
             |> Ash.bulk_update!(:update, %{approval_status: :rejected}, domain: Domain, strategy: :stream)

           {result, list_devices_by_ids(ids)}
         end) do
      {:ok, {result, devices}} ->
        Enum.each(devices, &broadcast_device(:device_approval_status_changed, &1))
        result

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
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
    lease_ref = GenServer.call(@remote_access_leases_name, {:open_remote_access_lease, device.id, owner, ttl_ms})

    case set_remote_access(device, true) do
      {:ok, updated} ->
        {:ok, updated, lease_ref}

      {:error, _reason} = error ->
        close_remote_access_lease(lease_ref)
        error
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

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Deletes a device.
  """
  def delete_device(%Device{} = device) do
    case Domain.destroy_device(device) do
      :ok = result ->
        broadcast_device(:device_deleted, device)
        result

      result ->
        result
    end
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

  @command_policy_content_type "application/vnd.nixstasis.command-policy+json;version=1"
  @inline_command_policy_payload_limit 4096

  def queue_command(%Device{} = device, payload) do
    Domain.create_pending_command(%{
      device_id: device.id,
      command_payload: payload,
      status: :queued,
      queued_at: DateTime.utc_now()
    })
  end

  def queue_command_policy_assignment(%Nixstasis.CommandAllowlists.DevicePolicyAssignment{} = assignment) do
    with {:ok, device} <- Domain.get_device(assignment.device_id),
         payload <- command_policy_command_payload(assignment) do
      replace_queued_command_policy(device, payload)
    end
  end

  defp replace_queued_command_policy(device, payload) do
    Repo.transaction(fn -> create_replacement_command_policy(device, payload) end)
    |> case do
      {:ok, {command, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, command}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_replacement_command_policy(device, payload) do
    :ok = supersede_queued_command_policies(device.id)

    pending_command_attrs = %{
      device_id: device.id,
      command_payload: payload,
      status: :queued,
      queued_at: DateTime.utc_now()
    }

    PendingCommand
    |> Ash.Changeset.for_create(:create, pending_command_attrs)
    |> Ash.create(domain: Domain, return_notifications?: true)
    |> case do
      {:ok, command, notifications} -> {command, notifications}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def command_result_status(device_id, command_id) when is_binary(device_id) and is_binary(command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, command_id} -> pending_command_result_status(device_id, command_id)
      :error -> :pending
    end
  end

  def command_result_status(_device_id, _command_id), do: :pending

  def command_succeeded?(device_id, command_id) when is_binary(device_id) and is_binary(command_id) do
    command_result_status(device_id, command_id) == :ok
  end

  def command_succeeded?(_device_id, _command_id), do: false

  def command_payload_for_result(%Device{} = device, result) when is_map(result) do
    command_id = Map.get(result, "command_id") || Map.get(result, :command_id)

    case fetch_pending_command(device.id, command_id) do
      %{command_payload: %{} = payload} -> {:ok, payload}
      _ -> {:error, :not_found}
    end
  end

  def command_payload_for_result(_device, _result), do: {:error, :not_found}

  @doc """
  Queues a best-effort `ssh_revoke` command so the client can drop the in-memory
  authorization for the given terminal session. Returns `:ok` even when the
  device is no longer reachable or the queue insert fails; terminal cleanup
  must not block on a revoke that the client may never see.
  """
  def queue_terminal_revoke(%Device{} = device, session_ref)
      when is_binary(session_ref) and session_ref != "" do
    payload_data =
      Jason.encode!(%{session_ref: session_ref})

    case queue_command(device, %{
           "type" => "ssh_revoke",
           "payload" => %{
             "content_type" => "application/vnd.nixstasis.ssh-revoke+json;version=1",
             "name" => session_ref,
             "data" => payload_data
           }
         }) do
      {:ok, _command} ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to queue terminal revoke for device #{device.id}: #{inspect(reason)}")
        :ok
    end
  end

  def queue_terminal_revoke(_device, _session_ref), do: :ok

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
    unless Process.whereis(@remote_access_leases_name) do
      raise RuntimeError,
        message: "#{inspect(@remote_access_leases_name)} is not running; check supervision tree ordering"
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

    :exit, reason ->
      Logger.warning("Failed to clear remote access flag for #{device_id}: #{inspect(reason)}")
      :ok
  end

  defp global_group_visibility?(%GroupAuthorization{} = authorization) do
    authorization.can_manage_all_devices? and is_nil(authorization.authorized_device_ids)
  end

  defp list_global_group_rows(include_archived?) do
    from(group in "device_groups",
      left_join: membership in "device_group_memberships",
      on: membership.group_id == group.id,
      where: ^include_archived? or is_nil(group.archived_at),
      group_by: [group.id, group.name, group.name_key, group.description, group.archived_at],
      order_by: [asc: group.name, asc: group.id],
      select: %{
        group: %{
          id: type(group.id, Ecto.UUID),
          name: group.name,
          name_key: group.name_key,
          description: group.description,
          archived_at: group.archived_at
        },
        visible_device_count: count(membership.device_id, :distinct)
      }
    )
    |> Repo.all()
  end

  defp list_scoped_group_rows(%MapSet{} = ids, include_archived?) do
    list_scoped_group_rows(MapSet.to_list(ids), include_archived?)
  end

  defp list_scoped_group_rows([], _include_archived?), do: []

  defp list_scoped_group_rows(authorized_device_ids, include_archived?) do
    query =
      from(group in "device_groups",
        join: membership in "device_group_memberships",
        on: membership.group_id == group.id,
        where: ^include_archived? or is_nil(group.archived_at),
        group_by: [group.id, group.name, group.name_key, group.description, group.archived_at],
        order_by: [asc: group.name, asc: group.id],
        select: %{
          group: %{
            id: type(group.id, Ecto.UUID),
            name: group.name,
            name_key: group.name_key,
            description: group.description,
            archived_at: group.archived_at
          },
          visible_device_count: count(membership.device_id, :distinct)
        }
      )

    query =
      case authorized_device_ids do
        nil -> query
        ids -> from([group, membership] in query, where: type(membership.device_id, Ecto.UUID) in ^ids)
      end

    Repo.all(query)
  end

  defp membership_device_ids(group_id, authorized_device_ids) do
    query =
      from(membership in "device_group_memberships",
        join: group in "device_groups",
        on: group.id == membership.group_id,
        where: type(group.id, Ecto.UUID) == ^group_id,
        where: is_nil(group.archived_at),
        select: type(membership.device_id, Ecto.UUID)
      )

    query =
      case authorized_device_ids do
        nil -> query
        %MapSet{} = ids -> restrict_membership_query(query, MapSet.to_list(ids))
        ids when is_list(ids) -> restrict_membership_query(query, ids)
        _ids -> restrict_membership_query(query, [])
      end

    Repo.all(query)
  end

  defp restrict_membership_query(query, ids) do
    from([membership, group] in query, where: type(membership.device_id, Ecto.UUID) in ^ids)
  end

  defp publish_metadata_result({:ok, %{id: group_id}} = result, action, authorization) do
    publish_group_operation(action, group_id, [], authorization, true)
    result
  end

  defp publish_metadata_result(result, _action, _authorization), do: result

  defp publish_delete_result(:ok, group_id, authorization) do
    {:ok, group_id} = Ecto.UUID.cast(group_id)
    publish_group_operation(:permanent_delete, group_id, [], authorization, true)
    :ok
  end

  defp publish_delete_result(result, _group_id, _authorization), do: result

  defp publish_membership_result(
         {:ok, %{group_id: group_id, changed_device_ids: changed_ids}} = result,
         action,
         authorization
       ) do
    publish_group_operation(action, group_id, changed_ids, authorization, changed_ids != [])
    result
  end

  defp publish_membership_result(result, _action, _authorization), do: result

  defp publish_group_operation(action, group_id, device_ids, authorization, refresh?) do
    GroupAudit.emit(action, authorization.actor_id, group_id, device_ids)

    if refresh? do
      Phoenix.PubSub.broadcast(Nixstasis.PubSub, "devices", :device_groups_changed)
    end

    :ok
  end

  defp mutate_group_memberships(action, group_id, device_ids, authorization)
       when action in [:add, :remove] do
    with {:ok, group_id} <- cast_group_id(group_id),
         {:ok, device_ids} <- cast_device_ids(device_ids),
         :ok <- authorize_group_memberships(authorization, device_ids) do
      run_group_transaction(fn ->
        run_membership_transaction(action, group_id, device_ids, authorization)
      end)
    end
  end

  defp run_membership_transaction(action, group_id, device_ids, authorization) do
    with {:ok, group} <- lock_device_group(group_id),
         :ok <- ensure_active_group(group),
         :ok <- authorize_group_memberships(authorization, device_ids),
         :ok <- lock_existing_devices(device_ids) do
      memberships = current_group_memberships(group_id, device_ids)
      apply_membership_change(action, group_id, device_ids, memberships)
    end
  end

  defp ensure_active_group(%DeviceGroup{archived_at: nil}), do: :ok
  defp ensure_active_group(%DeviceGroup{}), do: {:error, :group_archived}

  defp cast_device_ids(device_ids) when is_list(device_ids) do
    Enum.reduce_while(device_ids, {:ok, []}, fn device_id, {:ok, valid_ids} ->
      case Ecto.UUID.cast(device_id) do
        {:ok, valid_id} -> {:cont, {:ok, append_unique(valid_ids, valid_id)}}
        :error -> {:halt, {:error, :devices_not_found}}
      end
    end)
  end

  defp cast_device_ids(_device_ids), do: {:error, :devices_not_found}

  defp append_unique(ids, id), do: if(id in ids, do: ids, else: ids ++ [id])

  defp authorize_group_memberships(%GroupAuthorization{} = authorization, device_ids) do
    cond do
      not valid_actor_id?(authorization.actor_id) -> {:error, :missing_actor}
      not authorization.can_manage_devices? -> {:error, :unauthorized}
      is_nil(authorization.authorized_device_ids) -> :ok
      MapSet.subset?(MapSet.new(device_ids), authorization.authorized_device_ids) -> :ok
      true -> {:error, :unauthorized_devices}
    end
  end

  defp lock_existing_devices([]), do: :ok

  defp lock_existing_devices(device_ids) do
    dumped_ids = Enum.map(device_ids, &Ecto.UUID.dump!/1)

    %{num_rows: count} =
      Repo.query!("SELECT id FROM devices WHERE id = ANY($1::uuid[]) FOR UPDATE", [dumped_ids])

    if count == length(device_ids), do: :ok, else: {:error, :devices_not_found}
  end

  defp current_group_memberships(_group_id, []), do: []

  defp current_group_memberships(group_id, device_ids) do
    DeviceGroupMembership
    |> Ash.Query.filter(group_id == ^group_id and device_id in ^device_ids)
    |> Ash.read!(domain: Domain)
  end

  defp apply_membership_change(:add, group_id, device_ids, memberships) do
    existing_ids = MapSet.new(memberships, & &1.device_id)
    changed_ids = Enum.reject(device_ids, &MapSet.member?(existing_ids, &1))

    persist_added_memberships(group_id, device_ids, changed_ids)
  end

  defp apply_membership_change(:remove, group_id, device_ids, memberships) do
    by_device_id = Map.new(memberships, &{&1.device_id, &1})
    changed_ids = Enum.filter(device_ids, &Map.has_key?(by_device_id, &1))

    persist_removed_memberships(group_id, device_ids, changed_ids, by_device_id)
  end

  defp persist_added_memberships(group_id, device_ids, changed_ids) do
    changed_ids
    |> Enum.reduce_while({:ok, []}, fn device_id, {:ok, notifications} ->
      case Domain.create_device_group_membership(
             %{group_id: group_id, device_id: device_id},
             return_notifications?: true
           ) do
        {:ok, _membership, new_notifications} ->
          {:cont, {:ok, notifications ++ new_notifications}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> membership_result(group_id, device_ids, changed_ids)
  end

  defp persist_removed_memberships(group_id, device_ids, changed_ids, by_device_id) do
    changed_ids
    |> Enum.reduce_while({:ok, []}, fn device_id, {:ok, notifications} ->
      case Domain.destroy_device_group_membership(by_device_id[device_id], return_notifications?: true) do
        {:ok, new_notifications} -> {:cont, {:ok, notifications ++ new_notifications}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> membership_result(group_id, device_ids, changed_ids)
  end

  defp membership_result({:ok, notifications}, group_id, device_ids, changed_ids) do
    {:ok, %{group_id: group_id, device_ids: device_ids, changed_device_ids: changed_ids}, notifications}
  end

  defp membership_result({:error, reason}, _group_id, _device_ids, _changed_ids),
    do: {:error, reason}

  defp authorize_group_metadata(%GroupAuthorization{} = authorization) do
    cond do
      not valid_actor_id?(authorization.actor_id) -> {:error, :missing_actor}
      not authorization.can_manage_devices? -> {:error, :unauthorized}
      not authorization.can_manage_all_devices? -> {:error, :unauthorized}
      not is_nil(authorization.authorized_device_ids) -> {:error, :unauthorized}
      true -> :ok
    end
  end

  defp valid_actor_id?(actor_id) when is_binary(actor_id), do: String.trim(actor_id) != ""
  defp valid_actor_id?(_actor_id), do: false

  defp metadata_attrs(attrs) do
    Map.take(attrs, [:name, :description, "name", "description"])
  end

  defp mutate_group(group_id, authorization, operation) do
    with :ok <- authorize_group_metadata(authorization),
         {:ok, group_id} <- cast_group_id(group_id) do
      run_locked_group_transaction(group_id, operation)
    end
  end

  defp run_locked_group_transaction(group_id, operation) do
    run_group_transaction(fn -> apply_to_locked_group(group_id, operation) end)
  end

  defp apply_to_locked_group(group_id, operation) do
    case lock_device_group(group_id) do
      {:ok, group} -> operation.(group)
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_archived_group(%DeviceGroup{archived_at: nil}), do: {:error, :group_not_archived}

  defp delete_archived_group(%DeviceGroup{} = group) do
    case Domain.destroy_device_group(group, return_notifications?: true) do
      {:ok, notifications} -> {:ok, :deleted, notifications}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cast_group_id(group_id) do
    case Ecto.UUID.cast(group_id) do
      {:ok, group_id} -> {:ok, group_id}
      :error -> {:error, :group_not_found}
    end
  end

  defp lock_device_group(group_id) do
    case Repo.query!("SELECT id FROM device_groups WHERE id = $1::uuid FOR UPDATE", [Ecto.UUID.dump!(group_id)]).rows do
      [[_id]] -> Domain.get_device_group(group_id)
      [] -> {:error, :group_not_found}
    end
  end

  defp run_group_transaction(operation) do
    Repo.transaction(fn ->
      case operation.() do
        {:ok, value, notifications} -> {value, notifications}
        {:ok, value} -> {value, []}
        :ok -> {:ok, []}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {:ok, notifications}} ->
        Ash.Notifier.notify(notifications)
        :ok

      {:ok, {:deleted, notifications}} ->
        Ash.Notifier.notify(notifications)
        :ok

      {:ok, {value, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, value}

      {:error, reason} ->
        {:error, reason}
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

  defp pending_device_ids([]), do: []

  defp pending_device_ids(ids) do
    Device
    |> Ash.Query.filter(id in ^ids and approval_status == :pending)
    |> Ash.read!(domain: Domain)
    |> Enum.map(& &1.id)
  end

  defp broadcast_update_for_attrs(%Device{} = device, attrs) when is_map(attrs) and map_size(attrs) > 0 do
    events =
      []
      |> maybe_add_update_event(attrs, :approval_status, :device_approval_status_changed)
      |> maybe_add_update_event(attrs, :last_seen_at, :device_last_seen_updated)
      |> maybe_add_update_event(attrs, :remote_access_requested, :device_remote_access_changed)

    case events do
      [] -> broadcast_device(:device_updated, device)
      events -> Enum.each(events, &broadcast_device(&1, device))
    end
  end

  defp broadcast_update_for_attrs(_device, _attrs), do: :ok

  defp maybe_add_update_event(events, attrs, key, event) do
    if Map.has_key?(attrs, key) or Map.has_key?(attrs, to_string(key)) do
      [event | events]
    else
      events
    end
  end

  defp broadcast_device(event, %Device{} = device) do
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, "devices", {event, device_broadcast_payload(device)})
  end

  defp device_broadcast_payload(%Device{} = device) do
    %{
      id: device.id,
      mac_address: device.mac_address,
      approval_status: device.approval_status,
      last_seen_at: device.last_seen_at,
      remote_access_requested: device.remote_access_requested
    }
  end

  defp fetch_pending_command(_device_id, command_id) when is_nil(command_id) or command_id == "", do: nil

  defp fetch_pending_command(device_id, command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, command_id} -> read_pending_command(device_id, command_id)
      :error -> nil
    end
  end

  defp read_pending_command(device_id, command_id) do
    PendingCommand
    |> Ash.Query.filter(device_id == ^device_id and id == ^command_id)
    |> Ash.read_one!(domain: Domain)
  rescue
    error ->
      Logger.warning(
        "Failed to fetch pending command #{inspect(command_id)} for device #{device_id}: #{Exception.message(error)}"
      )

      nil
  end

  defp pending_command_result_status(device_id, command_id) do
    case read_pending_command(device_id, command_id) do
      %{status: :acked, command_payload: %{} = payload} ->
        case payload["result_status"] || payload[:result_status] do
          "ok" -> :ok
          _ -> :failed
        end

      _ ->
        :pending
    end
  end

  defp command_policy_command_payload(assignment) do
    payload_data =
      Jason.encode!(%{
        assignment_id: assignment.id,
        version: assignment.version,
        revision: assignment.revision,
        commands: Map.get(assignment.resolved_policy, "commands", %{})
      })

    deferred? = byte_size(payload_data) > @inline_command_policy_payload_limit

    %{
      "type" => "apply_command_policy",
      "payload_ref" => assignment.id,
      "defer_payload" => deferred?,
      "payload" => %{
        "content_type" => @command_policy_content_type,
        "name" => assignment.version,
        "data" => payload_data
      }
    }
  end

  defp supersede_queued_command_policies(device_id) do
    Repo.delete_all(
      from(command in PendingCommand,
        where: command.device_id == ^device_id,
        where: command.status == :queued,
        where: fragment("?->>? = ?", command.command_payload, "type", "apply_command_policy")
      )
    )

    :ok
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
