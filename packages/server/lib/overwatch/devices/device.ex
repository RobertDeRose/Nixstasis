defmodule Nixstasis.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field(:mac_address, :string)
    field(:product_name, :string)
    field(:approval_status, :string, default: "pending")
    field(:schema_definition, :map, default: %{})
    field(:last_seen_at, :utc_datetime)
    field(:metadata, :map, default: %{})
    field(:ipv4_address, :string)
    field(:account_number, :string)
    field(:remote_access_requested, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :mac_address,
      :product_name,
      :approval_status,
      :schema_definition,
      :last_seen_at,
      :metadata,
      :ipv4_address,
      :account_number,
      :remote_access_requested
    ])
    |> validate_required([:mac_address])
    |> validate_inclusion(:approval_status, ["pending", "approved", "rejected"])
    |> validate_format(:account_number, ~r/^\d+$/, message: "must contain only digits")
    |> unique_constraint(:mac_address)
    |> normalize_mac_address()
  end

  defp normalize_mac_address(changeset) do
    case get_change(changeset, :mac_address) do
      nil ->
        changeset

      mac ->
        # Remove all non-alphanumeric chars
        clean_mac = String.replace(mac, ~r/[^a-fA-F0-9]/, "") |> String.upcase()

        cond do
          # Basic length check (EUI-48 is 12 hex chars)
          String.length(clean_mac) == 12 ->
            formatted_mac =
              clean_mac
              |> String.graphemes()
              |> Enum.chunk_every(2)
              |> Enum.map(&Enum.join/1)
              |> Enum.join(":")

            put_change(changeset, :mac_address, formatted_mac)

          true ->
            add_error(changeset, :mac_address, "is invalid. Must be 12 hex characters.")
        end
    end
  end
end
