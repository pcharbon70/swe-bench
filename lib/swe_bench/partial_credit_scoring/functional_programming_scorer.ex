defmodule SweBench.PartialCreditScoring.FunctionalProgrammingScorer do
  @moduledoc """
  Scores functional programming adherence and pattern usage.

  Evaluates usage of immutability, recursion, pattern matching, and other
  functional programming principles using existing analysis infrastructure.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the functional programming scorer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Scores functional programming adherence for the given solution.
  """
  def score(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:score, solution_data, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("FunctionalProgrammingScorer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:score, solution_data, _options}, _from, state) do
    score_result = evaluate_functional_programming(solution_data, state.config)
    {:reply, {:ok, score_result}, state}
  rescue
    error ->
      Logger.error("FP scoring failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp evaluate_functional_programming(solution_data, config) do
    fp_threshold = get_in(config, [:dimensions, :functional_programming, :threshold]) || 85

    # Extract functional programming metrics
    immutability_score = Map.get(solution_data, :immutability_score, 50.0)
    recursion_score = Map.get(solution_data, :recursion_score, 50.0)
    pattern_matching_score = Map.get(solution_data, :pattern_matching_score, 50.0)
    pipeline_score = Map.get(solution_data, :pipeline_score, 50.0)
    purity_score = Map.get(solution_data, :purity_score, 50.0)

    # Calculate composite functional programming score
    composite_score =
      immutability_score * 0.25 +
        recursion_score * 0.20 +
        pattern_matching_score * 0.25 +
        pipeline_score * 0.15 +
        purity_score * 0.15

    %{
      score: composite_score,
      threshold_met: composite_score >= fp_threshold,
      details: %{
        immutability_score: immutability_score,
        recursion_score: recursion_score,
        pattern_matching_score: pattern_matching_score,
        pipeline_score: pipeline_score,
        purity_score: purity_score,
        composite_score: composite_score,
        fp_patterns: analyze_fp_patterns(solution_data),
        threshold: fp_threshold
      }
    }
  end

  defp analyze_fp_patterns(solution_data) do
    %{
      immutable_structures: Map.get(solution_data, :uses_immutable_structures, false),
      recursive_algorithms: Map.get(solution_data, :uses_recursion, false),
      pattern_matching: Map.get(solution_data, :uses_pattern_matching, false),
      pipe_operators: Map.get(solution_data, :uses_pipe_operator, false),
      pure_functions: Map.get(solution_data, :has_pure_functions, false),
      higher_order_functions: Map.get(solution_data, :uses_higher_order_functions, false),
      guard_clauses: Map.get(solution_data, :uses_guard_clauses, false)
    }
  end
end
