defmodule Nixstasis.Types.ApprovalStatus do
  @moduledoc """
  Approval statuses for devices.
  """

  use Ash.Type.Enum, values: [:pending, :approved, :rejected]
end
