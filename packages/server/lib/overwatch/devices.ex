defmodule Nixstasis.Devices do
  @moduledoc """
  The Devices context.
  """

  import Ecto.Query, warn: false
  alias Nixstasis.Repo

  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.PendingCommand
  alias Nixstasis.Devices.SchemaValidator

  @doc """
  Counts all devices.
  """
  def count_all do
    Repo.aggregate(Device, :count, :id)
  end

  @doc """
  Counts devices by online/offline status.
  Online is defined as seen within the last 5 minutes.
  """
  def count_by_status(:online) do
    threshold = DateTime.add(DateTime.utc_now(), -5, :minute)

    Device
    |> where([d], d.last_seen_at >= ^threshold)
    |> Repo.aggregate(:count, :id)
  end

  def count_by_status(:offline) do
    threshold = DateTime.add(DateTime.utc_now(), -5, :minute)

    Device
    |> where([d], d.last_seen_at < ^threshold or is_nil(d.last_seen_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts devices pending approval.
  """
  def count_pending_approvals do
    Device
    |> where([d], d.approval_status == :pending)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Registers a device.
  """
  def register_device(attrs) do
    # Prevent device from setting its own status
    safe_attrs =
      if is_map(attrs) do
        attrs
        |> Map.delete("approval_status")
        |> Map.delete(:approval_status)
      else
        attrs
      end

    schema_def = safe_attrs["schema_definition"] || safe_attrs[:schema_definition] || %{}
    mac = safe_attrs["mac_address"] || safe_attrs[:mac_address]

    with :ok <- SchemaValidator.validate(schema_def) do
      case Repo.get_by(Device, mac_address: mac) do
        nil ->
          %Device{}
          |> Device.changeset(safe_attrs)
          |> Repo.insert()

        %Device{} = device ->
          device
          |> Device.changeset(safe_attrs)
          |> Repo.update()
      end
    else
      {:error, msg} ->
        %Device{}
        |> Device.changeset(safe_attrs)
        |> Ecto.Changeset.add_error(:schema_definition, msg)
        |> then(&{:error, &1})
    end
  end

  def update_last_seen(%Device{} = device) do
    device
    |> Device.changeset(%{last_seen_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Lists pending devices.
  """
  def list_pending_devices do
    Device
    |> where([d], d.approval_status == :pending)
    |> Repo.all()
  end

  @doc """
  Approves a device.
  """
  def approve_device(%Device{} = device) do
    device
    |> Device.changeset(%{approval_status: :approved})
    |> Repo.update()
  end

  @doc """
  Returns the list of devices.

  ## Options
    * `:sort_by` - The field to sort by. Defaults to `:inserted_at`.
    * `:sort_order` - The sort order, `:asc` or `:desc`. Defaults to `:desc`.
    * `:filter` - A map of filters (e.g., `%{status: :pending}`).
    * `:search` - A search string for mac_address or account_number.

  ## Examples

      iex> list_devices()
      [%Device{}, ...]

  """
  def list_devices(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, :inserted_at)
    sort_order = Keyword.get(opts, :sort_order, :desc)
    filter = Keyword.get(opts, :filter, %{})
    search = Keyword.get(opts, :search)

    Device
    |> filter_by_status(filter[:status])
    |> search_devices(search)
    |> order_by([d], {^sort_order, field(d, ^sort_by)})
    |> Repo.all()
  end

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, status) do
    where(query, [d], d.approval_status == ^status)
  end

  defp search_devices(query, nil), do: query

  defp search_devices(query, term) do
    term = "%#{term}%"
    where(query, [d], ilike(d.mac_address, ^term) or ilike(d.account_number, ^term))
  end

  @doc """
  Approves multiple devices by ID.
  """
  def approve_devices(ids) when is_list(ids) do
    from(d in Device, where: d.id in ^ids)
    |> Repo.update_all(set: [approval_status: :approved, updated_at: DateTime.utc_now()])
  end

  @doc """
  Rejects multiple devices by ID.
  """
  def reject_devices(ids) when is_list(ids) do
    from(d in Device, where: d.id in ^ids)
    |> Repo.update_all(set: [approval_status: :rejected, updated_at: DateTime.utc_now()])
  end

  @doc """
  Sets the remote_access_requested flag.
  """
  def set_remote_access(%Device{} = device, requested?) do
    device
    |> Device.changeset(%{remote_access_requested: requested?})
    |> Repo.update()
  end

  @doc """
  Gets a single device.

  Raises `Ecto.NoResultsError` if the Device does not exist.

  ## Examples

      iex> get_device!(123)
      %Device{}

      iex> get_device!(456)
      ** (Ecto.NoResultsError)

  """
  def get_device!(id), do: Repo.get!(Device, id)

  @doc """
  Creates a device.

  ## Examples

      iex> create_device(%{field: value})
      {:ok, %Device{}}

      iex> create_device(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_device(attrs \\ %{}) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a device.

  ## Examples

      iex> update_device(device, %{field: new_value})
      {:ok, %Device{}}

      iex> update_device(device, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a device.

  ## Examples

      iex> delete_device(device)
      {:ok, %Device{}}

      iex> delete_device(device)
      {:error, %Ecto.Changeset{}}

  """
  def delete_device(%Device{} = device) do
    Repo.delete(device)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking device changes.

  ## Examples

      iex> change_device(device)
      %Ecto.Changeset{data: %Device{}}

  """
  def change_device(%Device{} = device, attrs \\ %{}) do
    Device.changeset(device, attrs)
  end

  def queue_command(%Device{} = device, payload) do
    %PendingCommand{}
    |> PendingCommand.changeset(%{
      device_id: device.id,
      command_payload: payload,
      status: "queued",
      queued_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def pop_pending_commands(%Device{} = device) do
    Repo.transaction(fn ->
      query =
        from(c in PendingCommand,
          where: c.device_id == ^device.id and c.status == "queued",
          lock: "FOR UPDATE SKIP LOCKED"
        )

      commands = Repo.all(query)

      now = DateTime.utc_now()

      if commands != [] do
        from(c in PendingCommand, where: c.id in ^Enum.map(commands, & &1.id))
        |> Repo.update_all(set: [status: "delivered", delivered_at: now])
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
