defmodule Nixstasis.Types.BuilderKind do
  @moduledoc """
  Supported schema-driven builder contract kinds.
  """

  use Ash.Type.Enum, values: [:alert, :report]
end
