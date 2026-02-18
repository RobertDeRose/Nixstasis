defmodule Nixstasis.Types.RuleOperator do
  @moduledoc """
  Supported operators for alert rules.
  """

  use Ash.Type.Enum, values: [">", "<", "=", "!=", ">=", "<=", "contains", "doesn't contain", "is", "is not"]
end
