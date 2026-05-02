defmodule Nixstasis.E2E.EnvironmentLocks do
  @moduledoc """
  Manages environment-level locks for E2E execution.
  """

  import Ecto.Query

  alias Nixstasis.E2E.EnvironmentLock
  alias Nixstasis.Repo

  def acquire(environment_label) when is_binary(environment_label) do
    now = DateTime.utc_now()
    attrs = %{environment_label: environment_label, locked_at: now, inserted_at: now, updated_at: now}

    case Repo.insert_all(EnvironmentLock, [attrs], on_conflict: :nothing, conflict_target: :environment_label) do
      {1, _} ->
        {:ok, struct(EnvironmentLock, attrs)}

      {0, _} ->
        {:error, {:environment_locked, "Environment '#{environment_label}' already has an active E2E run."}}

      other ->
        {:error, {:database_error, other}}
    end
  end

  def assign_run(environment_label, run_id) when is_binary(environment_label) and is_binary(run_id) do
    from(lock in EnvironmentLock, where: lock.environment_label == ^environment_label)
    |> Repo.update_all(set: [run_id: run_id, updated_at: DateTime.utc_now()])

    :ok
  end

  def release(environment_label) when is_binary(environment_label) do
    from(lock in EnvironmentLock, where: lock.environment_label == ^environment_label)
    |> Repo.delete_all()

    :ok
  end

  def release_by_run(run_id) when is_binary(run_id) do
    from(lock in EnvironmentLock, where: lock.run_id == ^run_id)
    |> Repo.delete_all()

    :ok
  end
end
