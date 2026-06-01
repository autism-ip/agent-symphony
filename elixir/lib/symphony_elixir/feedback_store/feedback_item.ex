defmodule SymphonyElixir.FeedbackStore.FeedbackItem do
  @moduledoc """
  Schema for persisted review feedback items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "feedback_items" do
    field(:run_id, :string)
    field(:source, :string)
    field(:severity, Ecto.Enum, values: [:critical, :high, :medium, :low, :info])
    field(:status, Ecto.Enum, values: [:open, :acknowledged, :resolved, :dismissed])
    field(:body, :string)
    field(:external_url, :string)
    field(:file_location, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(run_id source severity status body)a
  @optional_fields ~w(external_url file_location)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(feedback_item, attrs) do
    feedback_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:source, min: 1, max: 255)
    |> validate_length(:body, min: 1)
  end
end
