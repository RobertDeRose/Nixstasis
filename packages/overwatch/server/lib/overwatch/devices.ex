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
    |> where([d], d.approval_status == "pending")
    |> Repo.all()
  end

  @doc """
  Approves a device.
  """
  def approve_device(%Device{} = device) do
    device
    |> Device.changeset(%{approval_status: "approved"})
    |> Repo.update()
  end

  @doc """
  Returns the list of devices.

  ## Examples

      iex> list_devices()
      [%Device{}, ...]

  """
  def list_devices do
    Repo.all(Device)
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
end
