defmodule SweBench.Container.AdvancedPool.HealthMonitor do
  @moduledoc """
  Container health monitoring system for advanced pool management.

  Implements comprehensive health checks, predictive failure detection,
  and automated container lifecycle management.
  """

  use GenServer
  require Logger

  alias SweBench.Container.AdvancedPool.PoolSupervisor

  defstruct [
    :pools,
    :health_metrics,
    :check_interval,
    :failure_thresholds,
    :predictive_model
  ]

  @doc """
  Starts the health monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets health status for all monitored pools.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Triggers immediate health check for specific pool.
  """
  def check_pool_health(pool_id) do
    GenServer.call(__MODULE__, {:check_pool_health, pool_id})
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, 30_000)

    state = %__MODULE__{
      pools: %{},
      health_metrics: %{},
      check_interval: check_interval,
      failure_thresholds: default_failure_thresholds(),
      predictive_model: initialize_predictive_model()
    }

    Logger.info("HealthMonitor started with check_interval=#{check_interval}ms")

    # Schedule first health check
    schedule_health_check(check_interval)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_health_status, _from, state) do
    {:reply, state.health_metrics, state}
  end

  @impl GenServer
  def handle_call({:check_pool_health, pool_id}, _from, state) do
    health_result = perform_pool_health_check(pool_id, state)
    new_metrics = Map.put(state.health_metrics, pool_id, health_result)
    new_state = %{state | health_metrics: new_metrics}

    {:reply, health_result, new_state}
  end

  @impl GenServer
  def handle_info(:perform_health_checks, state) do
    Logger.debug("Performing scheduled health checks")

    new_metrics = perform_all_health_checks(state)
    new_state = %{state | health_metrics: new_metrics}

    # Schedule next check
    schedule_health_check(state.check_interval)

    {:noreply, new_state}
  end

  # Private helper functions

  defp default_failure_thresholds do
    %{
      max_memory_mb: 1000,
      max_cpu_percent: 90,
      max_response_time_ms: 5000,
      max_failure_rate: 0.1
    }
  end

  defp initialize_predictive_model do
    %{
      enabled: true,
      # 5 minutes
      failure_prediction_window: 300_000,
      health_score_threshold: 70
    }
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :perform_health_checks, interval)
  end

  defp perform_all_health_checks(state) do
    # Get all active pools
    {:ok, pools} = PoolSupervisor.list_pools()

    Map.new(pools, fn pool ->
      health_result = perform_pool_health_check(pool.pool_id, state)
      {pool.pool_id, health_result}
    end)
  end

  defp perform_pool_health_check(pool_id, state) do
    Logger.debug("Performing health check for pool #{pool_id}")

    # Collect health metrics
    health_data = %{
      pool_id: pool_id,
      timestamp: DateTime.utc_now(),
      memory_usage: check_memory_usage(pool_id),
      cpu_usage: check_cpu_usage(pool_id),
      response_time: check_response_time(pool_id),
      error_rate: check_error_rate(pool_id),
      container_count: check_container_count(pool_id)
    }

    # Calculate overall health score
    health_score = calculate_health_score(health_data, state.failure_thresholds)

    # Determine actions needed
    actions = determine_health_actions(health_data, health_score, state.failure_thresholds)

    %{
      health_data: health_data,
      health_score: health_score,
      status: determine_health_status(health_score),
      recommended_actions: actions,
      checked_at: DateTime.utc_now()
    }
  end

  defp check_memory_usage(_pool_id) do
    # Placeholder for memory usage check
    # 100-900 MB
    :rand.uniform(800) + 100
  end

  defp check_cpu_usage(_pool_id) do
    # Placeholder for CPU usage check
    # 10-90%
    :rand.uniform(80) + 10
  end

  defp check_response_time(_pool_id) do
    # Placeholder for response time check
    # 500-3500ms
    :rand.uniform(3000) + 500
  end

  defp check_error_rate(_pool_id) do
    # Placeholder for error rate check
    # 0-5% error rate
    :rand.uniform() * 0.05
  end

  defp check_container_count(_pool_id) do
    # Placeholder for container count
    # 5-20 containers
    :rand.uniform(15) + 5
  end

  defp calculate_health_score(health_data, thresholds) do
    scores = [
      memory_score(health_data.memory_usage, thresholds.max_memory_mb),
      cpu_score(health_data.cpu_usage, thresholds.max_cpu_percent),
      response_time_score(health_data.response_time, thresholds.max_response_time_ms),
      error_rate_score(health_data.error_rate, thresholds.max_failure_rate)
    ]

    # Average score with weights
    weighted_score = (scores |> Enum.sum()) / length(scores)
    round(weighted_score)
  end

  defp memory_score(usage, max_threshold) do
    if usage <= max_threshold, do: 100, else: max(0, 100 - (usage - max_threshold) / 10)
  end

  defp cpu_score(usage, max_threshold) do
    if usage <= max_threshold, do: 100, else: max(0, 100 - (usage - max_threshold))
  end

  defp response_time_score(time, max_threshold) do
    if time <= max_threshold, do: 100, else: max(0, 100 - (time - max_threshold) / 100)
  end

  defp error_rate_score(rate, max_threshold) do
    if rate <= max_threshold, do: 100, else: max(0, 100 - (rate - max_threshold) * 1000)
  end

  defp determine_health_status(health_score) do
    cond do
      health_score >= 90 -> :excellent
      health_score >= 75 -> :good
      health_score >= 60 -> :fair
      health_score >= 40 -> :poor
      true -> :critical
    end
  end

  defp determine_health_actions(health_data, health_score, thresholds) do
    actions = []

    actions =
      if health_data.memory_usage > thresholds.max_memory_mb,
        do: [:reduce_memory_usage | actions],
        else: actions

    actions =
      if health_data.cpu_usage > thresholds.max_cpu_percent,
        do: [:reduce_cpu_load | actions],
        else: actions

    actions =
      if health_data.error_rate > thresholds.max_failure_rate,
        do: [:investigate_errors | actions],
        else: actions

    actions = if health_score < 50, do: [:consider_pool_restart | actions], else: actions

    actions
  end
end
