defmodule Nixstasis.Repo.Migrations.BindE2ERunsToRunner do
  use Ecto.Migration

  def up do
    alter table(:e2e_runs) do
      add :runner_id, :text
    end

    # The leading colon is outside the runner-ID grammar, so no configured
    # runner can authenticate as the owner of pre-ownership runs.
    execute("UPDATE e2e_runs SET runner_id = ':unowned' WHERE runner_id IS NULL")
    execute("ALTER TABLE e2e_runs ALTER COLUMN runner_id SET NOT NULL")

    create index(:e2e_runs, [:runner_id, :inserted_at], name: :e2e_runs_runner_inserted_at_idx)
  end

  def down do
    drop_if_exists index(:e2e_runs, [:runner_id, :inserted_at], name: :e2e_runs_runner_inserted_at_idx)

    alter table(:e2e_runs) do
      remove :runner_id
    end
  end
end
