defmodule SymphonyElixir.ArtifactStore do
  @moduledoc """
  Persists parsed artifacts to their destinations.

  Artifact types:
    :file    — writes content to workspace/.symphony/artifacts/<path>
    :comment — posts content as a tracker comment on the issue
  """

  alias SymphonyElixir.Tracker

  @type artifact :: %{type: :file | :comment, path: String.t() | nil, content: String.t()}

  @max_content_bytes 1_048_576
  @forbidden_extensions ~w(.sh .exe .bat .cmd)

  @spec save(String.t(), String.t(), [artifact()]) :: :ok | {:error, term()}
  def save(workspace, issue_id, artifacts) when is_list(artifacts) do
    Enum.reduce_while(artifacts, :ok, fn artifact, :ok ->
      case validate_and_save(workspace, issue_id, artifact) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  # -----------------------------------------------------------------------
  # Validation & persistence
  # -----------------------------------------------------------------------

  defp validate_and_save(workspace, _issue_id, %{type: :file, path: path, content: content}) do
    with :ok <- validate_path(path),
         :ok <- validate_extension(path),
         :ok <- validate_size(content) do
      write_file(workspace, path, content)
    end
  end

  defp validate_and_save(_workspace, issue_id, %{type: :comment, content: content}) do
    Tracker.create_comment(issue_id, content)
  end

  defp validate_path(path) do
    if String.contains?(path, "..") do
      {:error, {:invalid_artifact_path, path}}
    else
      :ok
    end
  end

  defp validate_extension(path) do
    ext = path |> Path.extname() |> String.downcase()

    if ext in @forbidden_extensions do
      {:error, {:forbidden_file_type, ext}}
    else
      :ok
    end
  end

  defp validate_size(content) do
    if byte_size(content) > @max_content_bytes do
      {:error, {:artifact_too_large, @max_content_bytes}}
    else
      :ok
    end
  end

  defp write_file(workspace, path, content) do
    dest = Path.join([workspace, ".symphony", "artifacts", path])
    dest |> Path.dirname() |> File.mkdir_p!()
    File.write!(dest, content)
    :ok
  end
end
