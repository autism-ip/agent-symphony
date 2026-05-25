Feature: Orchestrator Dispatcher
  As the orchestrator functional core
  I want to select issues for dispatch based on priority and capacity
  So that workers are loaded efficiently without exceeding limits

  # ---------------------------------------------------------------
  # Issue Sorting — Priority Ordering
  # ---------------------------------------------------------------

  Scenario: Sort issues by priority ascending (1 = highest)
    Given issues with priorities [3, 1, 4, 2]
    When I sort issues for dispatch
    Then the first issue has priority 1
    And the second issue has priority 2
    And the third issue has priority 3
    And the fourth issue has priority 4

  Scenario: Sort issues with equal priority by created_at ascending
    Given issues with priority 1 and created_at times ["2026-01-01", "2026-01-03", "2026-01-02"]
    When I sort issues for dispatch
    Then the issues are ordered by created_at ascending

  Scenario: Sort issues with equal priority and no created_at by identifier
    Given issues with priority 1, no created_at, and identifiers ["MT-100", "MT-050", "MT-200"]
    When I sort issues for dispatch
    Then the issues are ordered by identifier ascending

  Scenario: Treat nil priority as lowest rank (5)
    Given issues with priorities [nil, 1, nil, 2]
    When I sort issues for dispatch
    Then priority 1 comes first, then 2, then the nil-priority issues

  Scenario: Treat out-of-range priority as lowest rank
    Given issues with priorities [0, 5, -1, 1]
    When I sort issues for dispatch
    Then priority 1 comes first, then the out-of-range issues

  # ---------------------------------------------------------------
  # Issue Filtering — Candidate Eligibility
  # ---------------------------------------------------------------

  Scenario: Accept issue with valid id, identifier, title, and active state
    Given an issue with id "abc", identifier "MT-10", title "Fix bug", state "In Progress"
    And active states include "In Progress"
    And terminal states include "Done"
    When I check if the issue is a candidate
    Then the result is true

  Scenario: Reject issue with nil id
    Given an issue with id nil, identifier "MT-10", title "Fix bug", state "In Progress"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Reject issue with nil identifier
    Given an issue with id "abc", identifier nil, title "Fix bug", state "In Progress"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Reject issue with nil title
    Given an issue with id "abc", identifier "MT-10", title nil, state "In Progress"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Reject issue with nil state
    Given an issue with id "abc", identifier "MT-10", title "Fix bug", state nil
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Reject issue in terminal state
    Given an issue with state "Done"
    And terminal states include "Done"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Reject issue not in active states
    Given an issue with state "Backlog"
    And active states include "Todo", "In Progress"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Accept issue with assigned_to_worker true
    Given an issue with assigned_to_worker true and state "In Progress"
    When I check if the issue is a candidate
    Then the result is true

  Scenario: Reject issue with assigned_to_worker false
    Given an issue with assigned_to_worker false and state "In Progress"
    When I check if the issue is a candidate
    Then the result is false

  Scenario: Accept issue with assigned_to_worker nil (default routable)
    Given an issue with assigned_to_worker nil and state "In Progress"
    When I check if the issue is a candidate
    Then the result is true

  # ---------------------------------------------------------------
  # Blocked-by Non-Terminal Guard
  # ---------------------------------------------------------------

  Scenario: Reject Todo issue blocked by non-terminal blocker
    Given an issue in state "Todo" with blocked_by [%{state: "In Progress"}]
    And terminal states include "Done"
    When I check if the issue is a dispatch candidate
    Then the result is false

  Scenario: Accept Todo issue blocked only by terminal blockers
    Given an issue in state "Todo" with blocked_by [%{state: "Done"}]
    And terminal states include "Done"
    When I check if the issue is a dispatch candidate
    Then the result is true

  Scenario: Accept non-Todo issue even with non-terminal blockers
    Given an issue in state "In Progress" with blocked_by [%{state: "In Progress"}]
    When I check if the issue is a dispatch candidate
    Then the result is true

  Scenario: Accept Todo issue with empty blocked_by list
    Given an issue in state "Todo" with blocked_by []
    When I check if the issue is a dispatch candidate
    Then the result is true

  Scenario: Reject Todo issue when blocker has no state field
    Given an issue in state "Todo" with blocked_by [%{id: "some-id"}]
    When I check if the issue is a dispatch candidate
    Then the result is false

  # ---------------------------------------------------------------
  # Dispatch Eligibility — Already Claimed/Running/Blocked
  # ---------------------------------------------------------------

  Scenario: Reject issue that is already claimed
    Given an eligible issue "MT-10"
    And the issue is in the claimed set
    When I check dispatch eligibility
    Then the issue is not dispatched

  Scenario: Reject issue that is already running
    Given an eligible issue "MT-10"
    And the issue is in the running map
    When I check dispatch eligibility
    Then the issue is not dispatched

  Scenario: Reject issue that is already blocked
    Given an eligible issue "MT-10"
    And the issue is in the blocked map
    When I check dispatch eligibility
    Then the issue is not dispatched

  # ---------------------------------------------------------------
  # Global Slot Availability
  # ---------------------------------------------------------------

  Scenario: Reject dispatch when no global slots available
    Given max_concurrent_agents is 3
    And 3 issues are currently running
    When I check available slots
    Then available slots is 0
    And no new issues are dispatched

  Scenario: Allow dispatch when global slots are available
    Given max_concurrent_agents is 3
    And 1 issue is currently running
    When I check available slots
    Then available slots is 2

  Scenario: Treat zero running issues as full availability
    Given max_concurrent_agents is 5
    And 0 issues are currently running
    When I check available slots
    Then available slots is 5

  # ---------------------------------------------------------------
  # Per-State Concurrency Limits
  # ---------------------------------------------------------------

  Scenario: Reject dispatch when per-state limit is reached
    Given max_concurrent_agents_for_state "In Progress" is 2
    And 2 issues in state "In Progress" are currently running
    When I check state slots for an "In Progress" issue
    Then the result is no slots available

  Scenario: Allow dispatch when per-state limit is not reached
    Given max_concurrent_agents_for_state "In Progress" is 2
    And 1 issue in state "In Progress" is currently running
    When I check state slots for an "In Progress" issue
    Then the result is slots available

  Scenario: Per-state limit is case-insensitive
    Given max_concurrent_agents_for_state "in progress" is 1
    And 1 issue in state "In Progress" is currently running
    When I check state slots for an "in progress" issue
    Then the result is no slots available

  # ---------------------------------------------------------------
  # Worker Host Selection — Load Balancing
  # ---------------------------------------------------------------

  Scenario: Select least loaded worker host
    Given SSH hosts ["host-a", "host-b", "host-c"]
    And host-a has 2 running agents, host-b has 1 running agent, host-c has 3 running agents
    When I select a worker host with no preference
    Then the selected host is "host-b"

  Scenario: Select preferred host when it has capacity
    Given SSH hosts ["host-a", "host-b"]
    And host-a has 1 running agent, host-b has 0 running agents
    When I select a worker host with preference "host-a"
    Then the selected host is "host-a"

  Scenario: Fall back to least loaded when preferred host has no capacity
    Given SSH hosts ["host-a", "host-b"]
    And max_concurrent_agents_per_host is 2
    And host-a has 2 running agents, host-b has 0 running agents
    When I select a worker host with preference "host-a"
    Then the selected host is "host-b"

  Scenario: Return no_worker_capacity when all hosts are full
    Given SSH hosts ["host-a", "host-b"]
    And max_concurrent_agents_per_host is 1
    And host-a has 1 running agent, host-b has 1 running agent
    When I select a worker host with no preference
    Then the result is no_worker_capacity

  Scenario: Return nil (local) when no SSH hosts configured
    Given no SSH hosts configured
    When I select a worker host with no preference
    Then the selected host is nil (local execution)

  Scenario: Reject empty string as preferred host
    Given SSH hosts ["host-a"]
    When I select a worker host with preference ""
    Then the selected host is "host-a" (preference ignored)

  # ---------------------------------------------------------------
  # Worker Slot Availability — Per-Host Limit
  # ---------------------------------------------------------------

  Scenario: Per-host limit uses max_concurrent_agents_per_host config
    Given max_concurrent_agents_per_host is 3
    And host "host-a" has 2 running agents
    When I check worker host slots for "host-a"
    Then slots are available

  Scenario: Per-host limit blocks when at capacity
    Given max_concurrent_agents_per_host is 3
    And host "host-a" has 3 running agents
    When I check worker host slots for "host-a"
    Then no slots are available

  # ---------------------------------------------------------------
  # Issue Revalidation Before Dispatch
  # ---------------------------------------------------------------

  Scenario: Dispatch proceeds when refreshed issue is still a candidate
    Given an issue "MT-10" ready for dispatch
    And the issue fetcher returns the issue in state "In Progress"
    When I revalidate the issue for dispatch
    Then the result is ok with the refreshed issue

  Scenario: Skip dispatch when refreshed issue is in terminal state
    Given an issue "MT-10" ready for dispatch
    And the issue fetcher returns the issue in state "Done"
    When I revalidate the issue for dispatch
    Then the result is skip with the refreshed issue

  Scenario: Skip dispatch when issue is no longer visible
    Given an issue "MT-10" ready for dispatch
    And the issue fetcher returns an empty list
    When I revalidate the issue for dispatch
    Then the result is skip with reason missing

  Scenario: Error when issue fetcher fails
    Given an issue "MT-10" ready for dispatch
    And the issue fetcher returns an error
    When I revalidate the issue for dispatch
    Then the result is an error

  # ---------------------------------------------------------------
  # Full Dispatch Cycle — Integration
  # ---------------------------------------------------------------

  Scenario: Dispatch highest-priority eligible issue first
    Given candidate issues with priorities [2, 1, 3] and all eligible
    And 3 global slots available
    When I run the dispatch cycle
    Then the priority-1 issue is dispatched first

  Scenario: Stop dispatching when global slots are exhausted
    Given 5 candidate issues all eligible
    And max_concurrent_agents is 2
    When I run the dispatch cycle
    Then exactly 2 issues are dispatched

  Scenario: Skip already-claimed issues and dispatch next eligible
    Given candidate issues ["MT-1", "MT-2", "MT-3"] all eligible
    And "MT-2" is already claimed
    And 3 global slots available
    When I run the dispatch cycle
    Then "MT-1" and "MT-3" are dispatched
    And "MT-2" is not dispatched

  Scenario: Dispatch nothing when no candidate issues exist
    Given no candidate issues
    When I run the dispatch cycle
    Then no issues are dispatched
