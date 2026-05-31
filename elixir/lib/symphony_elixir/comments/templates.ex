defmodule SymphonyElixir.Comments.Templates do
  @moduledoc """
  Shared rendering helpers for comment formatting.
  """

  @spec render_runner_info(map()) :: String.t()
  def render_runner_info(%{} = runner_info) when map_size(runner_info) > 0 do
    Enum.map_join(runner_info, "\n", fn {key, value} -> "- **#{format_key(key)}:** #{value}" end)
  end

  def render_runner_info(_), do: "- No runner information available"

  @spec render_changed_files([String.t()]) :: String.t()
  def render_changed_files([]), do: "- No files changed"

  def render_changed_files(files) when is_list(files) do
    Enum.map_join(files, "\n", fn file -> "- `#{file}`" end)
  end

  def render_changed_files(_), do: "- No files changed"

  @spec render_validation_status(map()) :: String.t()
  def render_validation_status(%{} = status) when map_size(status) > 0 do
    Enum.map_join(status, "\n", fn {key, value} -> "- **#{format_key(key)}:** #{format_status(value)}" end)
  end

  def render_validation_status(_), do: "- No validation status available"

  @spec render_risks([String.t()]) :: String.t()
  def render_risks([]), do: "- No risks identified"

  def render_risks(risks) when is_list(risks) do
    Enum.map_join(risks, "\n", fn risk -> "- #{risk}" end)
  end

  def render_risks(_), do: "- No risks identified"

  @spec render_artifacts([map()]) :: String.t()
  def render_artifacts([]), do: "- No artifacts"

  def render_artifacts(artifacts) when is_list(artifacts) do
    Enum.map_join(artifacts, "\n", fn artifact ->
      name = Map.get(artifact, :name, "Unknown")
      url = Map.get(artifact, :url, "#")
      "- [#{name}](#{url})"
    end)
  end

  def render_artifacts(_), do: "- No artifacts"

  @spec format_timestamp(DateTime.t()) :: String.t()
  def format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_timestamp(_), do: "Unknown"

  @spec format_key(atom() | String.t()) :: String.t()
  def format_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  def format_key(key) when is_binary(key) do
    key |> String.replace("_", " ") |> String.capitalize()
  end

  @spec format_status(boolean() | String.t() | term()) :: String.t()
  def format_status(true), do: "Passed"
  def format_status(false), do: "Failed"
  def format_status(value), do: "#{value}"
end
