defmodule Nixstasis.Types.CommandPolicyDeliveryStatus do
  @moduledoc """
  Client delivery outcomes for command policy application.
  """

  use Ash.Type.Enum,
    values: [:delivered, :acknowledged, :failed, :unsupported, :stale, :conflict, :persistence_failed]
end
