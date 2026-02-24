defmodule Nixstasis.E2E.DataPolicy do
  @moduledoc """
  Enforces synthetic-only test data policy for E2E runs.
  """

  def validate_environment(label) when is_binary(label) do
    allowed = allowed_environments()

    if label in allowed do
      :ok
    else
      {:error,
       "Environment '#{label}' is not approved for synthetic-only E2E runs. Allowed: #{Enum.join(allowed, ", ")}."}
    end
  end

  def validate_environment(_), do: {:error, "Environment label must be provided."}

  def allowed_environments do
    Application.get_env(:nixstasis, :e2e, [])
    |> Keyword.get(:allowed_env_labels, [])
  end
end
