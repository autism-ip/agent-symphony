Feature: Orchestrator RetryManager
  As the orchestrator functional core
  I want to schedule retries with exponential backoff and handle agent failures
  So that failed issues are retried reliably without overwhelming the system

  # ---------------------------------------------------------------
  # Retry Delay — Exponential Backoff
  # ---------------------------------------------------------------

  Scenario: First failure retry uses base delay
    Given retry attempt 1 with delay_type not :continuation
    When I compute the retry delay
    Then the delay is 10000ms (failure_retry_base_ms)

  Scenario: Second failure retry doubles the base delay
    Given retry attempt 2 with delay_type not :continuation
    When I compute the retry delay
    Then the delay is 20000ms

  Scenario: Third failure retry quadruples the base delay
    Given retry attempt 3 with delay_type not :continuation
    When I compute the retry delay
    Then the delay is 40000ms

  Scenario: Retry delay caps at max_retry_backoff_ms
    Given retry attempt 20 with delay_type not :continuation
    And max_retry_backoff_ms is 300000
    When I compute the retry delay
    Then the delay is at most 300000ms

  Scenario: Delay power is capped at 10 to prevent overflow
    Given retry attempt 15 with delay_type not :continuation
    When I compute the retry delay
    Then the delay uses power min(attempt - 1, 10) = 10

  # ---------------------------------------------------------------
  # Retry Delay — Continuation Type
  # ---------------------------------------------------------------

  Scenario: First continuation retry uses short delay
    Given retry attempt 1 with delay_type :continuation
    When I compute the retry delay
    Then the delay is 1000ms (continuation_retry_delay_ms)

  Scenario: Second continuation retry uses failure backoff (not continuation)
    Given retry attempt 2 with delay_type :continuation
    When I compute the retry delay
    Then the delay is 20000ms (failure backoff for attempt 2)

  # ---------------------------------------------------------------
  # Retry Scheduling — State Updates
  # ---------------------------------------------------------------

  Scenario: Schedule a retry creates a retry_attempts entry
    Given an issue "MT-100" with no prior retry
    When I schedule a retry for attempt 1 with identifier "MT-100" and error "agent exited: :boom"
    Then the retry_attempts map contains "MT-100"
    And the entry has attempt 1
    And the entry has identifier "MT-100"
    And the entry has error "agent exited: :boom"

  Scenario: Schedule a retry sets a future due_at_ms
    Given an issue "MT-100"
    When I schedule a retry for attempt 1
    Then the due_at_ms is in the future

  Scenario: Schedule a retry cancels any previous timer
    Given an issue "MT-100" with an existing retry timer
    When I schedule a new retry for attempt 2
    Then the old timer is cancelled
    And the new retry entry has attempt 2

  Scenario: Schedule a retry with nil attempt increments from previous
    Given an issue "MT-100" with previous retry attempt 3
    When I schedule a retry with nil attempt
    Then the new retry entry has attempt 4

  # ---------------------------------------------------------------
  # Retry Scheduling — Metadata Preservation
  # ---------------------------------------------------------------

  Scenario: Preserve identifier from metadata over previous retry
    Given an issue "MT-100" with previous retry identifier "MT-OLD"
    When I schedule a retry with metadata identifier "MT-NEW"
    Then the retry entry identifier is "MT-NEW"

  Scenario: Fall back to previous retry identifier when metadata has none
    Given an issue "MT-100" with previous retry identifier "MT-OLD"
    When I schedule a retry with metadata identifier nil
    Then the retry entry identifier is "MT-OLD"

  Scenario: Fall back to issue_id when no identifier available
    Given an issue "MT-100" with no previous retry and no metadata identifier
    When I schedule a retry
    Then the retry entry identifier is "MT-100"

  Scenario: Preserve worker_host from metadata
    Given an issue with metadata worker_host "host-a"
    When I schedule a retry
    Then the retry entry worker_host is "host-a"

  Scenario: Preserve workspace_path from metadata
    Given an issue with metadata workspace_path "/workspaces/MT-100"
    When I schedule a retry
    Then the retry entry workspace_path is "/workspaces/MT-100"

  # ---------------------------------------------------------------
  # Retry Execution — Pop Retry State
  # ---------------------------------------------------------------

  Scenario: Pop matching retry attempt by token
    Given a retry entry for "MT-100" with attempt 2 and token :ref_abc
    When I pop retry attempt state for "MT-100" with token :ref_abc
    Then the result is {:ok, 2, metadata, new_state}
    And the retry entry is removed from retry_attempts

  Scenario: Return :missing when token does not match
    Given a retry entry for "MT-100" with attempt 2 and token :ref_abc
    When I pop retry attempt state for "MT-100" with token :ref_xyz
    Then the result is :missing

  Scenario: Return :missing when no retry entry exists
    Given no retry entry for "MT-100"
    When I pop retry attempt state for "MT-100" with token :ref_abc
    Then the result is :missing

  # ---------------------------------------------------------------
  # Retry Execution — Issue Lookup
  # ---------------------------------------------------------------

  Scenario: Dispatch retry when issue is still an active candidate
    Given a retry for "MT-100" at attempt 2
    And the issue is found in candidate issues with state "In Progress"
    And dispatch slots are available
    When I handle the retry
    Then the issue is dispatched with attempt 2

  Scenario: Release claim when issue is in terminal state
    Given a retry for "MT-100" at attempt 2
    And the issue is found with state "Done"
    When I handle the retry
    Then the claim on "MT-100" is released
    And the issue workspace is cleaned up

  Scenario: Release claim when issue is no longer in active states
    Given a retry for "MT-100" at attempt 2
    And the issue is found with state "Backlog"
    When I handle the retry
    Then the claim on "MT-100" is released

  Scenario: Release claim when issue is no longer visible
    Given a retry for "MT-100" at attempt 2
    And the issue is not found in candidate issues
    When I handle the retry
    Then the claim on "MT-100" is released

  Scenario: Re-schedule retry when candidate issue fetch fails
    Given a retry for "MT-100" at attempt 2
    And the candidate issues fetch returns an error
    When I handle the retry
    Then a new retry is scheduled for attempt 3
    And the error message includes the fetch failure reason

  # ---------------------------------------------------------------
  # Retry Execution — Slot Unavailability
  # ---------------------------------------------------------------

  Scenario: Re-schedule retry when no dispatch slots available
    Given a retry for "MT-100" at attempt 2
    And the issue is found and eligible
    And no dispatch slots are available
    When I handle the retry
    Then a new retry is scheduled for attempt 3
    And the error message is "no available orchestrator slots"

  Scenario: Re-schedule retry when worker slots unavailable for preferred host
    Given a retry for "MT-100" at attempt 2 with worker_host "host-a"
    And the issue is found and eligible
    And "host-a" has no capacity
    When I handle the retry
    Then a new retry is scheduled for attempt 3

  # ---------------------------------------------------------------
  # Agent Down — Normal Exit
  # ---------------------------------------------------------------

  Scenario: Schedule continuation when agent exits normally without blocker
    Given a running entry for "MT-100" with last_codex_event :notification
    And the agent exits with reason :normal
    When I handle agent down
    Then the issue is completed (added to completed set)
    And a continuation retry is scheduled with attempt 1

  Scenario: Block issue when agent exits normally with input-required blocker
    Given a running entry for "MT-100" with last_codex_event :turn_input_required
    And the agent exits with reason :normal
    When I handle agent down
    Then the issue is blocked (not retried)
    And the error is "codex turn requires operator input"

  # ---------------------------------------------------------------
  # Agent Down — Abnormal Exit
  # ---------------------------------------------------------------

  Scenario: Schedule retry when agent exits abnormally without blocker
    Given a running entry for "MT-100" with last_codex_event :notification and retry_attempt 0
    And the agent exits with reason {:shutdown, :killed}
    When I handle agent down
    Then a retry is scheduled
    And the error includes the exit reason

  Scenario: Block issue when agent exits abnormally with input-required blocker
    Given a running entry for "MT-100" with last_codex_event :turn_input_required
    And the agent exits with reason {:shutdown, :input_required}
    When I handle agent down
    Then the issue is blocked
    And the error is "codex turn requires operator input"

  Scenario: Schedule retry with incremented attempt from running entry
    Given a running entry for "MT-100" with retry_attempt 3
    And the agent exits with reason :boom
    When I handle agent down
    Then a retry is scheduled with attempt 4

  Scenario: Schedule retry with nil attempt when running entry has no retry_attempt
    Given a running entry for "MT-100" with retry_attempt 0
    And the agent exits with reason :boom
    When I handle agent down
    Then a retry is scheduled with nil attempt

  # ---------------------------------------------------------------
  # Retry Attempt Normalization
  # ---------------------------------------------------------------

  Scenario: Normalize positive integer attempt
    When I normalize retry attempt 3
    Then the result is 3

  Scenario: Normalize zero attempt to 0
    When I normalize retry attempt 0
    Then the result is 0

  Scenario: Normalize nil attempt to 0
    When I normalize retry attempt nil
    Then the result is 0

  Scenario: Normalize negative attempt to 0
    When I normalize retry attempt -1
    Then the result is 0

  # ---------------------------------------------------------------
  # Workspace Cleanup on Terminal States
  # ---------------------------------------------------------------

  Scenario: Clean up workspace when issue reaches terminal state during reconciliation
    Given a running issue "MT-100" with identifier "MT-100" and worker_host "host-a"
    And the issue transitions to terminal state "Done"
    When I reconcile the issue
    Then cleanup_issue_workspace is called with identifier "MT-100" and worker_host "host-a"

  Scenario: Clean up workspace when blocked issue reaches terminal state
    Given a blocked issue "MT-100" with identifier "MT-100" and worker_host "host-b"
    And the issue transitions to terminal state "Cancelled"
    When I reconcile the issue
    Then cleanup_issue_workspace is called with identifier "MT-100" and worker_host "host-b"

  Scenario: Clean up workspace on startup for all terminal issues
    Given issues in terminal states ["Done", "Closed"]
    When the orchestrator initializes
    Then cleanup is called for each terminal issue identifier

  Scenario: Skip workspace cleanup when identifier is nil
    Given a running issue with identifier nil
    And the issue transitions to terminal state
    When I terminate the issue with cleanup true
    Then no workspace cleanup is performed

  # ---------------------------------------------------------------
  # Claim Release
  # ---------------------------------------------------------------

  Scenario: Release claim removes issue from claimed, blocked, and retry_attempts
    Given an issue "MT-100" in claimed, blocked, and retry_attempts
    When I release the claim on "MT-100"
    Then "MT-100" is removed from claimed
    And "MT-100" is removed from blocked
    And "MT-100" is removed from retry_attempts

  # ---------------------------------------------------------------
  # Full Retry Lifecycle — Integration
  # ---------------------------------------------------------------

  Scenario: Complete retry lifecycle from failure to successful dispatch
    Given an issue "MT-100" dispatched for the first time
    When the agent exits with reason :boom
    Then a retry is scheduled for attempt 1
    When the retry timer fires and the issue is still eligible
    Then the issue is dispatched with attempt 1
    When the agent exits normally
    Then a continuation retry is scheduled for attempt 1
    When the continuation timer fires and the issue is still eligible
    Then the issue is dispatched again

  Scenario: Issue transitions to terminal during retry wait
    Given an issue "MT-100" with a pending retry at attempt 2
    When the retry timer fires but the issue state is now "Done"
    Then the claim is released
    And the workspace is cleaned up
    And no further retry is scheduled
