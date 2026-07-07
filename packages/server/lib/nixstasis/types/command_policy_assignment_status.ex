defmodule Nixstasis.Types.CommandPolicyAssignmentStatus do
  @moduledoc """
  Lifecycle states for per-device command policy assignments.
  """

  use Ash.Type.Enum, values: [:pending, :queued, :acknowledged, :failed, :revoked]
end
