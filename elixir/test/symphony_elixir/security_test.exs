defmodule SymphonyElixir.SecurityTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ArtifactStore
  alias SymphonyElixir.Config.Schema

  # ================================================================
  # Config.Schema — command injection prevention
  # ================================================================

  describe "Config.Schema.parse/1 — command injection prevention" do
    test "rejects command containing semicolon" do
      config = codex_config("codex; rm -rf /")
      assert {:error, :invalid_command} = Schema.parse(config)
    end

    test "rejects command containing pipe" do
      config = codex_config("codex | cat /etc/passwd")
      assert {:error, :invalid_command} = Schema.parse(config)
    end

    test "rejects command containing ampersand" do
      config = codex_config("codex && echo pwned")
      assert {:error, :invalid_command} = Schema.parse(config)
    end

    test "rejects command containing backtick" do
      config = codex_config("codex `whoami`")
      assert {:error, :invalid_command} = Schema.parse(config)
    end
  end

  # ================================================================
  # ArtifactStore — path traversal prevention
  # ================================================================

  describe "ArtifactStore.save/3 — path traversal prevention" do
    test "rejects artifact path containing dot-dot traversal" do
      workspace = make_workspace()
      artifact = file_artifact("../../../etc/passwd", "root:x:0:0:root:/root:/bin/bash\n")

      assert {:error, {:invalid_artifact_path, "../../../etc/passwd"}} =
               ArtifactStore.save(workspace, "ISSUE-1", [artifact])
    after
      cleanup_workspace()
    end
  end

  # ================================================================
  # ArtifactStore — executable file type rejection
  # ================================================================

  describe "ArtifactStore.save/3 — executable file type rejection" do
    test "rejects .sh extension" do
      workspace = make_workspace()
      artifact = file_artifact("script.sh", "#!/bin/bash\necho hello\n")

      assert {:error, {:forbidden_file_type, ".sh"}} =
               ArtifactStore.save(workspace, "ISSUE-1", [artifact])
    after
      cleanup_workspace()
    end

    test "rejects .exe extension" do
      workspace = make_workspace()
      artifact = file_artifact("payload.exe", "MZ\x90\x00")

      assert {:error, {:forbidden_file_type, ".exe"}} =
               ArtifactStore.save(workspace, "ISSUE-1", [artifact])
    after
      cleanup_workspace()
    end

    test "rejects .bat extension" do
      workspace = make_workspace()
      artifact = file_artifact("run.bat", "@echo off\necho hello\n")

      assert {:error, {:forbidden_file_type, ".bat"}} =
               ArtifactStore.save(workspace, "ISSUE-1", [artifact])
    after
      cleanup_workspace()
    end
  end

  # ================================================================
  # ArtifactStore — content size limit
  # ================================================================

  describe "ArtifactStore.save/3 — content size limit" do
    test "rejects content exceeding 1 MB" do
      workspace = make_workspace()
      oversized = String.duplicate("x", 1_048_577)
      artifact = file_artifact("large.txt", oversized)

      assert {:error, {:artifact_too_large, 1_048_576}} =
               ArtifactStore.save(workspace, "ISSUE-1", [artifact])
    after
      cleanup_workspace()
    end
  end

  # ================================================================
  # Helpers
  # ================================================================

  defp codex_config(command) do
    %{
      "codex" => %{
        "command" => command
      }
    }
  end

  defp file_artifact(path, content) do
    %{type: :file, path: path, content: content}
  end

  @tmp_prefix "symphony-security-test-"

  defp make_workspace do
    path = Path.join(System.tmp_dir!(), @tmp_prefix <> "#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    Process.put(:security_test_workspace, path)
    path
  end

  defp cleanup_workspace do
    case Process.get(:security_test_workspace) do
      nil -> :ok
      path -> File.rm_rf(path)
    end
  end
end
