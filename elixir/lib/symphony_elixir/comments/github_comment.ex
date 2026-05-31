defmodule SymphonyElixir.Comments.GitHubComment do
  @moduledoc """
  Renders and posts GitHub PR comments for agent run summaries.
  """

  alias SymphonyElixir.Comments.Templates

  require Logger

  @spec render(map()) :: String.t()
  def render(%{} = run_info) do
    """
    <!-- symphony-run-#{run_info.run_id} -->
    ## Symphony Agent Run Summary

    ```json
    {
      "run_id": "#{run_info.run_id}",
      "issue_identifier": "#{run_info.issue_identifier}",
      "pr_url": #{inspect(run_info.pr_url)},
      "timestamp": "#{Templates.format_timestamp(run_info.timestamp)}",
      "runner": #{inspect(run_info.runner_info)},
      "changed_files_count": #{length(run_info.changed_files)},
      "validation_passed": #{validation_passed?(run_info.validation_status)},
      "risks_count": #{length(run_info.risks)},
      "artifacts_count": #{length(run_info.artifacts)}
    }
    ```

    ### Details

    **Run ID:** #{run_info.run_id}
    **Issue:** #{run_info.issue_identifier}
    **Timestamp:** #{Templates.format_timestamp(run_info.timestamp)}

    ### Runner Information
    #{Templates.render_runner_info(run_info.runner_info)}

    ### Changed Files (#{length(run_info.changed_files)})
    #{Templates.render_changed_files(run_info.changed_files)}

    ### Validation Status
    #{Templates.render_validation_status(run_info.validation_status)}

    ### Risks (#{length(run_info.risks)})
    #{Templates.render_risks(run_info.risks)}

    ### Artifacts (#{length(run_info.artifacts)})
    #{Templates.render_artifacts(run_info.artifacts)}
    """
  end

  @spec post_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def post_comment(pr_url, body) when is_binary(pr_url) and is_binary(body) do
    case parse_pr_url(pr_url) do
      {:ok, owner, repo, pr_number} ->
        post_github_comment(owner, repo, pr_number, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_comments(String.t()) :: {:ok, [map()]} | {:error, term()}
  def fetch_comments(pr_url) when is_binary(pr_url) do
    case parse_pr_url(pr_url) do
      {:ok, owner, repo, pr_number} ->
        fetch_github_comments(owner, repo, pr_number)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec parse_pr_url(String.t()) :: {:ok, String.t(), String.t(), String.t()} | {:error, term()}
  def parse_pr_url(pr_url) when is_binary(pr_url) do
    case Regex.run(~r{https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)}, pr_url) do
      [_, owner, repo, pr_number] -> {:ok, owner, repo, pr_number}
      _ -> {:error, :invalid_pr_url}
    end
  end

  defp post_github_comment(owner, repo, pr_number, body) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/issues/#{pr_number}/comments"

    case github_request(:post, url, %{body: body}) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to post GitHub comment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_github_comments(owner, repo, pr_number) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/issues/#{pr_number}/comments"

    case github_request(:get, url, nil) do
      {:ok, response} ->
        comments = Enum.map(response, fn comment -> %{id: comment["id"], body: comment["body"]} end)
        {:ok, comments}

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub comments: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp github_request(method, url, body) do
    headers = github_headers()

    opts =
      [method: method, url: url, headers: headers, connect_options: [timeout: 30_000]]
      |> maybe_add_body(body)

    case Req.request(opts) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:github_api_error, status, response_body}}

      {:error, reason} ->
        {:error, {:github_request_error, reason}}
    end
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :json, body)

  defp github_headers do
    case System.get_env("GITHUB_TOKEN") do
      nil ->
        [{"Content-Type", "application/json"}]

      token ->
        [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"},
          {"Accept", "application/vnd.github.v3+json"}
        ]
    end
  end

  defp validation_passed?(%{} = status) do
    status
    |> Map.values()
    |> Enum.all?(fn
      true -> true
      "passed" -> true
      "success" -> true
      _ -> false
    end)
  end

  defp validation_passed?(_), do: false
end
