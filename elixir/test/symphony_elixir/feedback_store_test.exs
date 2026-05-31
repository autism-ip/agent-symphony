defmodule SymphonyElixir.FeedbackStoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.FeedbackStore

  setup do
    # Use a unique name per test to avoid conflicts
    name = Module.concat(__MODULE__, :"FeedbackStore#{System.unique_integer([:positive])}")
    {:ok, pid} = FeedbackStore.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    %{pid: pid, name: name}
  end

  # -------------------------------------------------------------------
  # record_feedback
  # -------------------------------------------------------------------

  test "record_feedback creates a new follow-up at attempt 0", %{name: name} do
    items = [%{body: "fix this", path: "lib/foo.ex", line: 10}]

    assert {:ok, follow_up} =
             GenServer.call(name, {:record_feedback, "issue-1", "https://github.com/org/repo/pull/42", items})

    assert follow_up.issue_id == "issue-1"
    assert follow_up.pr_url == "https://github.com/org/repo/pull/42"
    assert follow_up.feedback_items == items
    assert follow_up.attempt == 0
    assert %DateTime{} = follow_up.created_at
    assert %DateTime{} = follow_up.last_checked_at
  end

  test "record_feedback preserves existing attempt count", %{name: name} do
    items = [%{body: "fix this"}]
    GenServer.call(name, {:record_feedback, "issue-2", "https://github.com/org/repo/pull/1", items})
    GenServer.call(name, {:record_attempt, "issue-2"})

    new_items = [%{body: "still broken"}]

    assert {:ok, follow_up} =
             GenServer.call(name, {:record_feedback, "issue-2", "https://github.com/org/repo/pull/1", new_items})

    assert follow_up.attempt == 1
    assert follow_up.feedback_items == new_items
  end

  # -------------------------------------------------------------------
  # record_attempt
  # -------------------------------------------------------------------

  test "record_attempt increments the attempt counter", %{name: name} do
    GenServer.call(name, {:record_feedback, "issue-3", "https://github.com/org/repo/pull/5", [%{body: "x"}]})

    assert {:ok, %{attempt: 1}} = GenServer.call(name, {:record_attempt, "issue-3"})
    assert {:ok, %{attempt: 2}} = GenServer.call(name, {:record_attempt, "issue-3"})
    assert {:ok, %{attempt: 3}} = GenServer.call(name, {:record_attempt, "issue-3"})
  end

  test "record_attempt returns exhausted after max attempts", %{name: name} do
    GenServer.call(name, {:record_feedback, "issue-4", "https://github.com/org/repo/pull/6", [%{body: "x"}]})

    for _ <- 1..FeedbackStore.max_attempts() do
      assert {:ok, _} = GenServer.call(name, {:record_attempt, "issue-4"})
    end

    assert {:error, :attempts_exhausted} = GenServer.call(name, {:record_attempt, "issue-4"})
  end

  test "record_attempt returns error for unknown issue", %{name: name} do
    assert {:error, :no_follow_up} = GenServer.call(name, {:record_attempt, "nonexistent"})
  end

  # -------------------------------------------------------------------
  # get_follow_up / list_follow_ups
  # -------------------------------------------------------------------

  test "get_follow_up returns nil for unknown issue", %{name: name} do
    assert nil == GenServer.call(name, {:get_follow_up, "missing"})
  end

  test "get_follow_up returns the follow-up after record_feedback", %{name: name} do
    GenServer.call(name, {:record_feedback, "issue-5", "https://github.com/org/repo/pull/7", [%{body: "x"}]})
    result = GenServer.call(name, {:get_follow_up, "issue-5"})
    assert result.issue_id == "issue-5"
  end

  test "list_follow_ups returns all tracked follow-ups", %{name: name} do
    GenServer.call(name, {:record_feedback, "a", "https://github.com/o/r/pull/1", []})
    GenServer.call(name, {:record_feedback, "b", "https://github.com/o/r/pull/2", []})

    result = GenServer.call(name, :list_follow_ups)
    assert Map.has_key?(result, "a")
    assert Map.has_key?(result, "b")
    assert map_size(result) == 2
  end

  # -------------------------------------------------------------------
  # cleanup / reset
  # -------------------------------------------------------------------

  test "cleanup removes a single follow-up", %{name: name} do
    GenServer.call(name, {:record_feedback, "issue-6", "https://github.com/o/r/pull/8", []})
    assert :ok == GenServer.call(name, {:cleanup, "issue-6"})
    assert nil == GenServer.call(name, {:get_follow_up, "issue-6"})
  end

  test "cleanup is idempotent for missing issues", %{name: name} do
    assert :ok == GenServer.call(name, {:cleanup, "nonexistent"})
  end

  test "reset clears all follow-ups", %{name: name} do
    GenServer.call(name, {:record_feedback, "x", "https://github.com/o/r/pull/1", []})
    GenServer.call(name, {:record_feedback, "y", "https://github.com/o/r/pull/2", []})

    assert :ok == GenServer.call(name, :reset)
    assert %{} == GenServer.call(name, :list_follow_ups)
  end

  # -------------------------------------------------------------------
  # max_attempts
  # -------------------------------------------------------------------

  test "max_attempts returns a positive integer" do
    assert is_integer(FeedbackStore.max_attempts())
    assert FeedbackStore.max_attempts() > 0
  end
end
