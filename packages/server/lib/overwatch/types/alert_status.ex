defmodule Nixstasis.Types.AlertStatus do
  @moduledoc """
  Statuses for alerts.
  """

  use Ash.Type.Enum, values: [:active, :resolved, :acknowledged]
end
