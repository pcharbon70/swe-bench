defmodule SweBench.ConcurrentEvaluation.SupervisorTracker do
  @moduledoc """
  Supervision tree monitoring and cascade analysis.

  Tracks supervisor behavior, restart patterns, and resilience under
  fault injection scenarios.
  """

  use GenServer
  require Logger

  defstruct [:config, :supervisor_registry, :restart_patterns]

  @doc """
  Starts the supervisor tracker with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Tracks supervision behavior during solution execution.
  """
  def track_supervision(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:track_supervision, solution_data, monitoring_tier}, 60_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      supervisor_registry: %{},
      restart_patterns: []
    }

    Logger.info("SupervisorTracker initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:track_supervision, solution_data, monitoring_tier}, _from, state) do
    supervision_analysis = perform_supervision_tracking(solution_data, monitoring_tier, state)
    {:reply, {:ok, supervision_analysis}, state}
  rescue
    error ->
      Logger.error("Supervision tracking failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_supervision_tracking(solution_data, _monitoring_tier, _state) do
    solution_code = Map.get(solution_data, :solution_code, "")
    
    supervision_analysis = analyze_supervision_patterns(solution_code)
    
    %{
      supervisor_tree_health: supervision_analysis.tree_health,
      restart_strategy_analysis: supervision_analysis.restart_strategies,
      cascade_failure_resilience: supervision_analysis.cascade_resilience,
      child_spec_validation: supervision_analysis.child_specs,
      issues_detected: supervision_analysis.total_issues,
      score: calculate_supervision_score(supervision_analysis)
    }
  end

  defp analyze_supervision_patterns(code) do
    %{
      tree_health: analyze_supervisor_tree_health(code),
      restart_strategies: analyze_restart_strategies(code), 
      cascade_resilience: analyze_cascade_resilience(code),
      child_specs: analyze_child_specifications(code),
      total_issues: 0  # Will be calculated
    }
    |> calculate_supervision_issues()
  end

  defp analyze_supervisor_tree_health(code) do
    %{
      has_supervisor: String.contains?(code, "Supervisor") or String.contains?(code, "use Supervisor"),
      proper_initialization: String.contains?(code, "Supervisor.start_link"),
      child_management: String.contains?(code, "children = [")
    }
  end

  defp analyze_restart_strategies(code) do
    strategies = [
      {:one_for_one, String.contains?(code, ":one_for_one")},
      {:one_for_all, String.contains?(code, ":one_for_all")},
      {:rest_for_one, String.contains?(code, ":rest_for_one")},
      {:simple_one_for_one, String.contains?(code, ":simple_one_for_one")}
    ]
    
    detected_strategies = strategies
    |> Enum.filter(fn {_, detected} -> detected end)
    |> Enum.map(fn {strategy, _} -> strategy end)
    
    %{
      strategies_used: detected_strategies,
      strategy_count: length(detected_strategies),
      has_restart_limits: String.contains?(code, "max_restarts") or String.contains?(code, "max_seconds")
    }
  end

  defp analyze_cascade_resilience(code) do
    %{
      has_isolation: String.contains?(code, "DynamicSupervisor") or String.contains?(code, ":temporary"),
      error_handling: String.contains?(code, "terminate") or String.contains?(code, "handle_exit"),
      restart_bounds: String.contains?(code, "max_restarts")
    }
  end

  defp analyze_child_specifications(code) do
    %{
      has_child_specs: String.contains?(code, "child_spec") or String.contains?(code, "children = ["),
      proper_restart_types: analyze_restart_types(code),
      shutdown_handling: String.contains?(code, "shutdown:") or String.contains?(code, ":brutal_kill")
    }
  end

  defp analyze_restart_types(code) do
    restart_types = [
      String.contains?(code, ":permanent"),
      String.contains?(code, ":temporary"), 
      String.contains?(code, ":transient")
    ]
    
    Enum.any?(restart_types)
  end

  defp calculate_supervision_issues(analysis) do
    issue_count = 0
    
    # Count issues based on missing patterns
    tree_health = analysis.tree_health
    issue_count = if not Map.get(tree_health, :has_supervisor, false),
                  do: issue_count + 1, else: issue_count
    
    restart_analysis = analysis.restart_strategies  
    issue_count = if not Map.get(restart_analysis, :has_restart_limits, false),
                  do: issue_count + 1, else: issue_count
    
    %{analysis | total_issues: issue_count}
  end

  defp calculate_supervision_score(analysis) do
    total_issues = Map.get(analysis, :total_issues, 0)
    
    base_score = 80.0
    penalty = total_issues * 20.0
    
    max(0.0, base_score - penalty)
  end
end