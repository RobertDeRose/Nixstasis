defmodule Nixstasis.Types.AlertType do
  @moduledoc """
  Types of alerts that can be raised.
  """

  use Ash.Type.Enum, values: [:offline, :threshold]
end
