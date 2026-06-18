defmodule Nixstasis.Types.ScriptDeploymentStatus do
  @moduledoc """
  Statuses for script deployment runs.
  """

  use Ash.Type.Enum, values: [:pending, :running, :deployed, :partial, :failed]
end
