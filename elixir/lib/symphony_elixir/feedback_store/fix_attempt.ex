defmodule SymphonyElixir.FeedbackStore.FixAttempt do
  @moduledoc """
  Schema for persisted fix attempt records.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "fix_attempts" do
    field(:run_id, :string)
    field(:attempt_number, :integer)
    field(:trigger_source, :string)
    field(:base_commit, :string)
    field(:result_commit, :string)
    field(:artifact_paths, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(run_id attempt_number trigger_source base_commit)a
  @optional_fields ~w(result_commit artifact_paths)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(fix_attempt, attrs) do
    fix_attempt
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_length(:trigger_source, min: 1, max: 255)
    |> validate_length(:base_commit, min: 1, max: 64)
    |> unique_constraint([:run_id, :attempt_number])
  end
end
