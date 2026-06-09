defmodule Nixstasis.Types.ScriptClientActionStatus do
  @moduledoc """
  Statuses for per-client script actions.
  """

  use Ash.Type.Enum, values: [:queued, :delivered, :acknowledged, :failed, :missing_payload]
end
