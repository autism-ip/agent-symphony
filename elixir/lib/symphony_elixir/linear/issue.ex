defmodule SymphonyElixir.Linear.Issue do
  @moduledoc """
  Normalized Linear issue representation used by the orchestrator.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :assignee_id,
    :delivery_branch,
    :delivery_commit_sha,
    :delivery_pr_number,
    :delivery_pr_url,
    :delivery_pr_title,
    blocked_by: [],
    labels: [],
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          delivery_branch: String.t() | nil,
          delivery_commit_sha: String.t() | nil,
          delivery_pr_number: integer() | nil,
          delivery_pr_url: String.t() | nil,
          delivery_pr_title: String.t() | nil,
          labels: [String.t()],
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}) do
    labels
  end

  @doc """
  Apply delivery metadata from a successful GitHub delivery run.
  """
  @spec apply_delivery(t(), map()) :: t()
  def apply_delivery(%__MODULE__{} = issue, delivery) when is_map(delivery) do
    %{
      issue
      | delivery_branch: Map.get(delivery, :branch),
        delivery_commit_sha: Map.get(delivery, :commit_sha),
        delivery_pr_number: Map.get(delivery, :pr_number),
        delivery_pr_url: Map.get(delivery, :pr_url),
        delivery_pr_title: Map.get(delivery, :pr_title)
    }
  end
end
