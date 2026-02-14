defmodule Nixstasis.E2E.EnvironmentLock do
  @moduledoc """
  Represents a per-environment execution lock for E2E runs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:environment_label, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "e2e_environment_locks" do
    field :locked_at, :utc_datetime_usec

    belongs_to :run, Nixstasis.E2E.Run

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(environment_label locked_at)a

  def changeset(lock, attrs) do
    lock
    |> cast(attrs, @required_fields ++ [:run_id])
    |> validate_required(@required_fields)
  end
end
