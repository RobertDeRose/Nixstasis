defmodule Nixstasis.Types.ProvisioningDeliveryState do
  @moduledoc """
  Persisted states for an AtomixOS bootstrap delivery.
  """

  use Ash.Type.Enum,
    values: [:submitting, :submitted, :running, :succeeded, :failed, :indeterminate]
end
