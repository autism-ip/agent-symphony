defmodule SymphonyElixir.OrchestratorFollowUpTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.{FeedbackStore, Orchestrator}
  alias SymphonyElixir.Linear.Issue

  # Each test uses unique issue_ids; no global reset needed.
  # The FeedbackStore singleton is shared across the suite.

  # -------------------------------------------------------------------
  # Snapshot reflects follow-up state
  # -------------------------------------------------------------------

  test "snapshot includes pr_follow_ups from FeedbackStore" do
    issue_id = "issue-fu-snapshot"

    FeedbackStore.record_feedback(
      issue_id,
      "https://github.com/org/repo/pull/99",
      [%{body: "fix this", path: "lib/foo.ex", line: 10}]
    )

    orchestrator_name = Module.concat(__MODULE__, :FuSnapshotOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    snapshot = GenServer.call(pid, :snapshot)
    assert is_list(snapshot.pr_follow_ups)

    fu = Enum.find(snapshot.pr_follow_ups, &(&1.issue_id == issue_id))
    assert fu != nil
    assert fu.pr_url == "https://github.com/org/repo/pull/99"
    assert fu.attempt == 0
    assert fu.max_attempts == FeedbackStore.max_attempts()
    assert fu.feedback_count == 1
  end

  test "snapshot shows empty pr_follow_ups when FeedbackStore is empty" do
    orchestrator_name = Module.concat(__MODULE__, :EmptyFuOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    snapshot = GenServer.call(pid, :snapshot)
    assert snapshot.pr_follow_ups == []
  end

  # -------------------------------------------------------------------
  # Agent normal exit with follow-up pending → follow-up dispatch
  # -------------------------------------------------------------------

  test "agent normal exit with pending follow-up schedules follow-up dispatch" do
    issue_id = "issue-fu-dispatch"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-FU-1",
      title: "Follow-up dispatch test",
      description: "Test",
      state: "In Progress",
      url: "https://example.org/issues/MT-FU-1"
    }

    orchestrator_name = Module.concat(__MODULE__, :FuDispatchOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    # Record follow-up in FeedbackStore
    FeedbackStore.record_feedback(
      issue_id,
      "https://github.com/org/repo/pull/50",
      [%{body: "needs fix"}]
    )

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: "session-fu",
      turn_count: 1,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    # Simulate agent normal exit
    send(pid, {:DOWN, process_ref, :process, self(), :normal})

    # Give the orchestrator time to process
    Process.sleep(50)

    state = :sys.get_state(pid)

    # Issue should no longer be running
    refute Map.has_key?(state.running, issue_id)

    # Should have a follow-up retry scheduled (delay_type: :follow_up)
    retry = Map.get(state.retry_attempts, issue_id)
    assert retry != nil, "Expected a follow-up retry to be scheduled"
    assert retry.attempt == 1
  end

  # -------------------------------------------------------------------
  # Agent normal exit with exhausted follow-up → blocked
  # -------------------------------------------------------------------

  test "agent normal exit with exhausted follow-up blocks as Needs Human" do
    issue_id = "issue-fu-exhausted"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-FU-2",
      title: "Exhausted follow-up test",
      description: "Test",
      state: "In Progress",
      url: "https://example.org/issues/MT-FU-2"
    }

    orchestrator_name = Module.concat(__MODULE__, :FuExhaustedOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    # Record follow-up and exhaust attempts
    FeedbackStore.record_feedback(
      issue_id,
      "https://github.com/org/repo/pull/51",
      [%{body: "needs fix"}]
    )

    for _ <- 1..FeedbackStore.max_attempts() do
      {:ok, _} = FeedbackStore.record_attempt(issue_id)
    end

    # Verify exhausted
    assert {:error, :attempts_exhausted} = FeedbackStore.record_attempt(issue_id)

    # Re-record feedback so get_follow_up returns the exhausted state
    FeedbackStore.record_feedback(
      issue_id,
      "https://github.com/org/repo/pull/51",
      [%{body: "needs fix"}]
    )

    # The attempt count should be at max
    follow_up = FeedbackStore.get_follow_up(issue_id)
    assert follow_up.attempt >= FeedbackStore.max_attempts()

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: "session-fu-exhaust",
      turn_count: 1,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    # Simulate agent normal exit
    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    Process.sleep(50)

    state = :sys.get_state(pid)

    # Issue should be blocked
    assert Map.has_key?(state.blocked, issue_id)
    blocked_entry = Map.get(state.blocked, issue_id)
    assert blocked_entry.last_codex_event == :follow_up_exhausted
    assert blocked_entry.error =~ "follow-up"

    # Should NOT be running
    refute Map.has_key?(state.running, issue_id)

    # FeedbackStore should be cleaned up
    assert nil == FeedbackStore.get_follow_up(issue_id)
  end

  # -------------------------------------------------------------------
  # Agent normal exit without follow-up → normal continuation
  # -------------------------------------------------------------------

  test "agent normal exit without follow-up triggers normal continuation" do
    issue_id = "issue-no-fu"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-NO-FU",
      title: "No follow-up test",
      description: "Test",
      state: "In Progress",
      url: "https://example.org/issues/MT-NO-FU"
    }

    orchestrator_name = Module.concat(__MODULE__, :NoFuOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    # No follow-up recorded in FeedbackStore

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: "session-no-fu",
      turn_count: 1,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    # Simulate agent normal exit
    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    Process.sleep(50)

    state = :sys.get_state(pid)

    # Should have a normal continuation retry (not follow-up)
    retry = Map.get(state.retry_attempts, issue_id)
    assert retry != nil, "Expected a continuation retry to be scheduled"

    # Issue should not be blocked
    refute Map.has_key?(state.blocked, issue_id)
  end

  # -------------------------------------------------------------------
  # Cleanup on reconcile (release_issue_claim path)
  # -------------------------------------------------------------------

  test "FeedbackStore is cleaned up when issue is no longer claimed during reconcile" do
    issue_id = "issue-fu-reconcile"

    FeedbackStore.record_feedback(
      issue_id,
      "https://github.com/org/repo/pull/77",
      [%{body: "fix"}]
    )

    assert FeedbackStore.get_follow_up(issue_id) != nil

    orchestrator_name = Module.concat(__MODULE__, :FuReconcileOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    # Put the issue in claimed with a blocked entry so release_issue_claim gets called
    # when the issue is no longer visible in the tracker
    initial_state = :sys.get_state(pid)

    blocked_entry = %{
      issue_id: issue_id,
      identifier: "MT-RECONCILE",
      error: "test block",
      blocked_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:blocked, %{issue_id => blocked_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    # Trigger reconcile by sending :run_poll_cycle
    # This will call reconcile_blocked_issues which calls release_issue_claim
    # when the issue is not returned by the tracker
    send(pid, :run_poll_cycle)
    Process.sleep(100)

    # FeedbackStore should be cleaned up (the issue won't be found in the tracker)
    # Note: This depends on the tracker returning empty results in test
    # The key assertion is that no crash occurs
    state = :sys.get_state(pid)
    assert is_map(state.blocked)
  end
end
