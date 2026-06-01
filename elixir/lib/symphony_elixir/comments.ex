# [INPUT]: 依赖 SymphonyElixir.Comments.{GitHubComment, LinearComment}，依赖 SymphonyElixir.Tracker
# [OUTPUT]: 对外提供 post_linear_comment/2、post_github_comment/2、build_run_info/1
# [POS]: symphony_elixir 的评论编排模块，被 Orchestrator 在 PR 创建后调用
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

defmodule SymphonyElixir.Comments do
  @moduledoc """
  Orchestrates comment posting for Linear issues and GitHub PRs.

  Handles duplicate comment prevention via run_id markers.
  """

  alias SymphonyElixir.Comments.{GitHubComment, LinearComment}
  alias SymphonyElixir.Tracker

  @type run_info :: %{
          run_id: String.t(),
          issue_identifier: String.t(),
          pr_url: String.t() | nil,
          runner_info: map(),
          changed_files: [String.t()],
          validation_status: map(),
          risks: [String.t()],
          artifacts: [map()],
          timestamp: DateTime.t()
        }

  @doc """
  Posts a Linear issue comment when a PR is opened.
  """
  @spec post_linear_comment(String.t(), run_info()) :: :ok | {:error, term()}
  def post_linear_comment(issue_id, %{} = run_info) do
    body = LinearComment.render(run_info)

    case check_duplicate_comment(issue_id, run_info.run_id) do
      {:ok, :duplicate} -> :ok
      {:ok, :new} -> Tracker.create_comment(issue_id, body)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Posts a GitHub PR summary comment.
  """
  @spec post_github_comment(String.t(), run_info()) :: :ok | {:error, term()}
  def post_github_comment(pr_url, %{} = run_info) do
    body = GitHubComment.render(run_info)

    case check_duplicate_github_comment(pr_url, run_info.run_id) do
      {:ok, :duplicate} -> :ok
      {:ok, :new} -> GitHubComment.post_comment(pr_url, body)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a run_info map from agent run metadata.
  """
  @spec build_run_info(map()) :: run_info()
  def build_run_info(%{} = metadata) do
    %{
      run_id: Map.get(metadata, :run_id, generate_run_id()),
      issue_identifier: Map.get(metadata, :issue_identifier),
      pr_url: Map.get(metadata, :pr_url),
      runner_info: Map.get(metadata, :runner_info, %{}),
      changed_files: Map.get(metadata, :changed_files, []),
      validation_status: Map.get(metadata, :validation_status, %{}),
      risks: Map.get(metadata, :risks, []),
      artifacts: Map.get(metadata, :artifacts, []),
      timestamp: DateTime.utc_now()
    }
  end

  defp check_duplicate_comment(issue_id, run_id) do
    marker = "<!-- symphony-run-#{run_id} -->"

    case Tracker.fetch_comments(issue_id) do
      {:ok, comments} ->
        if Enum.any?(comments, &String.contains?(&1.body, marker)) do
          {:ok, :duplicate}
        else
          {:ok, :new}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_duplicate_github_comment(pr_url, run_id) do
    marker = "<!-- symphony-run-#{run_id} -->"

    case GitHubComment.fetch_comments(pr_url) do
      {:ok, comments} ->
        if Enum.any?(comments, &String.contains?(&1.body, marker)) do
          {:ok, :duplicate}
        else
          {:ok, :new}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
