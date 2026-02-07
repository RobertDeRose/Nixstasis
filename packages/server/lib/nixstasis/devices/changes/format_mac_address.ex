defmodule Nixstasis.Devices.Changes.FormatMacAddress do
  @moduledoc """
  Normalizes MAC addresses into colon-separated uppercase format.
  """

  use Ash.Resource.Change

  import Nixstasis.Utilities, only: [format_mac_address: 1]

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :mac_address) do
      {:ok, mac} when is_binary(mac) ->
        Ash.Changeset.change_attribute(changeset, :mac_address, format_mac_address(mac))

      _ ->
        changeset
    end
  end
end
