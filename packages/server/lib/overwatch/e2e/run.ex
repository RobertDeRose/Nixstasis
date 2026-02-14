defmodule Nixstasis.E2E.Run do
  @moduledoc """
  Represents a single E2E run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "e2e_runs" do
    field :suite_id, :string
    field :journey_ids, {:array, :string}, default: []
    field :environment_label, :string
    field :trigger_source, :string
    field :protocol_version, :string
    field :idempotency_key, :string
    field :idempotency_expires_at, :utc_datetime_usec
    field :status, :string, default: "queued"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :run_metadata, :map, default: %{}

    has_many :results, Nixstasis.E2E.RunResult, foreign_key: :run_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(suite_id environment_label trigger_source protocol_version)a
  @status_values ~w(queued running passed failed cancelled blocked)
  @trigger_values ~w(manual ci)

  def changeset(run, attrs) do
    run
    |> cast(
      attrs,
      @required_fields ++
        [:journey_ids, :status, :started_at, :finished_at, :run_metadata, :idempotency_key, :idempotency_expires_at]
    )
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @status_values)
    |> validate_inclusion(:trigger_source, @trigger_values)
  end
end
