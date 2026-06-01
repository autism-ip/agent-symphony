defmodule SymphonyElixir.Comments.LinearComment do
  @moduledoc """
  Renders Linear issue comments for agent run summaries.
  """

  alias SymphonyElixir.Comments.Templates

  @spec render(map()) :: String.t()
  def render(%{} = run_info) do
    """
    <!-- symphony-run-#{run_info.run_id} -->
    ## Symphony Agent Run Summary

    **Run ID:** #{run_info.run_id}
    **Timestamp:** #{Templates.format_timestamp(run_info.timestamp)}

    #{render_pr_link(run_info.pr_url)}

    ### Runner Information
    #{Templates.render_runner_info(run_info.runner_info)}

    ### Changed Files
    #{Templates.render_changed_files(run_info.changed_files)}

    ### Validation Status
    #{Templates.render_validation_status(run_info.validation_status)}

    ### Risks
    #{Templates.render_risks(run_info.risks)}

    ### Artifacts
    #{Templates.render_artifacts(run_info.artifacts)}
    """
  end

  defp render_pr_link(nil), do: "**PR:** Not yet created"
  defp render_pr_link(pr_url) when is_binary(pr_url), do: "**PR:** [#{pr_url}](#{pr_url})"
  defp render_pr_link(_), do: "**PR:** Not yet created"
end
