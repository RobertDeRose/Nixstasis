defmodule Nixstasis.Repo.Migrations.BindE2ERunsToRunner do
  use Ecto.Migration

  def up do
    alter table(:e2e_runs) do
      add :runner_id, :text
    end

    # The leading colon is outside the runner-ID grammar, so no configured
    # runner can authenticate as the owner of pre-ownership runs.
    execute("UPDATE e2e_runs SET runner_id = ':unowned' WHERE runner_id IS NULL")

    # No runner can finish or cancel an unowned run, so close active ones and
    # release their environment locks instead of leaving the environment held.
    execute("""
    UPDATE e2e_runs
    SET status = 'cancelled', finished_at = (now() AT TIME ZONE 'utc')
    WHERE runner_id = ':unowned'
      AND status NOT IN ('passed', 'failed', 'blocked', 'cancelled')
    """)

    execute("""
    DELETE FROM e2e_environment_locks
    WHERE run_id IN (SELECT id FROM e2e_runs WHERE runner_id = ':unowned')
    """)

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
