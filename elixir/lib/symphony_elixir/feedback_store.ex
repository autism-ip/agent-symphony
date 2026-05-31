defmodule SymphonyElixir.FeedbackStore do
  @moduledoc """
  In-memory store for PR feedback items and follow-up fix attempts.

  Tracks per-issue follow-up state: which PR triggered feedback, how many
  fix attempts have been made, and what feedback items are outstanding.
  Enforces a bounded retry limit (default 3) so exhausted issues move to
  a "Needs Human" blocked state instead of looping forever.
  """

  use GenServer
  require Logger

  @max_follow_up_attempts 3

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Record that an issue has PR feedback requiring follow-up.
  Returns `{:ok, follow_up_state}` or `{:error, :attempts_exhausted}`.
  """
  @spec record_feedback(String.t(), String.t(), [map()]) ::
          {:ok, map()} | {:error, :attempts_exhausted}
  def record_feedback(issue_id, pr_url, feedback_items) do
    GenServer.call(__MODULE__, {:record_feedback, issue_id, pr_url, feedback_items})
  end

  @doc """
  Record a fix attempt for an issue. Returns `{:ok, follow_up_state}` or
  `{:error, :attempts_exhausted}` if the max has been reached.
  """
  @spec record_attempt(String.t()) :: {:ok, map()} | {:error, :attempts_exhausted}
  def record_attempt(issue_id) do
    GenServer.call(__MODULE__, {:record_attempt, issue_id})
  end

  @doc """
  Get the current follow-up state for an issue, or `nil` if none exists.
  """
  @spec get_follow_up(String.t()) :: map() | nil
  def get_follow_up(issue_id) do
    GenServer.call(__MODULE__, {:get_follow_up, issue_id})
  end

  @doc """
  Get all tracked follow-up states.
  """
  @spec list_follow_ups() :: %{String.t() => map()}
  def list_follow_ups do
    GenServer.call(__MODULE__, :list_follow_ups)
  end

  @doc """
  Remove follow-up state for an issue (cleanup on release).
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(issue_id) do
    GenServer.call(__MODULE__, {:cleanup, issue_id})
  end

  @doc """
  Remove all follow-up state.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Returns the configured maximum follow-up attempts.
  """
  @spec max_attempts() :: pos_integer()
  def max_attempts, do: @max_follow_up_attempts

  # -------------------------------------------------------------------
  # Server callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{follow_ups: %{}}}
  end

  @impl true
  def handle_call({:record_feedback, issue_id, pr_url, feedback_items}, _from, state) do
    existing = Map.get(state.follow_ups, issue_id)
    attempt = if existing, do: existing.attempt, else: 0

    follow_up = %{
      issue_id: issue_id,
      pr_url: pr_url,
      feedback_items: feedback_items,
      attempt: attempt,
      last_checked_at: DateTime.utc_now(),
      created_at: if(existing, do: existing.created_at, else: DateTime.utc_now())
    }

    new_follow_ups = Map.put(state.follow_ups, issue_id, follow_up)
    Logger.info("FeedbackStore: recorded #{length(feedback_items)} feedback items for issue_id=#{issue_id} attempt=#{attempt}")
    {:reply, {:ok, follow_up}, %{state | follow_ups: new_follow_ups}}
  end

  def handle_call({:record_attempt, issue_id}, _from, state) do
    case Map.get(state.follow_ups, issue_id) do
      nil ->
        {:reply, {:error, :no_follow_up}, state}

      existing ->
        new_attempt = existing.attempt + 1

        if new_attempt > @max_follow_up_attempts do
          Logger.warning("FeedbackStore: attempts exhausted for issue_id=#{issue_id} attempt=#{new_attempt}/#{@max_follow_up_attempts}")
          {:reply, {:error, :attempts_exhausted}, state}
        else
          updated = %{existing | attempt: new_attempt, last_checked_at: DateTime.utc_now()}
          new_follow_ups = Map.put(state.follow_ups, issue_id, updated)
          Logger.info("FeedbackStore: recorded attempt #{new_attempt}/#{@max_follow_up_attempts} for issue_id=#{issue_id}")
          {:reply, {:ok, updated}, %{state | follow_ups: new_follow_ups}}
        end
    end
  end

  def handle_call({:get_follow_up, issue_id}, _from, state) do
    {:reply, Map.get(state.follow_ups, issue_id), state}
  end

  def handle_call(:list_follow_ups, _from, state) do
    {:reply, state.follow_ups, state}
  end

  def handle_call({:cleanup, issue_id}, _from, state) do
    new_follow_ups = Map.delete(state.follow_ups, issue_id)
    {:reply, :ok, %{state | follow_ups: new_follow_ups}}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{follow_ups: %{}}}
  end
end
