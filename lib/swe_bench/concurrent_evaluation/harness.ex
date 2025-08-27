defmodule SweBench.ConcurrentEvaluation.Harness do
  @moduledoc """
  Main concurrent test coordination and orchestration.

  Provides intelligent monitoring activation and comprehensive concurrent
  system evaluation for AI-generated Elixir code targeting BEAM VM
  concurrency patterns and actor model implementations.
  """

  use GenServer
  require Logger

  alias SweBench.ConcurrentEvaluation.{
    DecisionEngine,
    MetricsCollector,
    ProcessMonitor,
    RaceDetector,
    DeadlockAnalyzer,
    MailboxMonitor,
    SupervisorTracker,
    FaultInjector
  }

  defstruct [
    :config,
    :active_evaluations,
    :monitoring_tier,
    :evaluation_metrics,
    :circuit_breaker_state
  ]

  @doc """
  Starts the concurrent evaluation harness with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Evaluates concurrent system behavior for a solution.

  Returns comprehensive concurrent system analysis including race conditions,
  deadlocks, mailbox health, and supervision tree resilience.
  """
  def evaluate_concurrent_system(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:evaluate_concurrent_system, solution_data, options}, 120_000)
  end

  @doc """
  Returns current evaluation metrics and statistics.
  """
  def get_evaluation_metrics do
    GenServer.call(__MODULE__, :get_evaluation_metrics)
  end

  @doc """
  Updates the monitoring configuration.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  @impl true
  def init(config) do
    concurrent_config = build_concurrent_config(config)
    
    state = %__MODULE__{
      config: concurrent_config,
      active_evaluations: %{},
      monitoring_tier: :standard,
      evaluation_metrics: initialize_evaluation_metrics(),
      circuit_breaker_state: :closed
    }

    Logger.info("ConcurrentEvaluation.Harness initialized with #{state.monitoring_tier} monitoring")
    {:ok, state}
  end

  @impl true
  def handle_call({:evaluate_concurrent_system, solution_data, options}, from, state) do
    evaluation_id = generate_evaluation_id()
    
    # Determine monitoring tier based on solution complexity
    monitoring_tier = DecisionEngine.determine_monitoring_tier(solution_data, options)
    
    # Check circuit breaker state
    case state.circuit_breaker_state do
      :open ->
        {:reply, {:error, :circuit_breaker_open}, state}
      
      _ ->
        # Start concurrent evaluation
        evaluation_task = Task.async(fn ->
          perform_concurrent_evaluation(solution_data, monitoring_tier, state.config)
        end)
        
        # Store evaluation for monitoring
        new_evaluations = Map.put(state.active_evaluations, evaluation_id, %{
          task: evaluation_task,
          from: from,
          solution_data: solution_data,
          monitoring_tier: monitoring_tier,
          started_at: DateTime.utc_now()
        })
        
        # Process results asynchronously
        spawn_link(fn -> 
          monitor_evaluation_completion(evaluation_id, evaluation_task)
        end)
        
        new_state = %{state | 
          active_evaluations: new_evaluations,
          monitoring_tier: monitoring_tier
        }
        
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:get_evaluation_metrics, _from, state) do
    {:reply, state.evaluation_metrics, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    new_state = %{state | config: updated_config}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:evaluation_complete, evaluation_id, result}, state) do
    case Map.get(state.active_evaluations, evaluation_id) do
      nil ->
        {:noreply, state}
      
      evaluation_info ->
        GenServer.reply(evaluation_info.from, result)
        
        # Update metrics
        new_metrics = update_evaluation_metrics(
          state.evaluation_metrics,
          evaluation_info,
          result
        )
        
        # Update circuit breaker state
        new_circuit_state = update_circuit_breaker(state.circuit_breaker_state, result)
        
        # Clean up evaluation
        new_evaluations = Map.delete(state.active_evaluations, evaluation_id)
        
        new_state = %{state |
          active_evaluations: new_evaluations,
          evaluation_metrics: new_metrics,
          circuit_breaker_state: new_circuit_state
        }
        
        {:noreply, new_state}
    end
  end

  # Private functions

  defp perform_concurrent_evaluation(solution_data, monitoring_tier, config) do
    with {:ok, process_analysis} <- ProcessMonitor.analyze_processes(solution_data, monitoring_tier),
         {:ok, race_analysis} <- RaceDetector.detect_race_conditions(solution_data, monitoring_tier),
         {:ok, deadlock_analysis} <- DeadlockAnalyzer.analyze_deadlocks(solution_data, monitoring_tier),
         {:ok, mailbox_analysis} <- MailboxMonitor.monitor_mailboxes(solution_data, monitoring_tier),
         {:ok, supervisor_analysis} <- SupervisorTracker.track_supervision(solution_data, monitoring_tier),
         {:ok, fault_analysis} <- maybe_inject_faults(solution_data, monitoring_tier, config) do
      
      # Aggregate concurrent system analysis
      concurrent_result = %{
        process_analysis: process_analysis,
        race_conditions: race_analysis,
        deadlock_analysis: deadlock_analysis,
        mailbox_health: mailbox_analysis,
        supervisor_resilience: supervisor_analysis,
        fault_tolerance: fault_analysis,
        monitoring_tier: monitoring_tier,
        overall_score: calculate_concurrent_score([
          process_analysis, race_analysis, deadlock_analysis,
          mailbox_analysis, supervisor_analysis, fault_analysis
        ]),
        timestamp: DateTime.utc_now()
      }
      
      {:ok, concurrent_result}
    else
      {:error, reason} ->
        Logger.warning("Concurrent evaluation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_inject_faults(solution_data, monitoring_tier, config) do
    if should_inject_faults?(monitoring_tier, config) do
      FaultInjector.inject_faults(solution_data, monitoring_tier)
    else
      {:ok, %{fault_injection_enabled: false, resilience_score: :not_tested}}
    end
  end

  defp should_inject_faults?(:intensive, config) do
    Map.get(config, :fault_injection_enabled, true)
  end

  defp should_inject_faults?(:standard, config) do
    Map.get(config, :basic_fault_injection, false)
  end

  defp should_inject_faults?(_, _), do: false

  defp calculate_concurrent_score(analyses) do
    scores = analyses
    |> Enum.map(fn analysis -> Map.get(analysis, :score, 50.0) end)
    |> Enum.filter(fn score -> is_number(score) end)
    
    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      50.0
    end
  end

  defp monitor_evaluation_completion(evaluation_id, task) do
    try do
      result = Task.await(task, 120_000)
      send(__MODULE__, {:evaluation_complete, evaluation_id, result})
    catch
      :exit, reason ->
        send(__MODULE__, {:evaluation_complete, evaluation_id, {:error, {:timeout, reason}}})
    end
  end

  defp generate_evaluation_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  defp build_concurrent_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      monitoring_tier: :standard,
      max_concurrent_evaluations: 5,
      evaluation_timeout: 120_000,
      fault_injection_enabled: false,
      basic_fault_injection: false,
      circuit_breaker_enabled: true,
      circuit_breaker_threshold: 0.5,
      circuit_breaker_timeout: 60_000,
      process_sampling_rate: 0.3,
      metrics_interval: 2_000,
      deadlock_check_interval: 5_000
    }
  end

  defp initialize_evaluation_metrics do
    %{
      total_evaluations: 0,
      successful_evaluations: 0,
      failed_evaluations: 0,
      average_evaluation_time: 0.0,
      concurrent_issues_detected: %{
        race_conditions: 0,
        deadlocks: 0,
        mailbox_problems: 0,
        supervisor_failures: 0
      },
      monitoring_tier_usage: %{
        light: 0,
        standard: 0,
        intensive: 0
      },
      started_at: DateTime.utc_now()
    }
  end

  defp update_evaluation_metrics(metrics, evaluation_info, result) do
    evaluation_time = DateTime.diff(DateTime.utc_now(), evaluation_info.started_at, :millisecond)
    total = metrics.total_evaluations + 1
    tier = evaluation_info.monitoring_tier
    
    # Update tier usage
    new_tier_usage = Map.update(metrics.monitoring_tier_usage, tier, 1, &(&1 + 1))
    
    case result do
      {:ok, concurrent_result} ->
        # Count detected issues
        new_issues = count_detected_issues(concurrent_result)
        updated_issues = merge_issue_counts(metrics.concurrent_issues_detected, new_issues)
        
        %{metrics |
          total_evaluations: total,
          successful_evaluations: metrics.successful_evaluations + 1,
          average_evaluation_time: (metrics.average_evaluation_time * (total - 1) + evaluation_time) / total,
          concurrent_issues_detected: updated_issues,
          monitoring_tier_usage: new_tier_usage
        }
      
      {:error, _reason} ->
        %{metrics |
          total_evaluations: total,
          failed_evaluations: metrics.failed_evaluations + 1,
          average_evaluation_time: (metrics.average_evaluation_time * (total - 1) + evaluation_time) / total,
          monitoring_tier_usage: new_tier_usage
        }
    end
  end

  defp count_detected_issues(concurrent_result) do
    %{
      race_conditions: count_issues(concurrent_result.race_conditions),
      deadlocks: count_issues(concurrent_result.deadlock_analysis),
      mailbox_problems: count_issues(concurrent_result.mailbox_health),
      supervisor_failures: count_issues(concurrent_result.supervisor_resilience)
    }
  end

  defp count_issues(analysis) when is_map(analysis) do
    Map.get(analysis, :issues_detected, 0)
  end

  defp count_issues(_), do: 0

  defp merge_issue_counts(current, new) do
    Map.merge(current, new, fn _key, current_count, new_count ->
      current_count + new_count
    end)
  end

  defp update_circuit_breaker(:closed, {:error, _reason}) do
    # TODO: Implement sophisticated circuit breaker logic
    :half_open
  end

  defp update_circuit_breaker(state, {:ok, _result}) do
    if state in [:half_open, :open], do: :closed, else: state
  end

  defp update_circuit_breaker(state, _), do: state
end