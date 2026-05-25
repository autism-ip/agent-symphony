Feature: Orchestrator BlockerDetector
  As the orchestrator functional core
  I want to detect input-required blockers from Codex events
  So that I can classify blocker types and normalize completion outcomes

  # ---------------------------------------------------------------
  # Input-Required Blocker Detection — Codex Event Source
  # ---------------------------------------------------------------

  Scenario: Detect input blocker when last_codex_event is turn_input_required
    Given a running entry with last_codex_event :turn_input_required
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker when last_codex_event is approval_required
    Given a running entry with last_codex_event :approval_required
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Not an input blocker when last_codex_event is notification
    Given a running entry with last_codex_event :notification
    And no completion outcome and no MCP elicitation method
    When I check if the entry is an input-required blocker
    Then the result is false

  Scenario: Not an input blocker when last_codex_event is nil
    Given a running entry with last_codex_event nil
    And no completion outcome and no MCP elicitation method
    When I check if the entry is an input-required blocker
    Then the result is false

  # ---------------------------------------------------------------
  # Input-Required Blocker Detection — Completion Outcome Source
  # ---------------------------------------------------------------

  Scenario: Detect input blocker from completion outcome :input_required
    Given a running entry with completion outcome :input_required
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from completion outcome :needs_input
    Given a running entry with completion outcome :needs_input
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from completion outcome :approval_required
    Given a running entry with completion outcome :approval_required
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from string completion outcome "input_required"
    Given a running entry with completion outcome "input_required"
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from string completion outcome "needs_input"
    Given a running entry with completion outcome "needs_input"
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from string completion outcome "approval_required"
    Given a running entry with completion outcome "approval_required"
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Not an input blocker when completion outcome is :success
    Given a running entry with completion outcome :success
    When I check if the entry is an input-required blocker
    Then the result is false

  Scenario: Not an input blocker when completion outcome is an unrecognized string
    Given a running entry with completion outcome "unknown_status"
    When I check if the entry is an input-required blocker
    Then the result is false

  Scenario: Not an input blocker when completion is nil
    Given a running entry with completion nil
    When I check if the entry is an input-required blocker
    Then the result is false

  Scenario: Not an input blocker when completion has no outcome key
    Given a running entry with completion %{some_field: "value"}
    When I check if the entry is an input-required blocker
    Then the result is false

  # ---------------------------------------------------------------
  # Input-Required Blocker Detection — MCP Elicitation Source
  # ---------------------------------------------------------------

  Scenario: Detect input blocker from MCP elicitation request method
    Given a running entry with last_codex_message containing method "mcpServer/elicitation/request"
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Detect input blocker from nested message method
    Given a running entry with last_codex_message %{message: %{"method" => "mcpServer/elicitation/request"}}
    When I check if the entry is an input-required blocker
    Then the result is true

  Scenario: Not an input blocker when message method is unrelated
    Given a running entry with last_codex_message %{message: %{"method" => "turn/completed"}}
    And no codex event blocker and no completion blocker
    When I check if the entry is an input-required blocker
    Then the result is false

  # ---------------------------------------------------------------
  # Input-Required Blocker Detection — Nil/Empty Entry
  # ---------------------------------------------------------------

  Scenario: Not an input blocker when running_entry is nil
    Given a nil running entry
    When I check if the entry is an input-required blocker
    Then the result is false

  Scenario: Not an input blocker when running_entry is empty map
    Given an empty running entry map
    When I check if the entry is an input-required blocker
    Then the result is false

  # ---------------------------------------------------------------
  # Blocker Error Message Generation
  # ---------------------------------------------------------------

  Scenario: Generate error from turn_input_required codex event
    Given a running entry with last_codex_event :turn_input_required
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires operator input"

  Scenario: Generate error from approval_required codex event
    Given a running entry with last_codex_event :approval_required
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires approval"

  Scenario: Generate error from completion with input_required outcome
    Given a running entry with last_codex_event nil and completion outcome :input_required
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires operator input"

  Scenario: Generate error from completion with needs_input outcome
    Given a running entry with last_codex_event nil and completion outcome :needs_input
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires operator input"

  Scenario: Generate error from completion with approval_required outcome
    Given a running entry with last_codex_event nil and completion outcome :approval_required
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires approval"

  Scenario: Generate error from MCP elicitation method
    Given a running entry with last_codex_message method "mcpServer/elicitation/request" and no event or completion blocker
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex MCP elicitation requires operator input"

  Scenario: Fall back to provided fallback when no blocker source matches
    Given a running entry with no codex event, no completion, and no MCP method
    When I generate the blocker error with fallback "agent exited: :boom"
    Then the error message is "agent exited: :boom"

  Scenario: Fall back when running_entry is nil
    Given a nil running entry
    When I generate the blocker error with fallback "generic stall"
    Then the error message is "generic stall"

  # ---------------------------------------------------------------
  # Blocker Error Priority — Codex Event > Completion > MCP > Fallback
  # ---------------------------------------------------------------

  Scenario: Codex event takes precedence over completion outcome
    Given a running entry with last_codex_event :turn_input_required and completion outcome :approval_required
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires operator input"

  Scenario: Completion outcome takes precedence over MCP method
    Given a running entry with last_codex_event nil, completion outcome :approval_required, and message method "mcpServer/elicitation/request"
    When I generate the blocker error with fallback "stalled"
    Then the error message is "codex turn requires approval"

  # ---------------------------------------------------------------
  # Codex Message Method Extraction
  # ---------------------------------------------------------------

  Scenario: Extract method from message with string key "method"
    Given a codex message %{"method" => "turn/completed"}
    When I extract the codex message method
    Then the method is "turn/completed"

  Scenario: Extract method from message with atom key method
    Given a codex message %{method: "turn/completed"}
    When I extract the codex message method
    Then the method is "turn/completed"

  Scenario: Extract method from nested message.message structure
    Given a codex message %{message: %{"method" => "mcpServer/elicitation/request"}}
    When I extract the codex message method
    Then the method is "mcpServer/elicitation/request"

  Scenario: Extract method from nested message with atom method key
    Given a codex message %{message: %{method: "turn/started"}}
    When I extract the codex message method
    Then the method is "turn/started"

  Scenario: Return nil when message has no method key
    Given a codex message %{event: :notification, timestamp: nil}
    When I extract the codex message method
    Then the method is nil

  Scenario: Return nil when message is nil
    Given a nil codex message
    When I extract the codex message method
    Then the method is nil

  # ---------------------------------------------------------------
  # Completion Outcome Normalization
  # ---------------------------------------------------------------

  Scenario Outline: Normalize valid input-required outcomes from atoms
    Given a completion with atom outcome <atom_outcome>
    When I normalize the input-required outcome
    Then the normalized outcome is <normalized>

    Examples:
      | atom_outcome       | normalized           |
      | :input_required    | :input_required      |
      | :needs_input       | :needs_input         |
      | :approval_required | :approval_required   |

  Scenario Outline: Normalize valid input-required outcomes from strings
    Given a completion with string outcome "<string_outcome>"
    When I normalize the input-required outcome
    Then the normalized outcome is <normalized>

    Examples:
      | string_outcome    | normalized           |
      | input_required    | :input_required      |
      | needs_input       | :needs_input         |
      | approval_required | :approval_required   |

  Scenario: Return nil for unrecognized outcome string
    Given a completion with string outcome "completed_successfully"
    When I normalize the input-required outcome
    Then the normalized outcome is nil

  Scenario: Return nil for unrecognized outcome atom
    Given a completion with atom outcome :unknown
    When I normalize the input-required outcome
    Then the normalized outcome is nil

  Scenario: Return nil when completion is nil
    Given a nil completion
    When I normalize the input-required outcome
    Then the normalized outcome is nil

  Scenario: Return nil when completion has no outcome
    Given a completion with no outcome field
    When I normalize the input-required outcome
    Then the normalized outcome is nil

  # ---------------------------------------------------------------
  # Blocker Detection with Agent Down
  # ---------------------------------------------------------------

  Scenario: Block (not retry) when agent exits normally with input-required blocker
    Given a running entry with last_codex_event :turn_input_required
    And the agent exits with reason :normal
    When I determine the agent-down action
    Then the action is block
    And the error message is "codex turn requires operator input"

  Scenario: Block (not retry) when agent exits abnormally with input-required blocker
    Given a running entry with last_codex_event :turn_input_required
    And the agent exits with reason {:shutdown, :input_required}
    When I determine the agent-down action
    Then the action is block
    And the error message is "codex turn requires operator input"

  Scenario: Block when agent exits normally with completion input_required
    Given a running entry with completion outcome :input_required
    And the agent exits with reason :normal
    When I determine the agent-down action
    Then the action is block
    And the error message is "codex turn requires operator input"

  Scenario: Retry when agent exits normally without input-required blocker
    Given a running entry with last_codex_event :notification and no completion blocker
    And the agent exits with reason :normal
    When I determine the agent-down action
    Then the action is schedule_continuation

  Scenario: Retry when agent exits abnormally without input-required blocker
    Given a running entry with last_codex_event :notification and no completion blocker
    And the agent exits with reason {:shutdown, :boom}
    When I determine the agent-down action
    Then the action is schedule_retry
