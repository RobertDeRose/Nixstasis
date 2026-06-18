defmodule Nixstasis.Types.ScriptDraftStatus do
  @moduledoc """
  Statuses for script drafts.
  """

  use Ash.Type.Enum, values: [:draft, :validated, :archived]
end
