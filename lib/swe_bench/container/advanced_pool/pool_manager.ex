defmodule SweBench.Container.AdvancedPool.PoolManager do
  @moduledoc """
  Advanced container pool manager with pre-warming and health monitoring.

  Manages individual container pools with sophisticated allocation,
  health monitoring, and predictive scaling capabilities.
  """

  use GenServer
  require Logger

  defstruct [
    :pool_id,
    :config,
    :containers,
    :warm_containers,
    :checked_out_containers,
    :health_monitor_ref,
    :scaling_metrics,
    :allocation_queue
  ]

  @doc """
  Starts a pool manager.
  """
  def start_link(opts) do
    pool_id = Keyword.fetch!(opts, :pool_id)
    config = Keyword.fetch!(opts, :config)

    GenServer.start_link(__MODULE__, {pool_id, config}, name: via_tuple(pool_id))
  end

  @doc """
  Gets pool information and statistics.
  """
  def get_pool_info(pool_pid) when is_pid(pool_pid) do
    GenServer.call(pool_pid, :get_pool_info)
  end

  def get_pool_info(pool_id) do
    GenServer.call(via_tuple(pool_id), :get_pool_info)
  end

  @doc """
  Checks out a container from the pool.
  """
  def checkout_container(pool_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    priority = Keyword.get(opts, :priority, :normal)

    GenServer.call(via_tuple(pool_id), {:checkout_container, priority}, timeout)
  end

  @doc """
  Checks in a container back to the pool.
  """
  def checkin_container(pool_id, container_id, opts \\ []) do
    force_cleanup = Keyword.get(opts, :force_cleanup, false)

    GenServer.cast(via_tuple(pool_id), {:checkin_container, container_id, force_cleanup})
  end

  @doc """
  Triggers pool maintenance.
  """
  def perform_maintenance(pool_id) do
    GenServer.cast(via_tuple(pool_id), :perform_maintenance)
  end

  @doc """
  Gets pool scaling metrics.
  """
  def get_scaling_metrics(pool_id) do
    GenServer.call(via_tuple(pool_id), :get_scaling_metrics)
  end

  # GenServer callbacks

  @impl GenServer
  def init({pool_id, config}) do
    Logger.info("Starting PoolManager for #{pool_id}")

    state = %__MODULE__{
      pool_id: pool_id,
      config: Map.merge(default_config(), config),
      containers: %{},
      warm_containers: :queue.new(),
      checked_out_containers: %{},
      health_monitor_ref: nil,
      scaling_metrics: initialize_scaling_metrics(),
      allocation_queue: :queue.new()
    }

    # Start health monitoring
    health_ref = schedule_health_check(state.config.health_check_interval)
    new_state = %{state | health_monitor_ref: health_ref}

    # Pre-warm initial containers
    send(self(), :prewarm_containers)

    {:ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_pool_info, _from, state) do
    info = %{
      pool_id: state.pool_id,
      status: :active,
      container_count: map_size(state.containers),
      warm_containers: :queue.len(state.warm_containers),
      checked_out_count: map_size(state.checked_out_containers),
      memory_usage_mb: calculate_pool_memory_usage(state),
      cpu_usage_percent: calculate_pool_cpu_usage(state),
      scaling_metrics: state.scaling_metrics
    }

    {:reply, info, state}
  end

  @impl GenServer
  def handle_call({:checkout_container, priority}, from, state) do
    case try_checkout_warm_container(state) do
      {:ok, container_id, new_state} ->
        # Immediate checkout from warm pool
        final_state = record_checkout(container_id, from, new_state)
        {:reply, {:ok, container_id}, final_state}

      {:error, :no_warm_containers} ->
        # Queue the request or create new container
        case can_create_new_container?(state) do
          true ->
            {:ok, container_id, new_state} = create_new_container(state)
            final_state = record_checkout(container_id, from, new_state)
            {:reply, {:ok, container_id}, final_state}

          false ->
            # Queue the request
            new_queue =
              :queue.in({from, priority, System.monotonic_time()}, state.allocation_queue)

            new_state = %{state | allocation_queue: new_queue}
            {:noreply, new_state}
        end
    end
  end

  @impl GenServer
  def handle_call(:get_scaling_metrics, _from, state) do
    {:reply, state.scaling_metrics, state}
  end

  @impl GenServer
  def handle_cast({:checkin_container, container_id, force_cleanup}, state) do
    Logger.debug("Checking in container #{container_id}")

    case Map.get(state.checked_out_containers, container_id) do
      nil ->
        Logger.warning("Attempted to checkin unknown container: #{container_id}")
        {:noreply, state}

      _checkout_info ->
        new_state = process_container_checkin(container_id, force_cleanup, state)
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast(:perform_maintenance, state) do
    Logger.debug("Performing pool maintenance for #{state.pool_id}")

    new_state = perform_pool_maintenance(state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:prewarm_containers, state) do
    Logger.debug("Pre-warming containers for pool #{state.pool_id}")

    target_warm_count = state.config.target_warm_containers
    current_warm_count = :queue.len(state.warm_containers)

    containers_needed = max(0, target_warm_count - current_warm_count)

    new_state = create_warm_containers(containers_needed, state)

    # Schedule next pre-warming check
    Process.send_after(self(), :prewarm_containers, state.config.prewarm_interval)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    Logger.debug("Performing health check for pool #{state.pool_id}")

    new_state = perform_health_check(state)

    # Schedule next health check
    health_ref = schedule_health_check(state.config.health_check_interval)
    final_state = %{new_state | health_monitor_ref: health_ref}

    {:noreply, final_state}
  end

  # Private helper functions

  defp via_tuple(pool_id) do
    {:via, Registry, {SweBench.Container.PoolRegistry, pool_id}}
  end

  defp default_config do
    %{
      min_containers: 2,
      max_containers: 20,
      target_warm_containers: 5,
      health_check_interval: 30_000,
      prewarm_interval: 60_000,
      container_max_age: 3_600_000,
      max_container_usage: 100
    }
  end

  defp initialize_scaling_metrics do
    %{
      checkout_rate: 0,
      checkin_rate: 0,
      average_usage_time: 0,
      peak_usage_count: 0,
      scaling_events: []
    }
  end

  defp try_checkout_warm_container(state) do
    case :queue.out(state.warm_containers) do
      {{:value, container_id}, new_queue} ->
        new_state = %{state | warm_containers: new_queue}
        {:ok, container_id, new_state}

      {:empty, _queue} ->
        {:error, :no_warm_containers}
    end
  end

  defp can_create_new_container?(state) do
    total_containers = map_size(state.containers)
    total_containers < state.config.max_containers
  end

  defp create_new_container(state) do
    container_id = generate_container_id(state.pool_id)

    # Placeholder for container creation
    container_info = %{
      id: container_id,
      created_at: DateTime.utc_now(),
      usage_count: 0,
      status: :ready
    }

    new_containers = Map.put(state.containers, container_id, container_info)
    new_state = %{state | containers: new_containers}

    Logger.debug("Created new container #{container_id}")
    {:ok, container_id, new_state}
  end

  defp record_checkout(container_id, from, state) do
    checkout_info = %{
      checked_out_at: DateTime.utc_now(),
      checked_out_by: from,
      usage_count: get_container_usage_count(container_id, state) + 1
    }

    new_checked_out = Map.put(state.checked_out_containers, container_id, checkout_info)

    # Update container usage count
    new_containers = update_container_usage(container_id, state.containers)

    %{state | checked_out_containers: new_checked_out, containers: new_containers}
  end

  defp process_container_checkin(container_id, force_cleanup, state) do
    # Remove from checked out
    new_checked_out = Map.delete(state.checked_out_containers, container_id)

    # Decide whether to return to warm pool or cleanup
    should_cleanup = force_cleanup || should_cleanup_container?(container_id, state)

    new_state = %{state | checked_out_containers: new_checked_out}

    if should_cleanup do
      cleanup_container(container_id, new_state)
    else
      return_to_warm_pool(container_id, new_state)
    end
  end

  defp should_cleanup_container?(container_id, state) do
    case Map.get(state.containers, container_id) do
      nil ->
        true

      container_info ->
        container_info.usage_count >= state.config.max_container_usage ||
          container_age_exceeded?(container_info, state.config.container_max_age)
    end
  end

  defp container_age_exceeded?(container_info, max_age_ms) do
    age_ms = DateTime.diff(DateTime.utc_now(), container_info.created_at, :millisecond)
    age_ms > max_age_ms
  end

  defp cleanup_container(container_id, state) do
    Logger.debug("Cleaning up container #{container_id}")

    # Remove from containers map
    new_containers = Map.delete(state.containers, container_id)

    # Placeholder for actual container cleanup
    # Would call SweBench.Container.Builder.remove_container(container_id)

    %{state | containers: new_containers}
  end

  defp return_to_warm_pool(container_id, state) do
    Logger.debug("Returning container #{container_id} to warm pool")

    new_warm_queue = :queue.in(container_id, state.warm_containers)

    %{state | warm_containers: new_warm_queue}
  end

  defp create_warm_containers(count, state) when count <= 0, do: state

  defp create_warm_containers(count, state) do
    {:ok, container_id, new_state} = create_new_container(state)

    # Add to warm pool
    new_warm_queue = :queue.in(container_id, new_state.warm_containers)
    updated_state = %{new_state | warm_containers: new_warm_queue}

    create_warm_containers(count - 1, updated_state)
  end

  defp perform_health_check(state) do
    Logger.debug("Health check for #{map_size(state.containers)} containers")

    # Check container health and remove unhealthy ones
    {healthy_containers, unhealthy_count} = check_container_health(state.containers)

    if unhealthy_count > 0 do
      Logger.warning("Removed #{unhealthy_count} unhealthy containers from pool #{state.pool_id}")
    end

    %{state | containers: healthy_containers}
  end

  defp check_container_health(containers) do
    {healthy, unhealthy} =
      Enum.split_with(containers, fn {_id, container} ->
        container_healthy?(container)
      end)

    {Map.new(healthy), length(unhealthy)}
  end

  defp container_healthy?(_container) do
    # Placeholder for health check - would check actual container status
    # 10% chance of unhealthy
    :rand.uniform() > 0.1
  end

  defp perform_pool_maintenance(state) do
    Logger.debug("Performing maintenance for pool #{state.pool_id}")

    # Cleanup old containers, optimize warm pool, update metrics
    state
    |> cleanup_old_containers()
    |> optimize_warm_pool()
    |> update_scaling_metrics()
  end

  defp cleanup_old_containers(state) do
    current_time = DateTime.utc_now()
    max_age_ms = state.config.container_max_age

    {young_containers, old_containers} =
      Enum.split_with(state.containers, fn {_id, container} ->
        age_ms = DateTime.diff(current_time, container.created_at, :millisecond)
        age_ms <= max_age_ms
      end)

    if length(old_containers) > 0 do
      Logger.debug("Cleaned up #{length(old_containers)} old containers")
    end

    %{state | containers: Map.new(young_containers)}
  end

  defp optimize_warm_pool(state) do
    # Remove containers from warm pool that are no longer in containers map
    valid_container_ids = Map.keys(state.containers)

    new_warm_queue =
      :queue.filter(
        fn container_id ->
          container_id in valid_container_ids
        end,
        state.warm_containers
      )

    %{state | warm_containers: new_warm_queue}
  end

  defp update_scaling_metrics(state) do
    # Update scaling metrics for auto-scaling decisions
    current_metrics = %{
      timestamp: DateTime.utc_now(),
      container_count: map_size(state.containers),
      warm_count: :queue.len(state.warm_containers),
      checked_out_count: map_size(state.checked_out_containers),
      utilization_rate: calculate_utilization_rate(state)
    }

    %{state | scaling_metrics: Map.merge(state.scaling_metrics, current_metrics)}
  end

  defp calculate_utilization_rate(state) do
    total = map_size(state.containers)
    checked_out = map_size(state.checked_out_containers)

    if total > 0, do: checked_out / total * 100, else: 0
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp generate_container_id(pool_id) do
    timestamp = System.system_time(:microsecond)
    "#{pool_id}_container_#{timestamp}"
  end

  defp get_container_usage_count(container_id, state) do
    case Map.get(state.containers, container_id) do
      nil -> 0
      container_info -> container_info.usage_count
    end
  end

  defp update_container_usage(container_id, containers) do
    Map.update(containers, container_id, nil, fn container ->
      %{container | usage_count: container.usage_count + 1}
    end)
  end

  defp calculate_pool_memory_usage(state) do
    # Placeholder for memory calculation
    # 50MB per container estimate
    map_size(state.containers) * 50
  end

  defp calculate_pool_cpu_usage(state) do
    # Placeholder for CPU calculation
    utilization = calculate_utilization_rate(state)
    # Estimate based on utilization
    round(utilization * 0.8)
  end
end
