Feature: Orchestrator CodexTelemetry
  As the orchestrator functional core
  I want to extract token usage and rate limits from Codex worker updates
  So that I can maintain accurate accounting without side effects

  # ---------------------------------------------------------------
  # Token Usage Extraction — Absolute Payloads
  # ---------------------------------------------------------------

  Scenario Outline: Extract absolute token usage from deeply nested Codex payloads
    Given a Codex update with token usage at path "<path>"
    And the usage map contains input_tokens 50, output_tokens 20, total_tokens 70
    When I extract token usage from the update
    Then the extracted usage has input_tokens 50, output_tokens 20, total_tokens 70

    Examples:
      | path                                                       |
      | params.msg.payload.info.total_token_usage                  |
      | params.msg.info.total_token_usage                          |
      | params.tokenUsage.total                                    |
      | tokenUsage.total                                           |

  Scenario: Extract token usage from snake_case integer fields
    Given a Codex update with usage map %{"input_tokens" => 100, "output_tokens" => 40, "total_tokens" => 140}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 100, output_tokens 40, total_tokens 140

  Scenario: Extract token usage from camelCase integer fields
    Given a Codex update with usage map %{"inputTokens" => 100, "outputTokens" => 40, "totalTokens" => 140}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 100, output_tokens 40, total_tokens 140

  Scenario: Extract token usage from prompt/completion field aliases
    Given a Codex update with usage map %{"prompt_tokens" => 30, "completion_tokens" => 15, "total_tokens" => 45}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 30, output_tokens 15, total_tokens 45

  Scenario: Extract token usage from atom-keyed usage map
    Given a Codex update with usage map %{input_tokens: 8, output_tokens: 3, total_tokens: 11}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 8, output_tokens 3, total_tokens 11

  # ---------------------------------------------------------------
  # Token Usage Extraction — turn/completed Method
  # ---------------------------------------------------------------

  Scenario: Extract token usage from turn/completed payload with string method
    Given a Codex update with method "turn/completed" and usage %{"input_tokens" => 12, "output_tokens" => 4, "total_tokens" => 16}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 12, output_tokens 4, total_tokens 16

  Scenario: Extract token usage from turn/completed payload with atom method
    Given a Codex update with method :turn_completed and usage %{input_tokens: 5, output_tokens: 2, total_tokens: 7}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 5, output_tokens 2, total_tokens 7

  Scenario: Extract token usage from turn/completed with usage under params
    Given a Codex update with method "turn/completed" and usage nested under params.usage as %{"input_tokens" => 20, "output_tokens" => 8, "total_tokens" => 28}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 20, output_tokens 8, total_tokens 28

  Scenario: Prefer absolute total_token_usage over last_token_usage in token_count payloads
    Given a Codex update with both last_token_usage %{"input_tokens" => 2, "output_tokens" => 1, "total_tokens" => 3} and total_token_usage %{"input_tokens" => 200, "output_tokens" => 100, "total_tokens" => 300}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 200, output_tokens 100, total_tokens 300

  Scenario: Ignore last_token_usage when no cumulative totals are present
    Given a Codex update with only last_token_usage %{"input_tokens" => 8, "output_tokens" => 3, "total_tokens" => 11} and no total_token_usage
    When I extract token usage from the update
    Then the extracted usage is empty

  # ---------------------------------------------------------------
  # Token Usage Extraction — String-Coerced Values
  # ---------------------------------------------------------------

  Scenario: Parse string-encoded token values as integers
    Given a Codex update with usage map %{"input_tokens" => "12", "output_tokens" => "4", "total_tokens" => "16"}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 12, output_tokens 4, total_tokens 16

  Scenario: Parse string values with leading whitespace
    Given a Codex update with usage map %{"input_tokens" => "  42  ", "output_tokens" => "  10  ", "total_tokens" => "  52  "}
    When I extract token usage from the update
    Then the extracted usage has input_tokens 42, output_tokens 10, total_tokens 52

  Scenario: Reject negative string token values
    Given a Codex update with usage map %{"input_tokens" => "-5", "output_tokens" => "3", "total_tokens" => "8"}
    When I extract token usage from the update
    Then the extracted usage has no input_tokens, output_tokens 3, total_tokens 8

  # ---------------------------------------------------------------
  # Token Usage Extraction — Missing and Malformed Payloads
  # ---------------------------------------------------------------

  Scenario: Return empty usage when update has no usage data
    Given a Codex update with event :notification and no usage fields
    When I extract token usage from the update
    Then the extracted usage is empty

  Scenario: Return empty usage when payload is nil
    Given a Codex update with nil payload
    When I extract token usage from the update
    Then the extracted usage is empty

  Scenario: Return empty usage when usage map has no recognized token fields
    Given a Codex update with usage map %{"unknown_field" => 42, "other" => "value"}
    When I extract token usage from the update
    Then the extracted usage is empty

  Scenario: Reject negative integer token values
    Given a Codex update with usage map %{input_tokens: -10, output_tokens: 5, total_tokens: 15}
    When I extract token usage from the update
    Then the extracted usage has no input_tokens

  # ---------------------------------------------------------------
  # Token Delta Computation
  # ---------------------------------------------------------------

  Scenario: Compute token delta as difference from last reported values
    Given a running entry with last reported input 100, output 40, total 140
    And a Codex update reporting input 150, output 60, total 210
    When I compute the token delta
    Then the delta is input 50, output 20, total 70
    And the new reported values are input 150, output 60, total 210

  Scenario: Zero delta when reported values have not increased
    Given a running entry with last reported input 100, output 40, total 140
    And a Codex update reporting input 100, output 40, total 140
    When I compute the token delta
    Then the delta is input 0, output 0, total 0

  Scenario: Zero delta when reported values decrease (counter reset)
    Given a running entry with last reported input 200, output 80, total 280
    And a Codex update reporting input 50, output 20, total 70
    When I compute the token delta
    Then the delta is input 0, output 0, total 0
    And the new reported values are input 200, output 80, total 280

  Scenario: First update with no previous reported values
    Given a running entry with no previous reported token values
    And a Codex update reporting input 10, output 5, total 15
    When I compute the token delta
    Then the delta is input 10, output 5, total 15

  Scenario: Delta is zero when usage extraction returns empty
    Given a running entry with last reported input 100, output 40, total 140
    And a Codex update with no recognizable usage data
    When I compute the token delta
    Then the delta is input 0, output 0, total 0

  # ---------------------------------------------------------------
  # Cumulative Token Totals
  # ---------------------------------------------------------------

  Scenario: Accumulate multiple monotonic token updates into thread totals
    Given cumulative codex totals of input 0, output 0, total 0, seconds 0
    When I apply token delta input 8, output 3, total 11, seconds 5
    And I apply token delta input 2, output 1, total 3, seconds 10
    Then the cumulative totals are input 10, output 4, total 14, seconds 15

  Scenario: Token totals never go negative
    Given cumulative codex totals of input 5, output 2, total 7, seconds 3
    When I apply token delta input 0, output 0, total 0, seconds 0
    Then all cumulative totals are non-negative

  # ---------------------------------------------------------------
  # Rate Limit Extraction
  # ---------------------------------------------------------------

  Scenario: Extract rate limits from top-level rate_limits field
    Given a Codex update with rate_limits containing limit_id "codex", primary remaining 90, limit 100
    When I extract rate limits from the update
    Then the rate limits have limit_id "codex" and primary remaining 90

  Scenario: Extract rate limits from nested payload rate_limits
    Given a Codex update with rate_limits nested under payload.rate_limits
    And the rate limits contain limit_id "codex", primary remaining 50, limit 100
    When I extract rate limits from the update
    Then the rate limits have limit_id "codex" and primary remaining 50

  Scenario: Extract rate limits from deeply nested event message
    Given a Codex update with rate_limits nested under payload.info.rate_limits
    And the rate limits contain limit_id "codex", credits balance nil
    When I extract rate limits from the update
    Then the rate limits have limit_id "codex"

  Scenario: Recognize rate limits map by presence of limit_id and bucket keys
    Given a map with limit_id "test" and keys primary, secondary, credits
    When I check if the map is a rate_limits map
    Then the result is true

  Scenario: Reject map without limit_id as rate_limits
    Given a map with keys primary, secondary but no limit_id
    When I check if the map is a rate_limits map
    Then the result is false

  Scenario: Reject map without bucket keys as rate_limits
    Given a map with limit_id "test" but no primary, secondary, or credits keys
    When I check if the map is a rate_limits map
    Then the result is false

  Scenario: Return nil when no rate limits found in update
    Given a Codex update with no rate_limits fields anywhere
    When I extract rate limits from the update
    Then the result is nil

  # ---------------------------------------------------------------
  # Session and Turn Tracking
  # ---------------------------------------------------------------

  Scenario: Set session_id from session_started event
    Given a running entry with session_id nil
    And a Codex update with event :session_started and session_id "thread-abc-turn-1"
    When I integrate the codex update
    Then the running entry session_id is "thread-abc-turn-1"

  Scenario: Preserve existing session_id when update has no session_id
    Given a running entry with session_id "thread-existing"
    And a Codex update with event :notification and no session_id
    When I integrate the codex update
    Then the running entry session_id is "thread-existing"

  Scenario: Increment turn_count when session_id changes on session_started
    Given a running entry with session_id "thread-old" and turn_count 2
    And a Codex update with event :session_started and session_id "thread-new"
    When I integrate the codex update
    Then the running entry turn_count is 3

  Scenario: Do not increment turn_count when session_id is unchanged
    Given a running entry with session_id "thread-same" and turn_count 5
    And a Codex update with event :session_started and session_id "thread-same"
    When I integrate the codex update
    Then the running entry turn_count is 5

  Scenario: Preserve turn_count on non-session-started events
    Given a running entry with session_id "thread-abc" and turn_count 3
    And a Codex update with event :notification
    When I integrate the codex update
    Then the running entry turn_count is 3

  Scenario: Update codex_app_server_pid from update
    Given a running entry with codex_app_server_pid nil
    And a Codex update with codex_app_server_pid "4242"
    When I integrate the codex update
    Then the running entry codex_app_server_pid is "4242"

  Scenario: Convert integer codex_app_server_pid to string
    Given a running entry with codex_app_server_pid nil
    And a Codex update with codex_app_server_pid 4242
    When I integrate the codex update
    Then the running entry codex_app_server_pid is "4242"

  # ---------------------------------------------------------------
  # Session Completion Totals
  # ---------------------------------------------------------------

  Scenario: Record runtime seconds on session completion
    Given a running entry started 60 seconds ago
    When I record session completion totals
    Then the codex_totals seconds_running is at least 59
