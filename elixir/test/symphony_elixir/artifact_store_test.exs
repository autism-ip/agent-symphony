defmodule SymphonyElixir.ArtifactStoreTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.ArtifactStore

  # ------------------------------------------------------------------
  # :file artifact — writes content to workspace/.symphony/artifacts/<path>
  # ------------------------------------------------------------------

  test "file artifact writes to workspace/.symphony/artifacts/<path>" do
    workspace = unique_workspace("file-artifact")

    try do
      File.mkdir_p!(workspace)

      artifacts = [
        %{type: :file, path: "src/main.ex", content: "defmodule Main do\nend\n"}
      ]

      assert :ok = ArtifactStore.save(workspace, "ISSUE-1", artifacts)

      expected_path = Path.join([workspace, ".symphony", "artifacts", "src", "main.ex"])
      assert File.exists?(expected_path)
      assert File.read!(expected_path) == "defmodule Main do\nend\n"
    after
      File.rm_rf(workspace)
    end
  end

  # ------------------------------------------------------------------
  # :comment artifact — posts content as tracker comment
  # ------------------------------------------------------------------

  test "comment artifact calls Tracker.create_comment with issue_id and content" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])

    workspace = unique_workspace("comment-artifact")

    try do
      File.mkdir_p!(workspace)

      artifacts = [
        %{type: :comment, content: "Summary of changes"}
      ]

      assert :ok = ArtifactStore.save(workspace, "abc-123", artifacts)

      assert_received {:memory_tracker_comment, "abc-123", "Summary of changes"}
    after
      File.rm_rf(workspace)
      Application.delete_env(:symphony_elixir, :memory_tracker_recipient)
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)
    end
  end

  # ------------------------------------------------------------------
  # Nested path creation — e.g. src/lib/main.ex
  # ------------------------------------------------------------------

  test "file artifact creates nested directories for deep paths" do
    workspace = unique_workspace("nested-artifact")

    try do
      File.mkdir_p!(workspace)

      artifacts = [
        %{type: :file, path: "src/lib/deep/nested/main.ex", content: "defmodule Deep.Main do\nend\n"}
      ]

      assert :ok = ArtifactStore.save(workspace, "ISSUE-2", artifacts)

      expected_path =
        Path.join([
          workspace,
          ".symphony",
          "artifacts",
          "src",
          "lib",
          "deep",
          "nested",
          "main.ex"
        ])

      assert File.exists?(expected_path)
      assert File.read!(expected_path) == "defmodule Deep.Main do\nend\n"
    after
      File.rm_rf(workspace)
    end
  end

  # ------------------------------------------------------------------
  # Mixed artifact batch — file + comment in same call
  # ------------------------------------------------------------------

  test "mixed artifact list persists file and posts comment" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())
    Application.put_env(:symphony_elixir, :memory_tracker_issues, [])

    workspace = unique_workspace("mixed-artifact")

    try do
      File.mkdir_p!(workspace)

      artifacts = [
        %{type: :file, path: "lib/app.ex", content: "defmodule App do\nend\n"},
        %{type: :comment, content: "Created App module"}
      ]

      assert :ok = ArtifactStore.save(workspace, "ISSUE-3", artifacts)

      # Verify file artifact
      expected_file = Path.join([workspace, ".symphony", "artifacts", "lib", "app.ex"])
      assert File.exists?(expected_file)
      assert File.read!(expected_file) == "defmodule App do\nend\n"

      # Verify comment artifact
      assert_received {:memory_tracker_comment, "ISSUE-3", "Created App module"}
    after
      File.rm_rf(workspace)
      Application.delete_env(:symphony_elixir, :memory_tracker_recipient)
      Application.delete_env(:symphony_elixir, :memory_tracker_issues)
    end
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp unique_workspace(prefix) do
    Path.join(
      System.tmp_dir!(),
      "symphony-elixir-artifact-store-#{prefix}-#{System.unique_integer([:positive])}"
    )
  end
end
