defmodule Nixstasis.Devices.PendingCommand do
  @moduledoc """
  Schema for queued device commands awaiting delivery.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pending_commands" do
    field(:command_payload, :map)
    field(:status, :string, default: "queued")
    field(:queued_at, :utc_datetime)
    field(:delivered_at, :utc_datetime)

    belongs_to(:device, Nixstasis.Devices.Device)

    timestamps(type: :utc_datetime)
  end

  def changeset(pending_command, attrs) do
    pending_command
    |> cast(attrs, [:device_id, :command_payload, :status, :queued_at, :delivered_at])
    |> validate_required([:device_id, :command_payload])
    |> validate_inclusion(:status, ["queued", "delivered", "acked"])
  end
end
