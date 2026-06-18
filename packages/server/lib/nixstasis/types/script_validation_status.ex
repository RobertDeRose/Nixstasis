defmodule Nixstasis.Types.ScriptValidationStatus do
  @moduledoc """
  Statuses for script validation runs.
  """

  use Ash.Type.Enum, values: [:pending, :passed, :failed]
end
