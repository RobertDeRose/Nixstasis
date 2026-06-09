defmodule Nixstasis.Types.ScriptTestRunStatus do
  @moduledoc """
  Statuses for script test runs.
  """

  use Ash.Type.Enum,
    values: [:pending, :running, :passed, :failed, :timed_out, :unsupported, :unavailable]
end
