defmodule Nixstasis.Devices.Device do
  @moduledoc """
  The Device schema.

  This schema represents a device in the Nixstasis system, capturing essential
  attributes such as MAC address, product name, approval status, and metadata.
  It includes validations to ensure data integrity, such as MAC address formatting
  and approval status constraints.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Nixstasis.Utilities, only: [format_mac_address: 1]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field(:mac_address, :string)
    field(:product_name, :string)
    field(:account_number, :string)
    field(:approval_status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending)
    field(:last_seen_at, :utc_datetime)
    field(:schema, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:remote_access_requested, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :mac_address,
      :product_name,
      :account_number,
      :approval_status,
      :last_seen_at,
      :schema,
      :metadata,
      :remote_access_requested
    ])
    |> validate_required([:mac_address])
    |> update_change(:mac_address, &format_mac_address/1)
    |> validate_format(:mac_address, ~r/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/)
    |> validate_format(:account_number, ~r/^\d+$/)
    |> validate_length(:account_number, min: 5)
    |> unique_constraint(:mac_address)
  end
end
