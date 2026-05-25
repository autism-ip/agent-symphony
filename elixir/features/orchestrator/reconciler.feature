Feature: Orchestrator Reconciler
  As the orchestrator functional core
  I want to reconcile running and blocked issues with Linear state
  So that the orchestrator stays consistent with external reality

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Terminal Transitions
  # ---------------------------------------------------------------

  Scenario: Terminate running issue when it moves to a terminal state
    Given a running issue "MT-100" in state "In Progress"
    And Linear reports the issue is now in terminal state "Done"
    When I reconcile running issues
    Then the issue is removed from running
    And the issue workspace is cleaned up
    And the issue is removed from claimed

  Scenario: Terminate running issue when it moves to terminal state "Closed"
    Given a running issue "MT-101" in state "In Progress"
    And Linear reports the issue is now in terminal state "Closed"
    When I reconcile running issues
    Then the issue is removed from running
    And the issue workspace is cleaned up

  Scenario: Terminate running issue when it moves to terminal state "Cancelled"
    Given a running issue "MT-102" in state "In Progress"
    And Linear reports the issue is now in terminal state "Cancelled"
    When I reconcile running issues
    Then the issue is removed from running

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Active State Refresh
  # ---------------------------------------------------------------

  Scenario: Refresh running issue state when issue remains in active state
    Given a running issue "MT-200" in state "In Progress"
    And Linear reports the issue is still in state "In Progress"
    When I reconcile running issues
    Then the issue remains in running
    And the running entry issue object is refreshed from Linear

  Scenario: Refresh running issue when it transitions between active states
    Given a running issue "MT-201" in state "Todo"
    And Linear reports the issue is now in state "In Progress"
    When I reconcile running issues
    Then the issue remains in running
    And the running entry issue object reflects the new state

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Non-Active Transitions
  # ---------------------------------------------------------------

  Scenario: Terminate running issue when it moves to a non-active non-terminal state
    Given a running issue "MT-300" in state "In Progress"
    And Linear reports the issue is now in a non-active non-terminal state "Backlog"
    When I reconcile running issues
    Then the issue is removed from running
    And the issue workspace is NOT cleaned up

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Routability
  # ---------------------------------------------------------------

  Scenario: Terminate running issue when it is no longer routable to worker
    Given a running issue "MT-400" in state "In Progress" assigned to this worker
    And Linear reports the issue has assigned_to_worker set to false
    When I reconcile running issues
    Then the issue is removed from running
    And the issue workspace is NOT cleaned up

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Missing Issues
  # ---------------------------------------------------------------

  Scenario: Terminate running issue when it disappears from Linear
    Given a running issue "MT-500" in state "In Progress"
    And Linear does not return this issue in the state query
    When I reconcile running issues
    Then the issue is removed from running

  Scenario: Handle multiple missing issues gracefully
    Given running issues "MT-501" and "MT-502" in state "In Progress"
    And Linear returns only "MT-501" in the state query
    When I reconcile running issues
    Then "MT-502" is removed from running
    And "MT-501" remains in running

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Fetch Failure
  # ---------------------------------------------------------------

  Scenario: Keep all running issues when Linear state fetch fails
    Given running issues "MT-600" and "MT-601"
    And the Linear state fetch returns an error
    When I reconcile running issues
    Then all running issues remain unchanged

  # ---------------------------------------------------------------
  # Running Issue State Reconciliation — Stall Detection
  # ---------------------------------------------------------------

  Scenario: Restart stalled issue with backoff when no codex activity exceeds timeout
    Given a running issue "MT-700" with last codex activity 30 seconds ago
    And the stall timeout is configured to 10 seconds
    And the issue is not an input-required blocker
    When I reconcile stalled running issues
    Then the issue is removed from running
    And a retry is scheduled with backoff

  Scenario: Block stalled issue when it has an input-required blocker
    Given a running issue "MT-701" with last codex activity 30 seconds ago
    And the stall timeout is configured to 10 seconds
    And the issue has last_codex_event :turn_input_required
    When I reconcile stalled running issues
    Then the issue is removed from running
    And the issue is moved to blocked
    And no retry is scheduled

  Scenario: Skip stall detection when stall timeout is zero or negative
    Given a running issue "MT-702" with last codex activity 60 seconds ago
    And the stall timeout is configured to 0
    When I reconcile stalled running issues
    Then the issue remains in running

  Scenario: Skip stall detection when no issues are running
    Given no running issues
    When I reconcile stalled running issues
    Then no state changes occur

  Scenario: Skip stall detection for issues that are already blocked
    Given a running issue "MT-703" that is also in the blocked map
    And the issue has stale codex activity
    When I reconcile stalled running issues
    Then the issue remains in running

  Scenario: Use last_codex_timestamp for stall elapsed calculation
    Given a running issue "MT-704" with last_codex_timestamp 20 seconds ago and started_at 60 seconds ago
    And the stall timeout is configured to 15 seconds
    When I reconcile stalled running issues
    Then the issue is restarted

  Scenario: Fall back to started_at when last_codex_timestamp is nil
    Given a running issue "MT-705" with last_codex_timestamp nil and started_at 30 seconds ago
    And the stall timeout is configured to 10 seconds
    When I reconcile stalled running issues
    Then the issue is restarted

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Terminal Transitions
  # ---------------------------------------------------------------

  Scenario: Release blocked issue when it moves to a terminal state
    Given a blocked issue "MT-800" with error "codex turn requires operator input"
    And Linear reports the issue is now in terminal state "Done"
    When I reconcile blocked issues
    Then the issue is removed from blocked
    And the issue is removed from claimed
    And the issue workspace is cleaned up

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Active State Refresh
  # ---------------------------------------------------------------

  Scenario: Refresh blocked issue state when it remains in active state
    Given a blocked issue "MT-801" in state "In Progress"
    And Linear reports the issue is still in state "In Progress"
    When I reconcile blocked issues
    Then the issue remains in blocked
    And the blocked entry issue object is refreshed

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Non-Active Transitions
  # ---------------------------------------------------------------

  Scenario: Release blocked issue when it moves to non-active non-terminal state
    Given a blocked issue "MT-802" in state "In Progress"
    And Linear reports the issue is now in state "Backlog"
    When I reconcile blocked issues
    Then the issue is removed from blocked
    And the issue is removed from claimed

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Routability
  # ---------------------------------------------------------------

  Scenario: Release blocked issue when it is no longer routable to worker
    Given a blocked issue "MT-803" assigned to this worker
    And Linear reports the issue has assigned_to_worker set to false
    When I reconcile blocked issues
    Then the issue is removed from blocked
    And the issue is removed from claimed

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Missing Issues
  # ---------------------------------------------------------------

  Scenario: Release blocked issue when it disappears from Linear
    Given a blocked issue "MT-900"
    And Linear does not return this issue in the state query
    When I reconcile blocked issues
    Then the issue is removed from blocked
    And the issue is removed from claimed

  # ---------------------------------------------------------------
  # Blocked Issue State Reconciliation — Fetch Failure
  # ---------------------------------------------------------------

  Scenario: Keep all blocked issues when Linear state fetch fails
    Given blocked issues "MT-901" and "MT-902"
    And the Linear state fetch returns an error
    When I reconcile blocked issues
    Then all blocked issues remain unchanged

  # ---------------------------------------------------------------
  # State Normalization
  # ---------------------------------------------------------------

  Scenario Outline: Normalize issue state names for comparison
    Given an issue state name "<raw_state>"
    When I normalize the issue state
    Then the normalized state is "<normalized>"

    Examples:
      | raw_state     | normalized    |
      | In Progress   | in progress   |
      | " Todo "      | todo          |
      | CLOSED        | closed        |
      | Done          | done          |

  # ---------------------------------------------------------------
  # Terminal and Active State Classification
  # ---------------------------------------------------------------

  Scenario: Recognize configured terminal states
    Given terminal states are configured as ["Done", "Closed", "Cancelled"]
    When I check if state "Done" is terminal
    Then the result is true

  Scenario: Reject non-terminal states
    Given terminal states are configured as ["Done", "Closed", "Cancelled"]
    When I check if state "In Progress" is terminal
    Then the result is false

  Scenario: Recognize configured active states
    Given active states are configured as ["Todo", "In Progress"]
    When I check if state "In Progress" is active
    Then the result is true

  Scenario: Reject non-active states
    Given active states are configured as ["Todo", "In Progress"]
    When I check if state "Backlog" is active
    Then the result is false

  # ---------------------------------------------------------------
  # Reconcile Combined — Running + Blocked
  # ---------------------------------------------------------------

  Scenario: Full reconciliation processes both running and blocked issues
    Given a running issue "MT-A1" in state "In Progress" that moved to "Done"
    And a blocked issue "MT-A2" that moved to "Cancelled"
    And a running issue "MT-A3" that remains in "In Progress"
    When I run the full reconciliation cycle
    Then "MT-A1" is removed from running
    And "MT-A2" is removed from blocked
    And "MT-A3" remains in running
