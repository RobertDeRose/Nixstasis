defmodule Nixstasis.Monitoring.Alert do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "alerts" do
    # offline, threshold
    field(:type, :string)
    field(:status, :string, default: "active")
    field(:message, :string)
    field(:triggered_at, :utc_datetime)
    # Virtual or future relation
    field(:rule_id, :binary_id)

    belongs_to(:device, Nixstasis.Devices.Device)

    timestamps(type: :utc_datetime)
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:device_id, :rule_id, :type, :status, :message, :triggered_at])
    |> validate_required([:device_id, :type, :message, :triggered_at])
    |> validate_inclusion(:type, ["offline", "threshold"])
    |> validate_inclusion(:status, ["active", "resolved", "acknowledged"])
  end
end
