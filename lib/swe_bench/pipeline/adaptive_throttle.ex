defmodule SweBench.Pipeline.AdaptiveThrottle do
  @moduledoc """
  Dynamic concurrency management for the parallel evaluation pipeline.

  Monitors system resources and automatically adjusts concurrency levels
  to maintain optimal performance while preventing resource exhaustion.
  Implements gradual scaling algorithms and memory pressure detection.
  """

  use GenServer
  require Logger

  @default_max_concurrency 10
  @default_min_concurrency 2
  # 80% of available memory
  @memory_pressure_threshold 0.8
  # 90% CPU utilization
  @cpu_pressure_threshold 0.9
  # Scaling increment/decrement
  @scaling_factor 1.2
  # 5 seconds between adjustments
  @adjustment_interval 5_000
  # 2 seconds between memory checks
  @memory_check_interval 2_000

  defstruct [
    :max_concurrency,
    :min_concurrency,
    :current_concurrency,
    :target_concurrency,
    :memory_pressure_threshold,
    :cpu_pressure_threshold,
    :scaling_factor,
    :adjustment_history,
    :resource_metrics,
    :auto_scaling_enabled
  ]

  @type t :: %__MODULE__{
          max_concurrency: pos_integer(),
          min_concurrency: pos_integer(),
          current_concurrency: pos_integer(),
          target_concurrency: pos_integer(),
          memory_pressure_threshold: float(),
          cpu_pressure_threshold: float(),
          scaling_factor: float(),
          adjustment_history: [map()],
          resource_metrics: map(),
          auto_scaling_enabled: boolean()
        }

  # Public API

  @doc """
  Starts the adaptive throttle manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current recommended concurrency level.
  """
  def get_current_concurrency do
    GenServer.call(__MODULE__, :get_current_concurrency)
  end

  @doc """
  Requests permission to start a new concurrent task.
  Returns {:ok, :proceed} or {:error, :throttled}.
  """
  def request_concurrency_slot do
    GenServer.call(__MODULE__, :request_slot)
  end

  @doc """
  Notifies the throttle that a concurrent task has completed.
  """
  def release_concurrency_slot do
    GenServer.cast(__MODULE__, :release_slot)
  end

  @doc """
  Forces a resource utilization check and adjustment.
  """
  def force_adjustment do
    GenServer.cast(__MODULE__, :force_adjustment)
  end

  @doc """
  Gets current resource metrics and throttle status.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Updates throttle configuration at runtime.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    min_concurrency = Keyword.get(opts, :min_concurrency, @default_min_concurrency)

    initial_concurrency = max(min_concurrency, div(max_concurrency, 2))

    state = %__MODULE__{
      max_concurrency: max_concurrency,
      min_concurrency: min_concurrency,
      current_concurrency: initial_concurrency,
      target_concurrency: initial_concurrency,
      memory_pressure_threshold:
        Keyword.get(opts, :memory_pressure_threshold, @memory_pressure_threshold),
      cpu_pressure_threshold: Keyword.get(opts, :cpu_pressure_threshold, @cpu_pressure_threshold),
      scaling_factor: Keyword.get(opts, :scaling_factor, @scaling_factor),
      adjustment_history: [],
      resource_metrics: %{},
      auto_scaling_enabled: Keyword.get(opts, :auto_scaling, true)
    }

    # Schedule periodic resource monitoring
    if state.auto_scaling_enabled do
      schedule_resource_check()
      schedule_adjustment_check()
    end

    Logger.info(
      "AdaptiveThrottle started with concurrency: #{initial_concurrency}/#{max_concurrency}"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_current_concurrency, _from, state) do
    {:reply, state.current_concurrency, state}
  end

  @impl GenServer
  def handle_call(:request_slot, _from, state) do
    active_slots = get_active_concurrency_count()

    if active_slots < state.current_concurrency do
      {:reply, {:ok, :proceed}, state}
    else
      {:reply, {:error, :throttled}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      current_concurrency: state.current_concurrency,
      target_concurrency: state.target_concurrency,
      max_concurrency: state.max_concurrency,
      min_concurrency: state.min_concurrency,
      active_slots: get_active_concurrency_count(),
      resource_metrics: state.resource_metrics,
      adjustment_history: Enum.take(state.adjustment_history, 10)
    }

    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:update_config, new_config}, _from, state) do
    updated_state = %{
      state
      | max_concurrency: Keyword.get(new_config, :max_concurrency, state.max_concurrency),
        min_concurrency: Keyword.get(new_config, :min_concurrency, state.min_concurrency),
        memory_pressure_threshold:
          Keyword.get(new_config, :memory_pressure_threshold, state.memory_pressure_threshold),
        cpu_pressure_threshold:
          Keyword.get(new_config, :cpu_pressure_threshold, state.cpu_pressure_threshold),
        auto_scaling_enabled: Keyword.get(new_config, :auto_scaling, state.auto_scaling_enabled)
    }

    # Ensure current concurrency is within new bounds
    adjusted_current =
      max(
        updated_state.min_concurrency,
        min(updated_state.current_concurrency, updated_state.max_concurrency)
      )

    final_state = %{
      updated_state
      | current_concurrency: adjusted_current,
        target_concurrency: adjusted_current
    }

    Logger.info("AdaptiveThrottle config updated, concurrency adjusted to #{adjusted_current}")
    {:reply, :ok, final_state}
  end

  @impl GenServer
  def handle_cast(:release_slot, state) do
    # Slot released, no state change needed (tracking is external)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:force_adjustment, state) do
    updated_state = check_and_adjust_concurrency(state)
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info(:check_resources, state) do
    updated_state = collect_resource_metrics(state)
    schedule_resource_check()
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info(:adjustment_check, state) do
    updated_state =
      if state.auto_scaling_enabled do
        check_and_adjust_concurrency(state)
      else
        state
      end

    schedule_adjustment_check()
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp schedule_resource_check do
    Process.send_after(self(), :check_resources, @memory_check_interval)
  end

  defp schedule_adjustment_check do
    Process.send_after(self(), :adjustment_check, @adjustment_interval)
  end

  defp collect_resource_metrics(state) do
    memory_info = :erlang.memory()
    total_memory = memory_info[:total]
    system_memory = get_system_memory_info()

    cpu_utilization = get_cpu_utilization()
    active_processes = :erlang.system_info(:process_count)

    metrics = %{
      memory: %{
        erlang_total: total_memory,
        system_total: system_memory.total,
        system_used: system_memory.used,
        memory_pressure: system_memory.used / system_memory.total
      },
      cpu: %{
        utilization: cpu_utilization,
        pressure: cpu_utilization
      },
      processes: %{
        active: active_processes,
        limit: :erlang.system_info(:process_limit)
      },
      timestamp: DateTime.utc_now()
    }

    %{state | resource_metrics: metrics}
  end

  defp get_system_memory_info do
    # Platform-specific memory information
    case :os.type() do
      {:unix, _} ->
        {output, 0} = System.cmd("free", ["-b"])
        parse_free_output(output)

      _ ->
        # Default values for non-Unix systems
        %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
    end
  rescue
    # Default 8GB/4GB
    _ -> %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
  end

  defp parse_free_output(output) do
    lines = String.split(output, "\n")

    case Enum.find(lines, &String.starts_with?(&1, "Mem:")) do
      nil ->
        %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}

      mem_line ->
        # Skip "Mem:" label
        parts = String.split(mem_line) |> Enum.drop(1)

        case parts do
          [total_str, used_str | _] ->
            %{
              total: String.to_integer(total_str),
              used: String.to_integer(used_str)
            }

          _ ->
            %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
        end
    end
  end

  defp get_cpu_utilization do
    # Simplified CPU utilization - in production would use more sophisticated monitoring
    scheduler_usage = :erlang.statistics(:scheduler_wall_time)

    if is_list(scheduler_usage) and not Enum.empty?(scheduler_usage) do
      calculate_average_scheduler_utilization(scheduler_usage)
    else
      # Default moderate utilization
      0.5
    end
  rescue
    # Default if unable to get scheduler stats
    _ -> 0.5
  end

  defp calculate_average_scheduler_utilization(scheduler_usage) do
    total_schedulers = length(scheduler_usage)

    total_utilization =
      scheduler_usage
      |> Enum.map(&calculate_scheduler_ratio/1)
      |> Enum.sum()

    total_utilization / total_schedulers
  end

  defp calculate_scheduler_ratio({_id, active, total}) do
    if total > 0, do: active / total, else: 0.0
  end

  defp check_and_adjust_concurrency(state) do
    current_metrics = state.resource_metrics

    cond do
      should_scale_down?(current_metrics, state) ->
        scale_down(state, current_metrics)

      should_scale_up?(current_metrics, state) ->
        scale_up(state, current_metrics)

      true ->
        # No adjustment needed
        state
    end
  end

  defp should_scale_down?(metrics, state) do
    memory_pressure = get_in(metrics, [:memory, :memory_pressure]) || 0.0
    cpu_pressure = get_in(metrics, [:cpu, :pressure]) || 0.0

    memory_pressure > state.memory_pressure_threshold or
      cpu_pressure > state.cpu_pressure_threshold or
      state.current_concurrency > state.max_concurrency
  end

  defp should_scale_up?(metrics, state) do
    memory_pressure = get_in(metrics, [:memory, :memory_pressure]) || 1.0
    cpu_pressure = get_in(metrics, [:cpu, :pressure]) || 1.0
    active_slots = get_active_concurrency_count()

    # Scale up if resources are available and we're at capacity
    memory_pressure < state.memory_pressure_threshold - 0.2 and
      cpu_pressure < state.cpu_pressure_threshold - 0.2 and
      active_slots >= state.current_concurrency * 0.8 and
      state.current_concurrency < state.max_concurrency
  end

  defp scale_down(state, metrics) do
    new_concurrency =
      max(
        state.min_concurrency,
        round(state.current_concurrency / state.scaling_factor)
      )

    if new_concurrency != state.current_concurrency do
      Logger.info("Scaling down concurrency: #{state.current_concurrency} -> #{new_concurrency}")

      adjustment =
        create_adjustment_record(:scale_down, state.current_concurrency, new_concurrency, metrics)

      %{
        state
        | current_concurrency: new_concurrency,
          target_concurrency: new_concurrency,
          adjustment_history: [adjustment | state.adjustment_history]
      }
    else
      state
    end
  end

  defp scale_up(state, metrics) do
    new_concurrency =
      min(
        state.max_concurrency,
        round(state.current_concurrency * state.scaling_factor)
      )

    if new_concurrency != state.current_concurrency do
      Logger.info("Scaling up concurrency: #{state.current_concurrency} -> #{new_concurrency}")

      adjustment =
        create_adjustment_record(:scale_up, state.current_concurrency, new_concurrency, metrics)

      %{
        state
        | current_concurrency: new_concurrency,
          target_concurrency: new_concurrency,
          adjustment_history: [adjustment | state.adjustment_history]
      }
    else
      state
    end
  end

  defp create_adjustment_record(action, old_concurrency, new_concurrency, metrics) do
    %{
      action: action,
      timestamp: DateTime.utc_now(),
      old_concurrency: old_concurrency,
      new_concurrency: new_concurrency,
      memory_pressure: get_in(metrics, [:memory, :memory_pressure]),
      cpu_pressure: get_in(metrics, [:cpu, :pressure]),
      reason: determine_adjustment_reason(action, metrics)
    }
  end

  defp determine_adjustment_reason(action, metrics) do
    memory_pressure = get_in(metrics, [:memory, :memory_pressure]) || 0.0
    cpu_pressure = get_in(metrics, [:cpu, :pressure]) || 0.0

    case action do
      :scale_down -> determine_scale_down_reason(memory_pressure, cpu_pressure)
      :scale_up -> determine_scale_up_reason(memory_pressure, cpu_pressure)
    end
  end

  defp determine_scale_down_reason(memory_pressure, cpu_pressure) do
    cond do
      memory_pressure > 0.9 -> :memory_critical
      memory_pressure > 0.8 -> :memory_pressure
      cpu_pressure > 0.9 -> :cpu_overload
      true -> :resource_pressure
    end
  end

  defp determine_scale_up_reason(memory_pressure, cpu_pressure) do
    cond do
      memory_pressure < 0.4 and cpu_pressure < 0.4 -> :resources_available
      memory_pressure < 0.6 and cpu_pressure < 0.6 -> :moderate_utilization
      true -> :capacity_available
    end
  end

  defp get_active_concurrency_count do
    # In production, would track active evaluation processes
    # For now, simulate based on current pipeline load
    # Check for active evaluation processes
    processes = Process.list()

    evaluation_processes =
      Enum.count(processes, fn pid ->
        case Process.info(pid, [:current_function, :initial_call]) do
          [current_function: {module, _func, _arity}]
          when module in [
                 SweBench.Pipeline.ContainerEvaluator,
                 SweBench.PatternAnalysis,
                 SweBench.FunctionalAnalysis,
                 SweBench.StaticAnalysis
               ] ->
            true

          _ ->
            false
        end
      end)

    evaluation_processes
  rescue
    _ -> 0
  end

  # Public utility functions for pipeline integration

  @doc """
  Calculates optimal concurrency for a given batch of tasks.
  """
  def calculate_optimal_concurrency(tasks, available_resources \\ %{}) do
    task_count = length(tasks)
    memory_requirement = estimate_batch_memory_requirement(tasks)
    cpu_requirement = estimate_batch_cpu_requirement(tasks)

    # Get current system resources
    current_memory = get_in(available_resources, [:memory, :available]) || get_available_memory()

    current_cpu_cores =
      get_in(available_resources, [:cpu, :cores]) || :erlang.system_info(:schedulers)

    # Calculate memory-constrained concurrency
    memory_concurrency =
      if memory_requirement > 0 do
        max(1, div(current_memory, memory_requirement))
      else
        @default_max_concurrency
      end

    # Calculate CPU-constrained concurrency
    # Use 80% of cores
    cpu_concurrency = max(1, round(current_cpu_cores * 0.8))

    # Take the most restrictive constraint
    optimal = min(task_count, min(memory_concurrency, cpu_concurrency))

    # Ensure within configured bounds
    optimal
    |> max(@default_min_concurrency)
    |> min(@default_max_concurrency)
  end

  @doc """
  Provides concurrency recommendations based on current system state.
  """
  def get_concurrency_recommendation(task_batch) do
    with {:ok, metrics} <- collect_current_metrics(),
         optimal_concurrency <- calculate_optimal_concurrency(task_batch, metrics),
         current_concurrency <- get_current_concurrency() do
      recommendation = %{
        current: current_concurrency,
        optimal: optimal_concurrency,
        adjustment_needed: optimal_concurrency != current_concurrency,
        metrics: metrics,
        reasoning:
          generate_recommendation_reasoning(current_concurrency, optimal_concurrency, metrics)
      }

      {:ok, recommendation}
    else
      error -> error
    end
  end

  # Helper functions

  defp estimate_batch_memory_requirement(tasks) do
    # Estimate memory needed for batch processing
    # 100MB per task
    base_memory_per_task = 100 * 1024 * 1024

    tasks
    |> Enum.map(fn task ->
      multiplier =
        case task.repository do
          # High memory for multimedia
          "membrane" -> 3.0
          # Numerical computing
          "nx" -> 2.5
          # Message processing
          "broadway" -> 2.0
          # Asset compilation
          "phoenix_live_view" -> 1.8
          _ -> 1.0
        end

      round(base_memory_per_task * multiplier)
    end)
    |> Enum.sum()
  end

  defp estimate_batch_cpu_requirement(tasks) do
    # Estimate CPU intensity for batch
    # Returns a score from 0.1 to 2.0
    # 30% of one core per task baseline
    base_cpu_per_task = 0.3

    tasks
    |> Enum.map(fn task ->
      case Map.get(task, :analysis_type) do
        # Dialyzer is CPU intensive
        :static_analysis -> 0.8
        # AST processing
        :pattern_analysis -> 0.5
        :functional_analysis -> 0.4
        :otp_validation -> 0.3
        _ -> 0.3
      end
    end)
    |> Enum.sum()
    |> max(base_cpu_per_task)
  end

  defp get_available_memory do
    case get_system_memory_info() do
      %{total: total, used: used} -> total - used
      # Default 4GB available
      _ -> 4 * 1024 * 1024 * 1024
    end
  end

  defp collect_current_metrics do
    memory_info = get_system_memory_info()
    cpu_utilization = get_cpu_utilization()

    metrics = %{
      memory: %{
        total: memory_info.total,
        used: memory_info.used,
        available: memory_info.total - memory_info.used,
        pressure: memory_info.used / memory_info.total
      },
      cpu: %{
        cores: :erlang.system_info(:schedulers),
        utilization: cpu_utilization,
        pressure: cpu_utilization
      },
      processes: %{
        active: :erlang.system_info(:process_count),
        limit: :erlang.system_info(:process_limit)
      }
    }

    {:ok, metrics}
  end

  defp generate_recommendation_reasoning(current, optimal, metrics) do
    memory_pressure = get_in(metrics, [:memory, :pressure]) || 0.0
    cpu_pressure = get_in(metrics, [:cpu, :pressure]) || 0.0

    cond do
      optimal > current ->
        "Scale up recommended: Memory pressure #{Float.round(memory_pressure, 2)}, CPU pressure #{Float.round(cpu_pressure, 2)}"

      optimal < current ->
        "Scale down recommended: Memory pressure #{Float.round(memory_pressure, 2)}, CPU pressure #{Float.round(cpu_pressure, 2)}"

      true ->
        "Current concurrency optimal: Memory pressure #{Float.round(memory_pressure, 2)}, CPU pressure #{Float.round(cpu_pressure, 2)}"
    end
  end
end
