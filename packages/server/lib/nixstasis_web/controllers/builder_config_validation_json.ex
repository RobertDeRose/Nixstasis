defmodule NixstasisWeb.BuilderConfigValidationJSON do
  def show(%{validation: validation}) do
    %{
      valid: validation.valid,
      issues:
        Enum.map(validation.issues, fn issue ->
          %{
            issue_code: issue.issue_code,
            message: issue.message,
            slot_id: issue.slot_id,
            blocking: issue.blocking
          }
        end),
      cleared_slot_ids: validation.cleared_slot_ids
    }
  end
end
