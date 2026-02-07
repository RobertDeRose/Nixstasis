defmodule Nixstasis.Types.PendingCommandStatus do
  @moduledoc """
  Statuses for pending device commands.
  """

  use Ash.Type.Enum, values: [:queued, :delivered, :acked]
end
