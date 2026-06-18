defmodule Nixstasis.Types.ScriptClientActionKind do
  @moduledoc """
  Kinds of client-targeted script actions.
  """

  use Ash.Type.Enum, values: [:test, :deploy]
end
