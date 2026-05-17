defmodule Nixstasis.Devices.Validations.ApprovalTransition do
  @moduledoc """
  Validates that approval_status transitions are only allowed from :pending.

  Allowed transitions:
    - pending -> approved
    - pending -> rejected
    - any status -> same status (no-op)

  All other transitions are rejected.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :approval_status) do
      nil ->
        :ok

      new_status ->
        current = changeset.data.approval_status

        cond do
          current == new_status -> :ok
          current == :pending and new_status in [:approved, :rejected] -> :ok
          true -> {:error, approval_transition_error(current, new_status)}
        end
    end
  end

  defp approval_transition_error(current, next) do
    InvalidAttribute.exception(
      field: :approval_status,
      message: "cannot transition from %{current} to %{next}",
      vars: %{current: current, next: next}
    )
  end
end
