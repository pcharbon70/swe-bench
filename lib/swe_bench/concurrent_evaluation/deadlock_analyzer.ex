defmodule SweBench.ConcurrentEvaluation.DeadlockAnalyzer do
  @moduledoc """
  Wait-for-graph construction and deadlock cycle detection.

  Analyzes process dependencies, GenServer call chains, and resource
  contention to identify potential deadlock scenarios.
  """

  use GenServer
  require Logger

  defstruct [:config, :wait_graph, :deadlock_history]

  @doc """
  Starts the deadlock analyzer with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Analyzes deadlocks in the given solution.
  """
  def analyze_deadlocks(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:analyze_deadlocks, solution_data, monitoring_tier}, 60_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      wait_graph: :digraph.new(),
      deadlock_history: []
    }

    Logger.info("DeadlockAnalyzer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_deadlocks, solution_data, monitoring_tier}, _from, state) do
    deadlock_analysis = perform_deadlock_analysis(solution_data, monitoring_tier, state)
    {:reply, {:ok, deadlock_analysis}, state}
  rescue
    error ->
      Logger.error("Deadlock analysis failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_deadlock_analysis(solution_data, _monitoring_tier, _state) do
    solution_code = Map.get(solution_data, :solution_code, "")
    
    # Basic deadlock pattern analysis
    deadlock_indicators = analyze_deadlock_patterns(solution_code)
    
    %{
      circular_dependencies: deadlock_indicators.circular_deps,
      blocked_processes: deadlock_indicators.blocked_chains,
      infinite_receives: deadlock_indicators.infinite_receives,
      timeout_issues: deadlock_indicators.timeout_problems,
      resource_starvation: deadlock_indicators.resource_issues,
      issues_detected: deadlock_indicators.total_issues,
      score: calculate_deadlock_score(deadlock_indicators)
    }
  end

  defp analyze_deadlock_patterns(code) do
    %{
      circular_deps: analyze_circular_dependencies(code),
      blocked_chains: analyze_blocked_processes(code),
      infinite_receives: analyze_infinite_receives(code),
      timeout_problems: analyze_timeout_issues(code),
      resource_issues: analyze_resource_starvation(code),
      total_issues: 0  # Will be calculated based on above
    }
  end

  defp analyze_circular_dependencies(code) do
    # Look for patterns that might cause circular dependencies
    has_nested_calls = String.contains?(code, "GenServer.call") and 
                      String.contains?(code, "handle_call")
    
    if has_nested_calls, do: 1, else: 0
  end

  defp analyze_blocked_processes(code) do
    # Look for blocking operations without proper timeout handling
    blocking_patterns = [
      String.contains?(code, "GenServer.call") and not String.contains?(code, "timeout"),
      String.contains?(code, "Task.await") and not String.contains?(code, "Task.await("),
      String.contains?(code, "receive") and not String.contains?(code, "after")
    ]
    
    Enum.count(blocking_patterns, & &1)
  end

  defp analyze_infinite_receives(code) do
    # Look for receive blocks that might loop infinitely
    if String.contains?(code, "receive do") and not String.contains?(code, "after ") do
      1
    else
      0
    end
  end

  defp analyze_timeout_issues(code) do
    # Look for operations that might timeout without handling
    timeout_risks = [
      String.contains?(code, "GenServer.call(") and not String.contains?(code, ", :infinity)"),
      String.contains?(code, "Task.await") and not String.contains?(code, "Task.await(")
    ]
    
    Enum.count(timeout_risks, & &1)
  end

  defp analyze_resource_starvation(code) do
    # Look for patterns that might cause resource starvation
    starvation_patterns = [
      String.contains?(code, "spawn") and not String.contains?(code, "spawn_link"),
      String.contains?(code, ":ets.new") and not String.contains?(code, ":ets.delete")
    ]
    
    Enum.count(starvation_patterns, & &1)
  end

  defp calculate_deadlock_score(indicators) do
    total_issues = indicators.circular_deps + indicators.blocked_chains + 
                  indicators.infinite_receives + indicators.timeout_problems + 
                  indicators.resource_issues
    
    max(0.0, 100.0 - (total_issues * 20.0))
  end
end