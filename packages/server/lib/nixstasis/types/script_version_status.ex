defmodule Nixstasis.Types.ScriptVersionStatus do
  @moduledoc """
  Statuses for script versions.
  """

  use Ash.Type.Enum, values: [:candidate, :validated, :deployed, :superseded, :archived]
end
