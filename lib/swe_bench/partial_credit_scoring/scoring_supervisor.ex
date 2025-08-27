defmodule SweBench.PartialCreditScoring.ScoringSupervisor do
  @moduledoc """
  OTP Supervisor for the partial credit scoring system.

  Manages all scoring processes with fault tolerance and automatic restart
  capabilities. Provides supervision tree architecture for reliable scoring
  operations.
  """

  use Supervisor

  alias SweBench.PartialCreditScoring.{
    MultiDimensionalScorer,
    CompilationScorer,
    TestScorer,
    QualityScorer,
    PerformanceScorer,
    FunctionalProgrammingScorer,
    ErrorCategorizer,
    SolutionAnalyzer,
    ScoreAggregator,
    ImprovementSuggester
  }

  @doc """
  Starts the scoring supervisor with the given configuration.
  """
  def start_link(config \\ []) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    scoring_config = Keyword.get(config, :scoring_config, default_config())

    children = [
      # Core scoring coordinator
      {MultiDimensionalScorer, scoring_config},

      # Individual dimension scorers
      {CompilationScorer, scoring_config},
      {TestScorer, scoring_config},
      {QualityScorer, scoring_config},
      {PerformanceScorer, scoring_config},
      {FunctionalProgrammingScorer, scoring_config},

      # Analysis engines
      {ErrorCategorizer, scoring_config},
      {SolutionAnalyzer, scoring_config},
      {ImprovementSuggester, scoring_config},

      # Score aggregation system
      {ScoreAggregator, scoring_config}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc """
  Returns the default scoring configuration.
  """
  def default_config do
    %{
      dimensions: %{
        compilation: %{weight: 0.15, threshold: 25},
        partial_tests: %{weight: 0.35, threshold: 50},
        code_quality: %{weight: 0.25, threshold: 75},
        performance: %{weight: 0.15, threshold: 90},
        functional_programming: %{weight: 0.10, threshold: 85}
      },
      error_categories: %{
        compilation: [:syntax_error, :type_error, :missing_dependency, :macro_error],
        test: [:assertion_failure, :timeout, :setup_error, :teardown_error],
        runtime: [:exception, :crash, :infinite_loop, :memory_error],
        logic: [:incorrect_output, :edge_case_failure, :algorithm_error, :data_structure_misuse]
      },
      minimum_score_difference: 0.10,
      aggregation_strategy: :weighted_average,
      improvement_suggestions: true,
      timeout: 30_000,
      max_retries: 3
    }
  end

  @doc """
  Returns health status of all scoring processes.
  """
  def health_check do
    children = Supervisor.which_children(__MODULE__)

    children
    |> Enum.map(fn {name, pid, _type, _modules} ->
      case Process.alive?(pid) do
        true -> {name, :healthy}
        false -> {name, :unhealthy}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns configuration for the scoring system.
  """
  def get_config do
    case GenServer.call(MultiDimensionalScorer, :get_config) do
      {:ok, config} -> config
      {:error, _reason} -> default_config()
    end
  rescue
    _error -> default_config()
  end
end