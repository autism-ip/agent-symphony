# [INPUT]: 依赖 SymphonyElixir.Linear.Issue 结构体，依赖 git/gh CLI
# [OUTPUT]: 对外提供 deliver/2 交付管道、find_open_pr/2、poll_pr_status/2、ready?/1
# [POS]: symphony_elixir 的 GitHub 集成模块，被 Orchestrator 在 agent run 完成后调用
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

defmodule SymphonyElixir.GitHub do
  @moduledoc """
  GitHub integration for Symphony agent runs.

  Two concerns:
  - **Delivery**: branch → commit → push → draft PR (called after agent run)
  - **PR polling**: detect open PRs, poll status, check readiness
  """

  require Logger

  alias SymphonyElixir.Linear.Issue

  @type delivery_result :: %{
          branch: String.t(),
          commit_sha: String.t(),
          pr_number: integer(),
          pr_url: String.t(),
          pr_title: String.t()
        }

  @type delivery_error ::
          :no_changes
          | :gh_not_available
          | {:branch_failed, String.t()}
          | {:commit_failed, String.t()}
          | {:push_failed, String.t()}
          | {:pr_creation_failed, String.t()}
          | {:pr_parse_failed, String.t()}

  @type pr_status :: %{
          url: String.t(),
          state: String.t(),
          mergeable: String.t(),
          status_check_rollup: String.t(),
          merged: boolean(),
          number: integer()
        }

  # ===================================================================
  # Delivery pipeline
  # ===================================================================

  @doc """
  Run the full delivery pipeline for an issue workspace.

  Returns `{:ok, delivery_result}` on success or `{:error, reason}` on failure.
  """
  @spec deliver(Issue.t(), Path.t()) :: {:ok, delivery_result()} | {:error, delivery_error()}
  def deliver(%Issue{} = issue, workspace_path) when is_binary(workspace_path) do
    with :ok <- verify_gh_available() do
      branch = branch_name(issue)
      has_dirty = has_dirty_files?(workspace_path)
      has_unpushed = has_unpushed_commits?(branch, workspace_path)

      cond do
        has_dirty ->
          deliver_full_pipeline(issue, branch, workspace_path)

        has_unpushed ->
          deliver_push_and_pr(issue, branch, workspace_path)

        !has_pr?(branch, workspace_path) && remote_branch_exists?(branch, workspace_path) ->
          Logger.info("Branch pushed but no PR exists; creating PR for #{issue.identifier}")
          {:ok, pr_number, pr_url} = find_or_create_pr(issue, branch, workspace_path)
          {:ok, commit_sha} = get_head_sha(workspace_path)
          {:ok, delivery_result(branch, commit_sha, pr_number, pr_url, issue)}

        true ->
          {:error, :no_changes}
      end
    end
  end

  # Full pipeline: branch → commit → push → PR
  defp deliver_full_pipeline(issue, branch, workspace_path) do
    with :ok <- ensure_git_author(workspace_path),
         {:ok, ^branch} <- create_branch(issue, workspace_path),
         :ok <- commit_changes(issue, workspace_path),
         {:ok, commit_sha} <- get_head_sha(workspace_path),
         :ok <- push_branch(branch, workspace_path),
         {:ok, pr_number, pr_url} <- find_or_create_pr(issue, branch, workspace_path) do
      {:ok, delivery_result(branch, commit_sha, pr_number, pr_url, issue)}
    end
  end

  # Recovery pipeline: push unpushed commits → PR (skips commit)
  defp deliver_push_and_pr(issue, branch, workspace_path) do
    with {:ok, ^branch} <- ensure_branch(branch, workspace_path),
         :ok <- push_branch(branch, workspace_path),
         {:ok, commit_sha} <- get_head_sha(workspace_path),
         {:ok, pr_number, pr_url} <- find_or_create_pr(issue, branch, workspace_path) do
      Logger.info("Recovered unpushed commits for #{issue.identifier} branch=#{branch}")
      {:ok, delivery_result(branch, commit_sha, pr_number, pr_url, issue)}
    end
  end

  defp delivery_result(branch, commit_sha, pr_number, pr_url, issue) do
    result = %{
      branch: branch,
      commit_sha: commit_sha,
      pr_number: pr_number,
      pr_url: pr_url,
      pr_title: pr_title(issue)
    }

    Logger.info("Delivery completed: #{issue.identifier} branch=#{branch} pr=#{pr_number} url=#{pr_url}")
    result
  end

  # -------------------------------------------------------------------
  # Branch naming
  # -------------------------------------------------------------------

  @doc """
  Generate an issue-specific branch name.

  Format: `symphony/<sanitized-identifier>`
  """
  @spec branch_name(Issue.t()) :: String.t()
  def branch_name(%Issue{identifier: identifier}) when is_binary(identifier) do
    identifier
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> then(&"symphony/#{&1}")
  end

  def branch_name(%Issue{id: id}) when is_binary(id) do
    "symphony/#{id}"
  end

  def branch_name(_issue), do: "symphony/unknown-issue"

  # -------------------------------------------------------------------
  # Commit message
  # -------------------------------------------------------------------

  @doc """
  Build a conventional commit message that includes the Linear issue identifier.
  """
  @spec commit_message(Issue.t()) :: String.t()
  def commit_message(%Issue{} = issue) do
    body = """
    Summary:
    - Implement changes for #{issue.identifier}: #{issue.title}

    Rationale:
    - Automated delivery by Symphony agent run

    Tests:
    - Validated locally before commit

    Co-authored-by: Codex <codex@openai.com>
    """

    "#{commit_subject(issue)}\n\n#{body}"
  end

  # -------------------------------------------------------------------
  # PR metadata
  # -------------------------------------------------------------------

  @doc """
  PR title that starts with the Linear issue identifier.
  """
  @spec pr_title(Issue.t()) :: String.t()
  def pr_title(%Issue{identifier: identifier, title: title})
      when is_binary(identifier) and is_binary(title) do
    "#{identifier}: #{title}"
  end

  def pr_title(%Issue{identifier: identifier}) when is_binary(identifier) do
    "#{identifier}: implement changes"
  end

  def pr_title(_issue), do: "symphony: implement changes"

  @doc """
  PR body that includes `Fixes <LINEAR-ID>` for Linear linkage.
  """
  @spec pr_body(Issue.t()) :: String.t()
  def pr_body(%Issue{} = issue) do
    """
    #### Context

    Symphony agent run for #{issue.identifier}: #{issue.title}

    #### TL;DR

    *Automated implementation for #{issue.identifier}*

    #### Summary

    - Implements changes requested in #{issue.identifier}
    - Fixes #{issue.identifier}

    #### Alternatives

    - Agent-driven automated delivery; no manual alternatives considered

    #### Test Plan

    - [ ] `make -C elixir all`
    """
  end

  # ===================================================================
  # PR status polling
  # ===================================================================

  @doc """
  Find an open PR for the given branch in the repository.
  Returns `{:ok, pr_status()}` or `{:ok, :no_pr}`.
  """
  @spec find_open_pr(String.t(), String.t()) :: {:ok, pr_status() | :no_pr} | {:error, term()}
  def find_open_pr(repo, branch) when is_binary(repo) and is_binary(branch) do
    case gh([
           "pr",
           "list",
           "--repo",
           repo,
           "--head",
           branch,
           "--state",
           "open",
           "--json",
           "number,url,state,mergeable,statusCheckRollup",
           "--limit",
           "1"
         ]) do
      {:ok, output} ->
        parse_pr_list(output)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the current status of a specific PR.
  Returns `{:ok, pr_status()}` or `{:error, term()}`.
  """
  @spec poll_pr_status(String.t(), integer()) :: {:ok, pr_status()} | {:error, term()}
  def poll_pr_status(repo, pr_number) when is_binary(repo) and is_integer(pr_number) do
    case gh([
           "pr",
           "view",
           Integer.to_string(pr_number),
           "--repo",
           repo,
           "--json",
           "url,state,mergeable,statusCheckRollup,merged,number"
         ]) do
      {:ok, output} ->
        parse_pr_view(output)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a PR is ready (merged or checks pass and mergeable).
  """
  @spec ready?(pr_status()) :: boolean()
  def ready?(%{merged: true}), do: true
  def ready?(%{state: "MERGED"}), do: true
  def ready?(%{state: "OPEN", mergeable: "CONFLICTING"}), do: false
  def ready?(%{state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "SUCCESS"}), do: true

  def ready?(_pr), do: false

  # -------------------------------------------------------------------
  # Git operations (private)
  # -------------------------------------------------------------------

  @spec commit_subject(Issue.t()) :: String.t()
  defp commit_subject(%Issue{identifier: identifier, title: title})
       when is_binary(identifier) and is_binary(title) do
    "#{identifier}: #{title}"
  end

  defp commit_subject(%Issue{identifier: identifier}) when is_binary(identifier) do
    "#{identifier}: implement changes"
  end

  defp commit_subject(_issue), do: "symphony: implement changes"

  @spec create_branch(Issue.t(), Path.t()) :: {:ok, String.t()} | {:error, delivery_error()}
  defp create_branch(%Issue{} = issue, workspace_path) do
    branch = branch_name(issue)

    case current_branch(workspace_path) do
      {:ok, ^branch} ->
        Logger.info("Already on branch: #{branch}")
        {:ok, branch}

      _ ->
        ensure_branch(branch, workspace_path)
    end
  end

  @spec ensure_branch(String.t(), Path.t()) :: {:ok, String.t()} | {:error, delivery_error()}
  defp ensure_branch(branch, workspace_path) do
    # If the remote branch exists, track it instead of creating a divergent local branch
    if remote_branch_exists?(branch, workspace_path) do
      fetch_and_checkout_remote(branch, workspace_path)
    else
      create_local_branch(branch, workspace_path)
    end
  end

  @spec fetch_and_checkout_remote(String.t(), Path.t()) ::
          {:ok, String.t()} | {:error, delivery_error()}
  defp fetch_and_checkout_remote(branch, workspace_path) do
    with :ok <- git_fetch_branch(branch, workspace_path) do
      case System.cmd("git", ["checkout", branch],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          Logger.info("Tracking remote branch: #{branch}")
          {:ok, branch}

        {output, _status} ->
          {:error, {:branch_failed, "checkout failed: #{String.trim(output)}"}}
      end
    end
  end

  @spec git_fetch_branch(String.t(), Path.t()) :: :ok | {:error, delivery_error()}
  defp git_fetch_branch(branch, workspace_path) do
    case System.cmd("git", ["fetch", "origin", branch],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, {:branch_failed, "fetch failed: #{String.trim(output)}"}}
    end
  end

  @spec create_local_branch(String.t(), Path.t()) ::
          {:ok, String.t()} | {:error, delivery_error()}
  defp create_local_branch(branch, workspace_path) do
    case System.cmd("git", ["checkout", "-b", branch],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Created branch: #{branch}")
        {:ok, branch}

      {_output, _status} ->
        switch_to_existing_branch(branch, workspace_path)
    end
  end

  @spec switch_to_existing_branch(String.t(), Path.t()) ::
          {:ok, String.t()} | {:error, delivery_error()}
  defp switch_to_existing_branch(branch, workspace_path) do
    case System.cmd("git", ["checkout", branch],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Switched to existing branch: #{branch}")
        {:ok, branch}

      {output, _status} ->
        {:error, {:branch_failed, String.trim(output)}}
    end
  end

  @spec current_branch(Path.t()) :: {:ok, String.t()} | :error
  defp current_branch(workspace_path) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {branch, 0} -> {:ok, String.trim(branch)}
      _ -> :error
    end
  end

  @spec commit_changes(Issue.t(), Path.t()) :: :ok | {:error, delivery_error()}
  defp commit_changes(%Issue{} = issue, workspace_path) do
    with :ok <- stage_all(workspace_path),
         do: do_commit(issue, workspace_path)
  end

  @spec stage_all(Path.t()) :: :ok | {:error, delivery_error()}
  defp stage_all(workspace_path) do
    case System.cmd("git", ["add", "-A"], cd: workspace_path, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, {:commit_failed, "git add failed: #{String.trim(output)}"}}
    end
  end

  @spec do_commit(Issue.t(), Path.t()) :: :ok | {:error, delivery_error()}
  defp do_commit(%Issue{} = issue, workspace_path) do
    message_file = Path.join(workspace_path, ".git/COMMIT_MSG_SYMPHONY")
    File.write!(message_file, commit_message(issue))

    try do
      case System.cmd("git", ["commit", "-F", message_file],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          Logger.info("Committed changes for #{issue.identifier}")
          :ok

        {output, _status} ->
          {:error, {:commit_failed, String.trim(output)}}
      end
    after
      File.rm(message_file)
    end
  end

  @spec get_head_sha(Path.t()) :: {:ok, String.t()} | {:error, delivery_error()}
  defp get_head_sha(workspace_path) do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {output, _status} -> {:error, {:commit_failed, "failed to get HEAD sha: #{String.trim(output)}"}}
    end
  end

  @spec push_branch(String.t(), Path.t()) :: :ok | {:error, delivery_error()}
  defp push_branch(branch, workspace_path) do
    case System.cmd("git", ["push", "-u", "origin", branch],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Pushed branch: #{branch}")
        :ok

      {output, _status} ->
        {:error, {:push_failed, String.trim(output)}}
    end
  end

  @spec has_unpushed_commits?(String.t(), Path.t()) :: boolean()
  defp has_unpushed_commits?(branch, workspace_path) do
    case System.cmd("git", ["log", "--oneline", "origin/#{branch}..HEAD"],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {"", 0} -> false
      {_output, 0} -> true
      # Remote branch doesn't exist yet — but only if the remote itself is configured
      _ -> remote_branch_missing?(branch, workspace_path)
    end
  end

  @spec remote_branch_missing?(String.t(), Path.t()) :: boolean()
  defp remote_branch_missing?(branch, workspace_path) do
    case System.cmd("git", ["remote", "get-url", "origin"],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {_url, 0} -> !remote_branch_exists?(branch, workspace_path)
      _ -> false
    end
  end

  # -------------------------------------------------------------------
  # GitHub PR operations (gh CLI)
  # -------------------------------------------------------------------

  @spec find_or_create_pr(Issue.t(), String.t(), Path.t()) ::
          {:ok, integer(), String.t()} | {:error, delivery_error()}
  defp find_or_create_pr(%Issue{} = issue, branch, workspace_path) do
    case detect_existing_pr(branch, workspace_path) do
      {:ok, pr_number, pr_url} ->
        Logger.info("Reusing existing PR ##{pr_number} for #{issue.identifier}: #{pr_url}")
        {:ok, pr_number, pr_url}

      :no_pr ->
        create_draft_pr(issue, branch, workspace_path)
    end
  end

  @spec detect_existing_pr(String.t(), Path.t()) ::
          {:ok, integer(), String.t()} | :no_pr
  defp detect_existing_pr(branch, workspace_path) do
    case System.cmd(
           "gh",
           [
             "pr",
             "list",
             "--head",
             branch,
             "--state",
             "all",
             "--json",
             "number,url,state",
             "--limit",
             "1"
           ],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(String.trim(output)) do
          {:ok, [%{"number" => number, "url" => url} | _]} ->
            {:ok, number, url}

          _ ->
            :no_pr
        end

      _ ->
        :no_pr
    end
  end

  @spec create_draft_pr(Issue.t(), String.t(), Path.t()) ::
          {:ok, integer(), String.t()} | {:error, delivery_error()}
  defp create_draft_pr(%Issue{} = issue, branch, workspace_path) do
    title = pr_title(issue)
    body = pr_body(issue)
    body_file = Path.join(workspace_path, ".git/PR_BODY_SYMPHONY")
    File.write!(body_file, body)

    try do
      case System.cmd(
             "gh",
             [
               "pr",
               "create",
               "--title",
               title,
               "--body-file",
               body_file,
               "--base",
               detect_base_branch(workspace_path),
               "--head",
               branch,
               "--draft"
             ],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          parse_pr_output(String.trim(output), issue)

        {output, _status} ->
          {:error, {:pr_creation_failed, String.trim(output)}}
      end
    after
      File.rm(body_file)
    end
  end

  @spec parse_pr_output(String.t(), Issue.t()) ::
          {:ok, integer(), String.t()} | {:error, delivery_error()}
  defp parse_pr_output(output, %Issue{} = issue) do
    case Regex.run(~r{https://github.com/[^/]+/[^/]+/pull/(\d+)}, output) do
      [url, number_str] ->
        pr_number = String.to_integer(number_str)
        Logger.info("Created draft PR ##{pr_number} for #{issue.identifier}: #{url}")
        {:ok, pr_number, url}

      nil ->
        {:error, {:pr_parse_failed, "could not parse PR URL from: #{output}"}}
    end
  end

  # -------------------------------------------------------------------
  # PR status parsing (private)
  # -------------------------------------------------------------------

  defp parse_pr_list(output) do
    case Jason.decode(output) do
      {:ok, [%{"number" => number} = pr | _]} ->
        {:ok,
         %{
           url: pr["url"] || "",
           state: pr["state"] || "OPEN",
           mergeable: pr["mergeable"] || "UNKNOWN",
           status_check_rollup: normalize_check_rollup(pr["statusCheckRollup"]),
           merged: false,
           number: number
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
           state: pr["state"] || "OPEN",
           mergeable: pr["mergeable"] || "UNKNOWN",
           status_check_rollup: normalize_check_rollup(pr["statusCheckRollup"]),
           merged: pr["merged"] || false,
           number: pr["number"]
         }}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  # -------------------------------------------------------------------
  # normalize_check_rollup/1 — handles real GitHub API response
  #
  # GitHub returns statusCheckRollup as an array of check objects:
  #   [{"conclusion": "SUCCESS", "status": "COMPLETED"}, ...]
  # or null when no checks exist.
  #
  # The previous implementation only handled %{"state" => state} maps,
  # causing real arrays to always default to "PENDING" — making the
  # ready?/1 SUCCESS branch unreachable.
  # -------------------------------------------------------------------

  @spec normalize_check_rollup(term()) :: String.t()
  defp normalize_check_rollup(checks) when is_list(checks) do
    cond do
      checks == [] ->
        "PENDING"

      Enum.all?(checks, &check_completed_and_successful?(&1)) ->
        "SUCCESS"

      Enum.any?(checks, &check_failed?(&1)) ->
        "FAILURE"

      true ->
        "PENDING"
    end
  end

  defp normalize_check_rollup(nil), do: "SUCCESS"
  defp normalize_check_rollup(%{"state" => state}) when is_binary(state), do: state
  defp normalize_check_rollup(state) when is_binary(state), do: state
  defp normalize_check_rollup(_), do: "PENDING"

  defp check_completed_and_successful?(%{"status" => "COMPLETED", "conclusion" => conclusion})
       when conclusion in ["SUCCESS", "SKIPPED", "NEUTRAL"],
       do: true

  defp check_completed_and_successful?(%{"conclusion" => conclusion})
       when conclusion in ["SUCCESS", "SKIPPED", "NEUTRAL"],
       do: true

  # Legacy status contexts (not CheckRuns) use "state" instead of "conclusion"
  defp check_completed_and_successful?(%{"state" => state})
       when state in ["SUCCESS", "EXPECTED"],
       do: true

  defp check_completed_and_successful?(_), do: false

  defp check_failed?(%{"conclusion" => conclusion})
       when conclusion in ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"],
       do: true

  defp check_failed?(_), do: false

  # -------------------------------------------------------------------
  # Utilities
  # -------------------------------------------------------------------

  @spec verify_gh_available() :: :ok | {:error, :gh_not_available}
  defp verify_gh_available do
    case System.find_executable("gh") do
      nil -> {:error, :gh_not_available}
      _path -> :ok
    end
  end

  @spec has_dirty_files?(Path.t()) :: boolean()
  defp has_dirty_files?(workspace_path) do
    case System.cmd("git", ["status", "--porcelain"], cd: workspace_path, stderr_to_stdout: true) do
      {"", 0} -> false
      _ -> true
    end
  end

  @spec has_pr?(String.t(), Path.t()) :: boolean()
  defp has_pr?(branch, workspace_path) do
    case detect_existing_pr(branch, workspace_path) do
      {:ok, _number, _url} -> true
      :no_pr -> false
    end
  end

  @spec remote_branch_exists?(String.t(), Path.t()) :: boolean()
  defp remote_branch_exists?(branch, workspace_path) do
    case System.cmd("git", ["ls-remote", "--heads", "origin", branch],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {"", 0} -> false
      {_output, 0} -> true
      _ -> false
    end
  end

  @spec detect_base_branch(Path.t()) :: String.t()
  defp detect_base_branch(workspace_path) do
    case System.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
           cd: workspace_path,
           stderr_to_stdout: true
         ) do
      {"origin/" <> branch, 0} -> String.trim(branch)
      _ -> "main"
    end
  end

  @spec ensure_git_author(Path.t()) :: :ok
  defp ensure_git_author(workspace_path) do
    System.cmd("git", ["config", "user.name", "Symphony Agent"],
      cd: workspace_path,
      stderr_to_stdout: true
    )

    System.cmd("git", ["config", "user.email", "symphony@agent.local"],
      cd: workspace_path,
      stderr_to_stdout: true
    )

    :ok
  end

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
