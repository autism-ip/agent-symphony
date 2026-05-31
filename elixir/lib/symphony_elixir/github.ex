defmodule SymphonyElixir.GitHub do
  @moduledoc """
  GitHub PR detection and feedback polling via `gh` CLI.

  Provides functions to find open PRs for branches, fetch unresolved
  reviewer comments, and check PR merge/readiness status. Used by the
  orchestrator to detect when a PR has actionable feedback that requires
  a follow-up agent run.
  """

  require Logger

  @type pr_info :: %{
          url: String.t(),
          number: integer(),
          state: String.t(),
          mergeable: String.t(),
          status_check_rollup: String.t(),
          merged: boolean()
        }

  @type pr_comment :: %{
          id: integer(),
          body: String.t(),
          author: String.t(),
          path: String.t() | nil,
          line: integer() | nil,
          created_at: String.t()
        }

  # -------------------------------------------------------------------
  # PR discovery
  # -------------------------------------------------------------------

  @doc """
  Find an open PR for the given branch in the repository.
  Returns `{:ok, pr_info()}` or `{:ok, :no_pr}`.
  """
  @spec find_open_pr(String.t(), String.t()) :: {:ok, pr_info() | :no_pr} | {:error, term()}
  def find_open_pr(repo, branch) when is_binary(repo) and is_binary(branch) do
    case gh([
           "pr", "list",
           "--repo", repo,
           "--head", branch,
           "--state", "open",
           "--json", "number,url,state,mergeable,statusCheckRollup",
           "--limit", "1"
         ]) do
      {:ok, output} -> parse_pr_list(output)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the current status of a specific PR.
  Returns `{:ok, pr_info()}` or `{:error, term()}`.
  """
  @spec poll_pr_status(String.t(), integer()) :: {:ok, pr_info()} | {:error, term()}
  def poll_pr_status(repo, pr_number) when is_binary(repo) and is_integer(pr_number) do
    case gh([
           "pr", "view", Integer.to_string(pr_number),
           "--repo", repo,
           "--json", "url,state,mergeable,statusCheckRollup,merged,number"
         ]) do
      {:ok, output} -> parse_pr_view(output)
      {:error, reason} -> {:error, reason}
    end
  end

  # -------------------------------------------------------------------
  # PR feedback detection
  # -------------------------------------------------------------------

  @doc """
  Fetch unresolved review comments on a PR.

  Returns `{:ok, [pr_comment()]}` or `{:error, term()}`.
  Only returns top-level review comments (not resolved threads).
  """
  @spec fetch_pr_comments(String.t(), integer()) :: {:ok, [pr_comment()]} | {:error, term()}
  def fetch_pr_comments(repo, pr_number) when is_binary(repo) and is_integer(pr_number) do
    case gh([
           "api",
           "repos/#{repo}/pulls/#{Integer.to_string(pr_number)}/comments",
           "--jq", ".[] | {id: .id, body: .body, author: .user.login, path: .path, line: .line, created_at: .created_at}"
         ]) do
      {:ok, output} -> parse_pr_comments(output)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch PR review summaries (approve/request_changes/comment).

  Returns `{:ok, [map()]}` or `{:error, term()}`.
  """
  @spec fetch_pr_reviews(String.t(), integer()) :: {:ok, [map()]} | {:error, term()}
  def fetch_pr_reviews(repo, pr_number) when is_binary(repo) and is_integer(pr_number) do
    case gh([
           "pr", "view", Integer.to_string(pr_number),
           "--repo", repo,
           "--json", "reviews"
         ]) do
      {:ok, output} -> parse_pr_reviews(output)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a PR is ready (merged or checks pass and mergeable).
  """
  @spec ready?(pr_info()) :: boolean()
  def ready?(%{merged: true}), do: true
  def ready?(%{state: "MERGED"}), do: true
  def ready?(%{state: "OPEN", mergeable: "CONFLICTING"}), do: false
  def ready?(%{state: "OPEN", status_check_rollup: "SUCCESS"}), do: true
  def ready?(_pr), do: false

  @doc """
  Check whether a PR has actionable reviewer feedback.

  Returns `true` if there are unresolved review comments or
  requesting-changes reviews.
  """
  @spec has_actionable_feedback?(String.t(), integer()) :: boolean()
  def has_actionable_feedback?(repo, pr_number) do
    case fetch_pr_comments(repo, pr_number) do
      {:ok, comments} when comments != [] ->
        true

      _ ->
        case fetch_pr_reviews(repo, pr_number) do
          {:ok, reviews} ->
            Enum.any?(reviews, fn r -> Map.get(r, :state) == "CHANGES_REQUESTED" end)

          _ ->
            false
        end
    end
  end

  @doc """
  Parse a PR URL to extract `{:ok, {owner/repo, pr_number}}` or `:error`.

  Supports formats:
  - `https://github.com/owner/repo/pull/123`
  - `github.com/owner/repo/pull/123`
  """
  @spec parse_pr_url(String.t()) :: {:ok, {String.t(), integer()}} | :error
  def parse_pr_url(url) when is_binary(url) do
    case Regex.run(~r{github\.com/([^/]+/[^/]+)/pull/(\d+)}, url) do
      [_, repo, number_str] ->
        case Integer.parse(number_str) do
          {number, ""} -> {:ok, {repo, number}}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse_pr_url(_), do: :error

  # -------------------------------------------------------------------
  # Private — parsers
  # -------------------------------------------------------------------

  defp parse_pr_list(output) do
    case Jason.decode(output) do
      {:ok, [%{"number" => number} = pr | _]} ->
        {:ok,
         %{
           url: pr["url"] || "",
           number: number,
           state: pr["state"] || "OPEN",
           mergeable: pr["mergeable"] || "UNKNOWN",
           status_check_rollup: normalize_check_rollup(pr["statusCheckRollup"]),
           merged: false
         }}

      {:ok, []} ->
        {:ok, :no_pr}

      {:ok, _other} ->
        {:ok, :no_pr}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  defp parse_pr_view(output) do
    case Jason.decode(output) do
      {:ok, pr} when is_map(pr) ->
        {:ok,
         %{
           url: pr["url"] || "",
           number: pr["number"],
           state: pr["state"] || "OPEN",
           mergeable: pr["mergeable"] || "UNKNOWN",
           status_check_rollup: normalize_check_rollup(pr["statusCheckRollup"]),
           merged: pr["merged"] || false
         }}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  defp parse_pr_comments(output) do
    comments =
      output
      |> String.trim()
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, comment} when is_map(comment) ->
            [%{
               id: comment["id"],
               body: comment["body"] || "",
               author: comment["author"] || "unknown",
               path: comment["path"],
               line: comment["line"],
               created_at: comment["created_at"]
             }]

          _ ->
            []
        end
      end)

    {:ok, comments}
  end

  defp parse_pr_reviews(output) do
    case Jason.decode(output) do
      {:ok, %{"reviews" => reviews}} when is_list(reviews) ->
        parsed =
          Enum.map(reviews, fn r ->
            %{
              state: r["state"] || "COMMENTED",
              author: get_in(r, ["author", "login"]) || "unknown",
              body: r["body"] || ""
            }
          end)

        {:ok, parsed}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  # -------------------------------------------------------------------
  # Private — check rollup normalization
  # -------------------------------------------------------------------

  defp normalize_check_rollup(checks) when is_list(checks) do
    conclusions = Enum.map(checks, &check_conclusion/1)

    cond do
      conclusions == [] -> "PENDING"
      Enum.any?(conclusions, &(&1 == "FAILURE")) -> "FAILURE"
      Enum.all?(conclusions, &(&1 == "SUCCESS")) -> "SUCCESS"
      true -> "PENDING"
    end
  end

  defp normalize_check_rollup(%{"state" => state}) when is_binary(state), do: String.upcase(state)
  defp normalize_check_rollup(state) when is_binary(state), do: state
  defp normalize_check_rollup(_), do: "PENDING"

  defp check_conclusion(%{"conclusion" => conclusion}) when is_binary(conclusion) do
    String.upcase(conclusion)
  end

  defp check_conclusion(%{"state" => state}) when is_binary(state) do
    String.upcase(state)
  end

  defp check_conclusion(%{"status" => "COMPLETED", "conclusion" => nil}), do: "PENDING"
  defp check_conclusion(%{"status" => _}), do: "PENDING"
  defp check_conclusion(_), do: "PENDING"

  # -------------------------------------------------------------------
  # Private — gh CLI wrapper
  # -------------------------------------------------------------------

  defp gh(args) do
    case System.find_executable("gh") do
      nil ->
        {:error, :gh_not_found}

      path ->
        case System.cmd(path, args, stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, output}

          {output, status} ->
            Logger.warning("gh command failed: exit=#{status} args=#{inspect(args)} output=#{String.trim(output)}")
            {:error, {:gh_failed, status, String.trim(output)}}
        end
    end
  end
end
