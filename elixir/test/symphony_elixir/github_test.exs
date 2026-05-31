defmodule SymphonyElixir.GitHubTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub

  # -------------------------------------------------------------------
  # parse_pr_url
  # -------------------------------------------------------------------

  describe "parse_pr_url/1" do
    test "parses standard GitHub PR URL" do
      assert {:ok, {"owner/repo", 42}} =
               GitHub.parse_pr_url("https://github.com/owner/repo/pull/42")
    end

    test "parses URL without https prefix" do
      assert {:ok, {"acme/app", 7}} =
               GitHub.parse_pr_url("github.com/acme/app/pull/7")
    end

    test "parses URL with trailing slash" do
      assert {:ok, {"org/project", 100}} =
               GitHub.parse_pr_url("https://github.com/org/project/pull/100/")
    end

    test "returns :error for non-GitHub URL" do
      assert :error == GitHub.parse_pr_url("https://gitlab.com/org/repo/pull/1")
    end

    test "returns :error for URL missing PR number" do
      assert :error == GitHub.parse_pr_url("https://github.com/org/repo/pull/")
    end

    test "returns :error for non-numeric PR number" do
      assert :error == GitHub.parse_pr_url("https://github.com/org/repo/pull/abc")
    end

    test "returns :error for empty string" do
      assert :error == GitHub.parse_pr_url("")
    end

    test "returns :error for nil" do
      assert :error == GitHub.parse_pr_url(nil)
    end

    test "returns :error for completely unrelated string" do
      assert :error == GitHub.parse_pr_url("not a url at all")
    end
  end

  # -------------------------------------------------------------------
  # ready?/1
  # -------------------------------------------------------------------

  describe "ready?/1" do
    test "merged PR is ready" do
      assert GitHub.ready?(%{merged: true, state: "OPEN", mergeable: "UNKNOWN", status_check_rollup: "PENDING"})
    end

    test "MERGED state PR is ready" do
      assert GitHub.ready?(%{merged: false, state: "MERGED", mergeable: "UNKNOWN", status_check_rollup: "PENDING"})
    end

    test "OPEN PR with successful checks is ready" do
      assert GitHub.ready?(%{merged: false, state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "SUCCESS"})
    end

    test "OPEN PR with conflicting merge is not ready" do
      refute GitHub.ready?(%{merged: false, state: "OPEN", mergeable: "CONFLICTING", status_check_rollup: "SUCCESS"})
    end

    test "OPEN PR with pending checks is not ready" do
      refute GitHub.ready?(%{merged: false, state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "PENDING"})
    end

    test "OPEN PR with failure checks is not ready" do
      refute GitHub.ready?(%{merged: false, state: "OPEN", mergeable: "MERGEABLE", status_check_rollup: "FAILURE"})
    end

    test "CLOSED PR is not ready" do
      refute GitHub.ready?(%{merged: false, state: "CLOSED", mergeable: "UNKNOWN", status_check_rollup: "PENDING"})
    end
  end
end
