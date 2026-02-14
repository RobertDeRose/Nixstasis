defmodule Nixstasis.E2E.RunResult do
  @moduledoc """
  Represents a per-journey result for an E2E run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "e2e_run_results" do
    field :journey_id, :string
    field :status, :string, default: "queued"
    field :failure_step, :string
    field :failure_reason, :string
    field :log_ref, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :duration_ms, :integer

    belongs_to :run, Nixstasis.E2E.Run

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(run_id journey_id status)a
  @status_values ~w(queued running passed failed cancelled blocked skipped)

  def changeset(result, attrs) do
    result
    |> cast(
      attrs,
      @required_fields ++ [:failure_step, :failure_reason, :log_ref, :started_at, :finished_at, :duration_ms]
    )
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @status_values)
  end
end
