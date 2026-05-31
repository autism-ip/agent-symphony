defmodule SymphonyElixir.FeedbackStoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.FeedbackStore
  alias SymphonyElixir.FeedbackStore.{FeedbackItem, FixAttempt}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SymphonyElixir.Repo)
  end

  # -------------------------------------------------------------------
  # Feedback Items
  # -------------------------------------------------------------------

  describe "create_feedback_item/1" do
    test "creates item with valid attrs" do
      attrs = %{
        run_id: "run-1",
        source: "codex-review",
        severity: :high,
        status: :open,
        body: "Missing error handling"
      }

      assert {:ok, %FeedbackItem{} = item} = FeedbackStore.create_feedback_item(attrs)
      assert item.run_id == "run-1"
      assert item.severity == :high
      assert item.status == :open
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = FeedbackStore.create_feedback_item(%{})
      refute changeset.valid?
    end
  end

  describe "get_feedback_item/1" do
    test "returns item when it exists" do
      {:ok, item} = FeedbackStore.create_feedback_item(valid_feedback_attrs())
      assert %FeedbackItem{} = FeedbackStore.get_feedback_item(item.id)
    end

    test "returns nil when item does not exist" do
      assert FeedbackStore.get_feedback_item(-1) == nil
    end
  end

  describe "list_feedback_items_by_run/1" do
    test "returns items for the given run" do
      FeedbackStore.create_feedback_item(valid_feedback_attrs(run_id: "run-1"))
      FeedbackStore.create_feedback_item(valid_feedback_attrs(run_id: "run-1"))
      FeedbackStore.create_feedback_item(valid_feedback_attrs(run_id: "run-2"))

      items = FeedbackStore.list_feedback_items_by_run("run-1")
      assert length(items) == 2
      assert Enum.all?(items, &(&1.run_id == "run-1"))
    end
  end

  describe "update_feedback_item/2" do
    test "updates item attrs" do
      {:ok, item} = FeedbackStore.create_feedback_item(valid_feedback_attrs())
      assert {:ok, updated} = FeedbackStore.update_feedback_item(item, %{status: :resolved})
      assert updated.status == :resolved
    end
  end

  describe "delete_feedback_item/1" do
    test "deletes the item" do
      {:ok, item} = FeedbackStore.create_feedback_item(valid_feedback_attrs())
      assert :ok = FeedbackStore.delete_feedback_item(item)
      assert FeedbackStore.get_feedback_item(item.id) == nil
    end
  end

  # -------------------------------------------------------------------
  # Fix Attempts
  # -------------------------------------------------------------------

  describe "create_fix_attempt/1" do
    test "creates attempt with valid attrs" do
      attrs = %{
        run_id: "run-1",
        attempt_number: 1,
        trigger_source: "codex-review",
        base_commit: "abc1234"
      }

      assert {:ok, %FixAttempt{} = attempt} = FeedbackStore.create_fix_attempt(attrs)
      assert attempt.run_id == "run-1"
      assert attempt.attempt_number == 1
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = FeedbackStore.create_fix_attempt(%{})
      refute changeset.valid?
    end
  end

  describe "get_fix_attempt/1" do
    test "returns attempt when it exists" do
      {:ok, attempt} = FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs())
      assert %FixAttempt{} = FeedbackStore.get_fix_attempt(attempt.id)
    end

    test "returns nil when attempt does not exist" do
      assert FeedbackStore.get_fix_attempt(-1) == nil
    end
  end

  describe "list_fix_attempts_by_run/1" do
    test "returns attempts for the given run ordered by attempt_number" do
      FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs(attempt_number: 2))
      FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs(attempt_number: 1))

      attempts = FeedbackStore.list_fix_attempts_by_run("run-1")
      assert length(attempts) == 2
      assert Enum.map(attempts, & &1.attempt_number) == [1, 2]
    end
  end

  describe "next_attempt_number/1" do
    test "returns 1 when no attempts exist" do
      assert FeedbackStore.next_attempt_number("run-new") == 1
    end

    test "returns max + 1" do
      FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs(attempt_number: 3))
      assert FeedbackStore.next_attempt_number("run-1") == 4
    end
  end

  describe "update_fix_attempt/2" do
    test "updates attempt attrs" do
      {:ok, attempt} = FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs())

      assert {:ok, updated} =
               FeedbackStore.update_fix_attempt(attempt, %{result_commit: "def5678"})

      assert updated.result_commit == "def5678"
    end
  end

  describe "delete_fix_attempt/1" do
    test "deletes the attempt" do
      {:ok, attempt} = FeedbackStore.create_fix_attempt(valid_fix_attempt_attrs())
      assert :ok = FeedbackStore.delete_fix_attempt(attempt)
      assert FeedbackStore.get_fix_attempt(attempt.id) == nil
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp valid_feedback_attrs(overrides \\ []) do
    %{
      run_id: "run-1",
      source: "codex-review",
      severity: :medium,
      status: :open,
      body: "Test feedback item"
    }
    |> Map.merge(Map.new(overrides))
  end

  defp valid_fix_attempt_attrs(overrides \\ []) do
    %{
      run_id: "run-1",
      attempt_number: 1,
      trigger_source: "codex-review",
      base_commit: "abc1234"
    }
    |> Map.merge(Map.new(overrides))
  end
end
