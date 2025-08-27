defmodule SweBench.ConcurrentEvaluation.ProcessMonitor do
  @moduledoc """
  BEAM VM process lifecycle tracking and metrics collection.

  Monitors process creation, termination, memory usage, and message queue
  characteristics during concurrent system evaluation.
  """

  use GenServer
  require Logger

  alias SweBench.ConcurrentEvaluation.DecisionEngine

  defstruct [
    :config,
    :monitoring_tier,
    :active_processes,
    :process_metrics,
    :sampling_rate
  ]

  @doc """
  Starts the process monitor with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Analyzes processes during solution execution.
  """
  def analyze_processes(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:analyze_processes, solution_data, monitoring_tier}, 60_000)
  end

  @doc """
  Returns current process monitoring statistics.
  """
  def get_process_statistics do
    GenServer.call(__MODULE__, :get_process_statistics)
  end

  @impl true
  def init(config) do
    monitoring_config = Enum.into(config, %{})

    state = %__MODULE__{
      config: monitoring_config,
      monitoring_tier: Map.get(monitoring_config, :monitoring_tier, :standard),
      active_processes: %{},
      process_metrics: initialize_process_metrics(),
      sampling_rate: Map.get(monitoring_config, :process_sampling_rate, 0.3)
    }

    Logger.info("ProcessMonitor initialized with #{state.monitoring_tier} tier")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_processes, solution_data, monitoring_tier}, _from, state) do
    monitoring_config = DecisionEngine.get_monitoring_config(monitoring_tier)

    analysis_result = perform_process_analysis(solution_data, monitoring_config, state)

    {:reply, {:ok, analysis_result}, state}
  rescue
    error ->
      Logger.error("Process analysis failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  @impl true
  def handle_call(:get_process_statistics, _from, state) do
    {:reply, state.process_metrics, state}
  end

  # Private functions

  defp perform_process_analysis(solution_data, monitoring_config, _state) do
    # Get baseline process count before execution
    initial_process_count = :erlang.system_info(:process_count)

    # Set up process monitoring based on tier
    setup_process_monitoring(monitoring_config)

    # Execute solution code while monitoring
    execution_result = execute_with_monitoring(solution_data, monitoring_config)

    # Collect final metrics
    final_process_count = :erlang.system_info(:process_count)
    process_metrics = collect_process_metrics(initial_process_count, final_process_count)

    # Analyze collected data
    analysis = analyze_process_behavior(execution_result, process_metrics, monitoring_config)

    %{
      process_metrics: process_metrics,
      process_analysis: analysis,
      monitoring_tier: Map.get(monitoring_config, :tier, :standard),
      execution_result: execution_result,
      score: calculate_process_score(analysis)
    }
  end

  defp setup_process_monitoring(monitoring_config) do
    sampling_rate = Map.get(monitoring_config, :process_sampling_rate, 0.3)

    # Enable process tracing based on sampling rate
    if sampling_rate > 0.5 do
      # High sampling - enable comprehensive tracing
      :erlang.trace(:processes, true, [:procs, :running, :exiting])
    else
      # Light sampling - minimal tracing
      :erlang.trace(:processes, true, [:procs])
    end
  end

  defp execute_with_monitoring(solution_data, monitoring_config) do
    solution_code = Map.get(solution_data, :solution_code, "")

    # Create isolated execution environment
    execution_pid =
      spawn_link(fn ->
        try do
          # Execute solution in monitored environment
          result = execute_solution_safely(solution_code)
          send(self(), {:execution_complete, result})
        rescue
          error ->
            send(self(), {:execution_failed, error})
        end
      end)

    # Monitor execution with timeout
    timeout = Map.get(monitoring_config, :execution_timeout, 30_000)

    receive do
      {:execution_complete, result} ->
        {:ok, result}

      {:execution_failed, error} ->
        {:error, error}
    after
      timeout ->
        Process.exit(execution_pid, :kill)
        {:error, :execution_timeout}
    end
  end

  defp execute_solution_safely(_solution_code) do
    # This would integrate with existing test runner for safe code execution
    # For now, return a mock result
    %{
      execution_successful: true,
      processes_spawned: :rand.uniform(10),
      messages_sent: :rand.uniform(100),
      execution_time: :rand.uniform(1000)
    }
  end

  defp collect_process_metrics(initial_count, final_count) do
    system_info = %{
      total_processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      memory_total: :erlang.memory(:total),
      memory_processes: :erlang.memory(:processes),
      memory_processes_used: :erlang.memory(:processes_used)
    }

    process_diff = %{
      initial_process_count: initial_count,
      final_process_count: final_count,
      net_process_change: final_count - initial_count,
      process_creation_rate: max(0, final_count - initial_count)
    }

    Map.merge(system_info, process_diff)
  end

  defp analyze_process_behavior(execution_result, process_metrics, monitoring_config) do
    case execution_result do
      {:ok, result} ->
        %{
          execution_successful: true,
          process_lifecycle_healthy: analyze_process_lifecycle(process_metrics),
          resource_usage_healthy: analyze_resource_usage(process_metrics),
          cleanup_successful: analyze_cleanup(process_metrics),
          performance_impact: analyze_performance_impact(result, monitoring_config),
          issues_detected: 0
        }

      {:error, reason} ->
        %{
          execution_successful: false,
          error_reason: reason,
          process_lifecycle_healthy: false,
          resource_usage_healthy: false,
          cleanup_successful: false,
          performance_impact: :unknown,
          issues_detected: 1
        }
    end
  end

  defp analyze_process_lifecycle(process_metrics) do
    net_change = Map.get(process_metrics, :net_process_change, 0)

    # Healthy if process count returns to baseline (within tolerance)
    abs(net_change) <= 5
  end

  defp analyze_resource_usage(process_metrics) do
    total_memory = Map.get(process_metrics, :memory_total, 0)
    process_memory = Map.get(process_metrics, :memory_processes, 0)

    # Healthy if process memory is reasonable proportion of total
    if total_memory > 0 do
      process_memory / total_memory < 0.8
    else
      true
    end
  end

  defp analyze_cleanup(process_metrics) do
    # Check if processes were properly cleaned up
    final_count = Map.get(process_metrics, :final_process_count, 0)
    process_limit = Map.get(process_metrics, :process_limit, 262_144)

    # Healthy if we're not approaching process limits
    final_count < process_limit * 0.9
  end

  defp analyze_performance_impact(result, monitoring_config) do
    execution_time = Map.get(result, :execution_time, 0)
    tier = Map.get(monitoring_config, :tier, :standard)

    # Estimate monitoring overhead based on tier
    case tier do
      :light -> min(execution_time * 0.1, execution_time)
      :standard -> min(execution_time * 0.3, execution_time)
      :intensive -> min(execution_time * 0.7, execution_time)
    end
  end

  defp calculate_process_score(analysis) do
    if Map.get(analysis, :execution_successful, false) do
      base_score = 70.0

      score =
        if Map.get(analysis, :process_lifecycle_healthy, false),
          do: base_score + 10.0,
          else: base_score

      score = if Map.get(analysis, :resource_usage_healthy, false), do: score + 10.0, else: score
      score = if Map.get(analysis, :cleanup_successful, false), do: score + 10.0, else: score

      min(100.0, score)
    else
      20.0
    end
  end

  defp initialize_process_metrics do
    %{
      total_analyses: 0,
      successful_analyses: 0,
      failed_analyses: 0,
      average_process_count: 0.0,
      max_process_count_seen: 0,
      total_memory_peak: 0
    }
  end
end
