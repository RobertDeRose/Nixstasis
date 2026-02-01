defmodule Nixstasis.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field(:mac_address, :string)
    field(:product_key, :string)
    field(:approval_status, :string, default: "pending")
    field(:schema_definition, :map, default: %{})
    field(:last_seen_at, :utc_datetime)
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :mac_address,
      :product_key,
      :approval_status,
      :schema_definition,
      :last_seen_at,
      :metadata
    ])
    |> validate_required([:mac_address, :product_key])
    |> validate_inclusion(:approval_status, ["pending", "approved", "rejected"])
    |> unique_constraint(:mac_address)
  end
end
