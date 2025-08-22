defmodule SweBench.Pipeline.ContainerEvaluator do
  @moduledoc """
  GenStage ConsumerProducer for container-based evaluation.

  Integrates with container pool for parallel evaluation, implements
  container health monitoring, and handles evaluation timeouts.
  """

  use GenStage
  require Logger

  # alias SweBench.Container - for future container integration

  defstruct [
    :container_pool,
    :timeout_config,
    :health_monitor,
    :active_evaluations,
    :max_concurrent_evaluations
  ]

  @doc """
  Starts the container evaluator stage.
  """
  def start_link(opts \\ []) do
    stage_name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, opts, name: stage_name)
  end

  @doc """
  Gets current evaluator statistics.
  """
  def get_stats(stage_name \\ __MODULE__) do
    GenStage.call(stage_name, :get_stats)
  end

  # GenStage callbacks

  @impl GenStage
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent_evaluations, 12)
    evaluation_timeout = Keyword.get(opts, :evaluation_timeout, 300_000)

    state = %__MODULE__{
      container_pool: initialize_container_pool(opts),
      timeout_config: %{evaluation: evaluation_timeout, cleanup: 30_000},
      health_monitor: initialize_health_monitor(opts),
      active_evaluations: %{},
      max_concurrent_evaluations: max_concurrent
    }

    Logger.info("ContainerEvaluator started with max_concurrent=#{max_concurrent}")

    # Schedule periodic health checks
    schedule_health_check()

    {:producer_consumer, state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    Logger.debug("ContainerEvaluator processing #{length(events)} patch events")

    # Filter events that can be processed based on available capacity
    available_capacity = state.max_concurrent_evaluations - map_size(state.active_evaluations)
    processable_events = Enum.take(events, available_capacity)

    if length(processable_events) < length(events) do
      Logger.debug(
        "ContainerEvaluator at capacity, queuing #{length(events) - length(processable_events)} events"
      )
    end

    {completed_evaluations, new_state} = start_evaluations(processable_events, state)

    {:noreply, completed_evaluations, new_state}
  end

  @impl GenStage
  def handle_call(:get_stats, _from, state) do
    stats = %{
      active_evaluations: map_size(state.active_evaluations),
      max_concurrent: state.max_concurrent_evaluations,
      available_capacity: state.max_concurrent_evaluations - map_size(state.active_evaluations),
      timeout_config: state.timeout_config
    }

    {:reply, stats, [], state}
  end

  @impl GenStage
  def handle_info({:evaluation_complete, evaluation_id, result}, state) do
    Logger.debug("Evaluation #{evaluation_id} completed")

    case Map.get(state.active_evaluations, evaluation_id) do
      nil ->
        Logger.warning("Received completion for unknown evaluation: #{evaluation_id}")
        {:noreply, [], state}

      evaluation_data ->
        enhanced_result = Map.merge(evaluation_data, result)
        new_active = Map.delete(state.active_evaluations, evaluation_id)
        new_state = %{state | active_evaluations: new_active}

        {:noreply, [enhanced_result], new_state}
    end
  end

  @impl GenStage
  def handle_info({:evaluation_timeout, evaluation_id}, state) do
    Logger.warning("Evaluation #{evaluation_id} timed out")

    case Map.get(state.active_evaluations, evaluation_id) do
      nil ->
        {:noreply, [], state}

      evaluation_data ->
        timeout_result =
          Map.merge(evaluation_data, %{
            status: :timeout,
            error: :evaluation_timeout,
            completed_at: DateTime.utc_now()
          })

        new_active = Map.delete(state.active_evaluations, evaluation_id)
        new_state = %{state | active_evaluations: new_active}

        {:noreply, [timeout_result], new_state}
    end
  end

  @impl GenStage
  def handle_info(:health_check, state) do
    Logger.debug("Performing container health check")

    # Check health of active evaluations
    unhealthy_evaluations = check_evaluation_health(state.active_evaluations)

    # Handle unhealthy evaluations
    new_state = handle_unhealthy_evaluations(unhealthy_evaluations, state)

    # Schedule next health check
    schedule_health_check()

    {:noreply, [], new_state}
  end

  # Private helper functions

  defp start_evaluations(events, state) do
    {completed, new_active} =
      Enum.map_reduce(events, state.active_evaluations, fn event, active ->
        evaluation_id = generate_evaluation_id()

        {:ok, :async} = start_container_evaluation(event, evaluation_id, state)

        evaluation_data = %{
          id: evaluation_id,
          task: event,
          started_at: DateTime.utc_now(),
          status: :running
        }

        new_active = Map.put(active, evaluation_id, evaluation_data)
        {nil, new_active}
      end)

    # Filter out nil events (async evaluations)
    immediate_completions = Enum.filter(completed, & &1)

    new_state = %{state | active_evaluations: new_active}
    {immediate_completions, new_state}
  end

  defp start_container_evaluation(event, evaluation_id, state) do
    Logger.debug("Starting container evaluation #{evaluation_id} for task #{event.id}")

    # Simulate container evaluation startup
    spawn(fn ->
      # Simulate evaluation time
      evaluation_time = :rand.uniform(2000) + 1000
      :timer.sleep(evaluation_time)

      result = %{
        status: :completed,
        evaluation_time: evaluation_time,
        test_results: %{passed: 15, failed: 2, total: 17},
        completed_at: DateTime.utc_now()
      }

      send(self(), {:evaluation_complete, evaluation_id, result})
    end)

    # Set timeout
    Process.send_after(
      self(),
      {:evaluation_timeout, evaluation_id},
      state.timeout_config.evaluation
    )

    {:ok, :async}
  end

  defp generate_evaluation_id do
    timestamp = System.system_time(:microsecond)
    "eval_#{timestamp}_#{:rand.uniform(999)}"
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end

  defp check_evaluation_health(active_evaluations) do
    current_time = DateTime.utc_now()

    Enum.filter(active_evaluations, fn {_id, evaluation} ->
      time_diff = DateTime.diff(current_time, evaluation.started_at, :second)
      # Mark as unhealthy if running > 5 minutes
      time_diff > 300
    end)
  end

  defp handle_unhealthy_evaluations(unhealthy_evaluations, state) do
    if length(unhealthy_evaluations) > 0 do
      Logger.warning("Found #{length(unhealthy_evaluations)} unhealthy evaluations")

      # Remove unhealthy evaluations from active list
      unhealthy_ids = Enum.map(unhealthy_evaluations, fn {id, _eval} -> id end)
      new_active = Map.drop(state.active_evaluations, unhealthy_ids)

      %{state | active_evaluations: new_active}
    else
      state
    end
  end

  defp initialize_container_pool(_opts) do
    # Placeholder for container pool initialization
    %{pool_id: "evaluation_pool", size: 12}
  end

  defp initialize_health_monitor(_opts) do
    # Placeholder for health monitor initialization
    %{enabled: true, check_interval: 30_000}
  end
end
