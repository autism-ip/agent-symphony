defmodule SymphonyElixir.FeedbackStore do
  @moduledoc """
  Repository for feedback items and fix attempts.
  """

  import Ecto.Query
  alias SymphonyElixir.FeedbackStore.{FeedbackItem, FixAttempt}
  alias SymphonyElixir.Repo

  # -------------------------------------------------------------------
  # Feedback Items
  # -------------------------------------------------------------------

  @spec create_feedback_item(map()) :: {:ok, FeedbackItem.t()} | {:error, Ecto.Changeset.t()}
  def create_feedback_item(attrs) do
    %FeedbackItem{}
    |> FeedbackItem.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_feedback_item(integer()) :: FeedbackItem.t() | nil
  def get_feedback_item(id), do: Repo.get(FeedbackItem, id)

  @spec list_feedback_items_by_run(String.t()) :: [FeedbackItem.t()]
  def list_feedback_items_by_run(run_id) do
    FeedbackItem
    |> where([f], f.run_id == ^run_id)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  @spec list_feedback_items_by_status(atom()) :: [FeedbackItem.t()]
  def list_feedback_items_by_status(status) do
    FeedbackItem
    |> where([f], f.status == ^status)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  @spec update_feedback_item(FeedbackItem.t(), map()) ::
          {:ok, FeedbackItem.t()} | {:error, Ecto.Changeset.t()}
  def update_feedback_item(%FeedbackItem{} = item, attrs) do
    item
    |> FeedbackItem.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_feedback_item(FeedbackItem.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete_feedback_item(%FeedbackItem{} = item) do
    case Repo.delete(item) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  # -------------------------------------------------------------------
  # Fix Attempts
  # -------------------------------------------------------------------

  @spec create_fix_attempt(map()) :: {:ok, FixAttempt.t()} | {:error, Ecto.Changeset.t()}
  def create_fix_attempt(attrs) do
    %FixAttempt{}
    |> FixAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_fix_attempt(integer()) :: FixAttempt.t() | nil
  def get_fix_attempt(id), do: Repo.get(FixAttempt, id)

  @spec list_fix_attempts_by_run(String.t()) :: [FixAttempt.t()]
  def list_fix_attempts_by_run(run_id) do
    FixAttempt
    |> where([fa], fa.run_id == ^run_id)
    |> order_by([fa], asc: fa.attempt_number)
    |> Repo.all()
  end

  @spec next_attempt_number(String.t()) :: integer()
  def next_attempt_number(run_id) do
    case FixAttempt
         |> where([fa], fa.run_id == ^run_id)
         |> select([fa], max(fa.attempt_number))
         |> Repo.one() do
      nil -> 1
      max_number -> max_number + 1
    end
  end

  @spec update_fix_attempt(FixAttempt.t(), map()) ::
          {:ok, FixAttempt.t()} | {:error, Ecto.Changeset.t()}
  def update_fix_attempt(%FixAttempt{} = attempt, attrs) do
    attempt
    |> FixAttempt.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_fix_attempt(FixAttempt.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete_fix_attempt(%FixAttempt{} = attempt) do
    case Repo.delete(attempt) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
