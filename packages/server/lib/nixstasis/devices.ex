defmodule Nixstasis.Devices do
  @moduledoc """
  The Devices context.
  """

  require Ash.Query

  import Ecto.Query, only: [from: 2]

  alias Nixstasis.Domain
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.PendingCommand
  alias Nixstasis.Devices.SchemaValidator
  alias Nixstasis.Repo

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
        Domain.register_device(safe_attrs)

      {:error, msg} ->
        {:error,
         Ash.Error.Invalid.exception(
           errors: [Ash.Error.Changes.InvalidAttribute.exception(field: :schema_definition, message: msg)]
         )}
    end
  end

  def update_last_seen(%Device{} = device) do
    Domain.update_device(device, %{last_seen_at: DateTime.utc_now()})
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
    * `:filter` - A map of filters (e.g., `%{status: :pending}`).
    * `:search` - A search string for mac_address or account_number.
  """
  def list_devices(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, :inserted_at)
    sort_order = Keyword.get(opts, :sort_order, :desc)
    filter = Keyword.get(opts, :filter, %{})
    search = Keyword.get(opts, :search)

    Device
    |> filter_by_status(filter[:status])
    |> filter_by_product(filter[:product])
    |> filter_by_account_number(filter[:account_number])
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

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, status) do
    case normalize_status_filter(status) do
      nil -> query
      normalized_status -> Ash.Query.filter(query, approval_status == ^normalized_status)
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

  defp normalize_status_filter(status) when is_atom(status), do: status

  defp normalize_status_filter(status) when is_binary(status) do
    case String.trim(status) do
      "" ->
        nil

      value ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp normalize_status_filter(_), do: nil

  @doc """
  Approves multiple devices by ID.
  """
  def approve_devices(ids) when is_list(ids) do
    result =
      Device
      |> Ash.Query.filter(id in ^ids)
      |> Ash.bulk_update!(:update, %{approval_status: :approved}, domain: Domain, strategy: :stream)

    clear_device_token_hashes(ids)
    result
  end

  @doc """
  Rejects multiple devices by ID.
  """
  def reject_devices(ids) when is_list(ids) do
    Device
    |> Ash.Query.filter(id in ^ids)
    |> Ash.bulk_update!(:update, %{approval_status: :rejected}, domain: Domain, strategy: :stream)
  end

  @doc """
  Sets the remote_access_requested flag.
  """
  def set_remote_access(%Device{} = device, requested?) do
    Domain.update_device(device, %{remote_access_requested: requested?})
  end

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
    Domain.create_device(attrs)
  end

  @doc """
  Updates a device.
  """
  def update_device(%Device{} = device, attrs) do
    Domain.update_device(device, attrs)
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

    acknowledged_count =
      Enum.reduce(results, 0, fn result, count ->
        command_id = Map.get(result, "command_id") || Map.get(result, :command_id)

        case fetch_pending_command(device.id, command_id) do
          nil ->
            count

          command ->
            status = command_result_status(result)
            updated_payload = merge_command_result(command.command_payload, result, now, status)

            case Domain.update_pending_command(command, %{status: :acked, command_payload: updated_payload}) do
              {:ok, _} -> count + 1
              {:error, _reason} -> count
            end
        end
      end)

    {:ok, acknowledged_count}
  end

  def acknowledge_command_results(_device, _results), do: {:error, "results must be a list"}

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
