defmodule SweBench.PartialCreditScoring.QualityScorer do
  @moduledoc """
  Scores code quality using existing static analysis infrastructure.

  Integrates with existing Credo and Dialyzer analysis to provide quality
  scoring. Provides 75% threshold scoring based on quality achievements.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the quality scorer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Scores code quality for the given solution.
  """
  def score(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:score, solution_data, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("QualityScorer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:score, solution_data, _options}, _from, state) do
    score_result = evaluate_quality(solution_data, state.config)
    {:reply, {:ok, score_result}, state}
  rescue
    error ->
      Logger.error("Quality scoring failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp evaluate_quality(solution_data, config) do
    quality_threshold = get_in(config, [:dimensions, :code_quality, :threshold]) || 75

    # Extract quality metrics from solution data
    credo_score = Map.get(solution_data, :credo_score, 50.0)
    dialyzer_issues = Map.get(solution_data, :dialyzer_issues, [])
    pattern_analysis_score = Map.get(solution_data, :pattern_analysis_score, 50.0)

    # Calculate composite quality score
    base_score = credo_score * 0.4 + pattern_analysis_score * 0.4
    dialyzer_penalty = length(dialyzer_issues) * 5.0
    final_score = max(0.0, base_score - dialyzer_penalty + 20.0)

    %{
      score: final_score,
      threshold_met: final_score >= quality_threshold,
      details: %{
        credo_score: credo_score,
        dialyzer_issues: length(dialyzer_issues),
        pattern_analysis_score: pattern_analysis_score,
        composite_score: final_score,
        quality_issues: categorize_quality_issues(solution_data),
        threshold: quality_threshold
      }
    }
  end

  defp categorize_quality_issues(solution_data) do
    credo_issues = Map.get(solution_data, :credo_issues, [])
    dialyzer_issues = Map.get(solution_data, :dialyzer_issues, [])

    %{
      credo: Enum.map(credo_issues, &categorize_credo_issue/1),
      dialyzer: Enum.map(dialyzer_issues, &categorize_dialyzer_issue/1)
    }
  end

  defp categorize_credo_issue(issue) when is_map(issue) do
    %{
      category: Map.get(issue, :category, "unknown"),
      priority: Map.get(issue, :priority, :low),
      message: Map.get(issue, :message, "No message")
    }
  end

  defp categorize_credo_issue(issue) do
    %{
      category: "unknown",
      priority: :low,
      message: to_string(issue)
    }
  end

  defp categorize_dialyzer_issue(issue) when is_map(issue) do
    %{
      type: Map.get(issue, :type, "type_error"),
      severity: determine_dialyzer_severity(issue),
      message: Map.get(issue, :message, "No message")
    }
  end

  defp categorize_dialyzer_issue(issue) do
    %{
      type: "unknown",
      severity: :minor,
      message: to_string(issue)
    }
  end

  defp determine_dialyzer_severity(issue) do
    message = Map.get(issue, :message, "")

    cond do
      String.contains?(message, "no_return") -> :critical
      String.contains?(message, "contract") -> :major
      String.contains?(message, "type") -> :minor
      true -> :minor
    end
  end
end
