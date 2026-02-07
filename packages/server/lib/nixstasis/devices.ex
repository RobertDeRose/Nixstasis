defmodule Nixstasis.Devices do
  @moduledoc """
  The Devices context.
  """

  require Ash.Query

  alias Nixstasis.Domain
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.PendingCommand
  alias Nixstasis.Devices.SchemaValidator

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
    Domain.update_device(device, %{approval_status: :approved})
  end

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
    Ash.Query.filter(query, approval_status == ^status)
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
    Device
    |> Ash.Query.filter(id in ^ids)
    |> Ash.bulk_update!(:update, %{approval_status: :approved}, domain: Domain, strategy: :stream)
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
    Ash.transaction(PendingCommand, fn ->
      query =
        PendingCommand
        |> Ash.Query.filter(device_id == ^device.id and status == :queued)

      commands = Ash.read!(query, domain: Domain)

      if commands != [] do
        ids = Enum.map(commands, & &1.id)
        now = DateTime.utc_now()

        PendingCommand
        |> Ash.Query.filter(id in ^ids)
        |> Ash.bulk_update!(:update, %{status: :delivered, delivered_at: now}, domain: Domain)
      end

      commands
    end)
    |> case do
      {:ok, commands} -> commands
      _ -> []
    end
  end

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
end
