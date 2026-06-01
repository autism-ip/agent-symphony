defmodule SymphonyElixir.GitHubTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub
  alias SymphonyElixir.Linear.Issue

  # -------------------------------------------------------------------
  # branch_name/1
  # -------------------------------------------------------------------

  describe "branch_name/1" do
    test "generates branch from identifier" do
      issue = %Issue{identifier: "ZEN-19", title: "Test"}
      assert GitHub.branch_name(issue) == "symphony/zen-19"
    end

    test "sanitizes special characters" do
      issue = %Issue{identifier: "FOO_BAR@123", title: "Test"}
      assert GitHub.branch_name(issue) == "symphony/foo_bar-123"
    end

    test "falls back to id when identifier is nil" do
      issue = %Issue{id: "abc123", identifier: nil}
      assert GitHub.branch_name(issue) == "symphony/abc123"
    end

    test "falls back to unknown-issue when both id and identifier are nil" do
      issue = %Issue{}
      assert GitHub.branch_name(issue) == "symphony/unknown-issue"
    end

    test "lowercases identifier" do
      issue = %Issue{identifier: "ZEN-19"}
      assert GitHub.branch_name(issue) == "symphony/zen-19"
    end
  end

  # -------------------------------------------------------------------
  # commit_message/1
  # -------------------------------------------------------------------

  describe "commit_message/1" do
    test "includes identifier and title in subject" do
      issue = %Issue{identifier: "ZEN-19", title: "Implement delivery"}
      message = GitHub.commit_message(issue)
      assert String.starts_with?(message, "ZEN-19: Implement delivery")
    end

    test "includes Co-authored-by trailer" do
      issue = %Issue{identifier: "ZEN-19", title: "Test"}
      message = GitHub.commit_message(issue)
      assert message =~ "Co-authored-by: Codex <codex@openai.com>"
    end

    test "handles nil title" do
      issue = %Issue{identifier: "ZEN-19", title: nil}
      message = GitHub.commit_message(issue)
      assert String.starts_with?(message, "ZEN-19: implement changes")
    end

    test "handles nil identifier" do
      issue = %Issue{identifier: nil, title: "Test"}
      message = GitHub.commit_message(issue)
      assert String.starts_with?(message, "symphony: implement changes")
    end
  end

  # -------------------------------------------------------------------
  # pr_title/1
  # -------------------------------------------------------------------

  describe "pr_title/1" do
    test "starts with identifier" do
      issue = %Issue{identifier: "ZEN-19", title: "Implement delivery"}
      assert GitHub.pr_title(issue) == "ZEN-19: Implement delivery"
    end

    test "handles nil title" do
      issue = %Issue{identifier: "ZEN-19", title: nil}
      assert GitHub.pr_title(issue) == "ZEN-19: implement changes"
    end

    test "handles nil identifier" do
      issue = %Issue{identifier: nil, title: "Test"}
      assert GitHub.pr_title(issue) == "symphony: implement changes"
    end
  end

  # -------------------------------------------------------------------
  # pr_body/1
  # -------------------------------------------------------------------

  describe "pr_body/1" do
    test "includes Fixes keyword with identifier" do
      issue = %Issue{identifier: "ZEN-19", title: "Test"}
      body = GitHub.pr_body(issue)
      assert body =~ "Fixes ZEN-19"
    end

    test "includes test plan" do
      issue = %Issue{identifier: "ZEN-19", title: "Test"}
      body = GitHub.pr_body(issue)
      assert body =~ "make -C elixir all"
    end
  end

  # -------------------------------------------------------------------
  # Issue.apply_delivery/2
  # -------------------------------------------------------------------

  describe "Issue.apply_delivery/2" do
    test "populates delivery metadata fields" do
      issue = %Issue{identifier: "ZEN-19", title: "Test"}

      delivery = %{
        branch: "symphony/zen-19",
        commit_sha: "abc1234",
        pr_number: 42,
        pr_url: "https://github.com/org/repo/pull/42",
        pr_title: "ZEN-19: Test"
      }

      updated = Issue.apply_delivery(issue, delivery)

      assert updated.delivery_branch == "symphony/zen-19"
      assert updated.delivery_commit_sha == "abc1234"
      assert updated.delivery_pr_number == 42
      assert updated.delivery_pr_url == "https://github.com/org/repo/pull/42"
      assert updated.delivery_pr_title == "ZEN-19: Test"
    end

    test "preserves existing issue fields" do
      issue = %Issue{
        id: "id-123",
        identifier: "ZEN-19",
        title: "Test",
        state: "In Progress"
      }

      delivery = %{branch: "symphony/zen-19", commit_sha: "abc", pr_number: 1, pr_url: "url", pr_title: "title"}
      updated = Issue.apply_delivery(issue, delivery)

      assert updated.id == "id-123"
      assert updated.identifier == "ZEN-19"
      assert updated.state == "In Progress"
    end

    test "delivery fields default to nil" do
      issue = %Issue{}
      assert issue.delivery_branch == nil
      assert issue.delivery_commit_sha == nil
      assert issue.delivery_pr_number == nil
      assert issue.delivery_pr_url == nil
      assert issue.delivery_pr_title == nil
    end
  end

  # -------------------------------------------------------------------
  # ready?/1
  # -------------------------------------------------------------------

  describe "ready?/1" do
    test "returns true when PR is merged" do
      pr = %{state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "PENDING", merged: true, number: 1, url: ""}
      assert GitHub.ready?(pr) == true
    end

    test "returns true when state is MERGED" do
      pr = %{state: "MERGED", mergeable: "MERGEABLE", status_check_rollup: "PENDING", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == true
    end

    test "returns true when OPEN + MERGEABLE + SUCCESS" do
      pr = %{state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "SUCCESS", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == true
    end

    test "returns false when OPEN + PENDING checks" do
      pr = %{state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "PENDING", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == false
    end

    test "returns false when OPEN + FAILURE checks" do
      pr = %{state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "FAILURE", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == false
    end

    test "returns false when CLOSED" do
      pr = %{state: "CLOSED", mergeable: "MERGEABLE", status_check_rollup: "SUCCESS", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == false
    end

    test "returns false when CONFLICTING" do
      pr = %{state: "OPEN", mergeable: "CONFLICTING", status_check_rollup: "SUCCESS", merged: false, number: 1, url: ""}
      assert GitHub.ready?(pr) == false
    end
  end

  # -------------------------------------------------------------------
  # deliver/2 — error paths
  # -------------------------------------------------------------------

  describe "deliver/2" do
    test "returns :gh_not_available when gh binary is missing" do
      workspace = setup_git_repo_with_changes()
      issue = %Issue{id: "abc", identifier: "ZEN-19", title: "Test"}
      original_path = System.get_env("PATH")

      try do
        System.put_env("PATH", "")
        assert {:error, :gh_not_available} = GitHub.deliver(issue, workspace)
      after
        System.put_env("PATH", original_path)
      end
    end

    test "returns :no_changes when workspace is clean" do
      workspace = setup_git_repo()
      issue = %Issue{id: "abc", identifier: "ZEN-19", title: "Test"}

      assert {:error, :no_changes} = GitHub.deliver(issue, workspace)
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp setup_git_repo do
    dir = Path.join(System.tmp_dir!(), "symphony-github-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    System.cmd("git", ["init"], cd: dir, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.name", "Test"], cd: dir, stderr_to_stdout: true)
    File.write!(Path.join(dir, "README.md"), "init")
    System.cmd("git", ["add", "."], cd: dir, stderr_to_stdout: true)
    System.cmd("git", ["commit", "-m", "init"], cd: dir, stderr_to_stdout: true)
    dir
  end

  defp setup_git_repo_with_changes do
    dir = setup_git_repo()
    File.write!(Path.join(dir, "dirty.txt"), "uncommitted")
    dir
  end
end
