defmodule SymphonyElixir.Repo.Migrations.CreateFeedbackTables do
  use Ecto.Migration

  def change do
    create table(:feedback_items) do
      add :run_id, :string, null: false
      add :source, :string, null: false
      add :severity, :string, null: false
      add :status, :string, null: false
      add :body, :text, null: false
      add :external_url, :string
      add :file_location, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:feedback_items, [:run_id])
    create index(:feedback_items, [:status])

    create table(:fix_attempts) do
      add :run_id, :string, null: false
      add :attempt_number, :integer, null: false
      add :trigger_source, :string, null: false
      add :base_commit, :string, null: false
      add :result_commit, :string
      add :artifact_paths, {:array, :string}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fix_attempts, [:run_id, :attempt_number])
    create index(:fix_attempts, [:run_id])
  end
end
