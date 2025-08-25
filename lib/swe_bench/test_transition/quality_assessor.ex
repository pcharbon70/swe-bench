defmodule SweBench.TestTransition.QualityAssessor do
  @moduledoc """
  Quality assessment for test transition validation results.

  Implements sophisticated quality tier classification based on transition
  patterns, consistency metrics, and suitability for benchmark tasks.
  """

  require Logger

  @doc """
  Assesses the quality tier for a validation analysis.

  ## Quality Tiers
    - :gold - Excellent: Clean FAIL_TO_PASS with high confidence and no regressions
    - :silver - Good: FAIL_TO_PASS with minor issues or moderate confidence
    - :bronze - Acceptable: FAIL_TO_PASS with some concerns but usable
    - :unsuitable - Poor: No clear FAIL_TO_PASS or significant issues

  ## Parameters
    - analysis: Comprehensive validation analysis with transitions and metrics

  ## Returns
    - {:ok, quality_tier} - Quality assessment result
    - {:error, reason} - Assessment failure details
  """
  def assess_quality(analysis) do
    Logger.debug("Assessing quality for validation analysis")

    analysis
    |> extract_quality_factors()
    |> apply_quality_rules()
    |> determine_final_tier()
  rescue
    error ->
      Logger.error("Quality assessment failed: #{inspect(error)}")
      {:error, {:assessment_failed, error}}
  end

  # Private implementation functions

  defp extract_quality_factors(analysis) do
    _transitions = analysis.transitions
    metrics = Map.get(analysis, :metrics, %{})

    factors = %{
      # Core transition metrics
      fail_to_pass_count: Map.get(metrics, :fail_to_pass_count, 0),
      pass_to_fail_count: Map.get(metrics, :pass_to_fail_count, 0),
      total_tests: Map.get(metrics, :total_tests, 0),

      # Quality indicators
      consistency_score: analysis.consistency_score,
      confidence_level: analysis.confidence_level,
      flakiness_score: Map.get(metrics, :flakiness_score, 0.0),
      flaky_test_count: Map.get(metrics, :flaky_test_count, 0),

      # Transition patterns
      transition_diversity: Map.get(metrics, :transition_diversity, 0.0),
      has_meaningful_fix: Map.get(metrics, :fail_to_pass_count, 0) > 0,
      has_regressions: Map.get(metrics, :pass_to_fail_count, 0) > 0,

      # Statistical measures
      sample_size_adequate: Map.get(metrics, :total_tests, 0) >= 3
    }

    {:ok, factors}
  end

  defp apply_quality_rules({:ok, factors}) do
    rules = [
      # Gold tier requirements
      &assess_gold_tier_eligibility/1,
      # Silver tier requirements
      &assess_silver_tier_eligibility/1,
      # Bronze tier requirements
      &assess_bronze_tier_eligibility/1,
      # Unsuitable conditions
      &assess_unsuitability/1
    ]

    assessment_results =
      rules
      |> Enum.map(fn rule -> rule.(factors) end)
      |> Enum.filter(&match?({:eligible, _}, &1))

    {:ok, {factors, assessment_results}}
  end

  defp apply_quality_rules({:error, reason}) do
    {:error, reason}
  end

  defp assess_gold_tier_eligibility(factors) do
    if factors.has_meaningful_fix and
         factors.confidence_level >= 0.95 and
         factors.consistency_score >= 0.95 and
         not factors.has_regressions and
         factors.flaky_test_count == 0 and
         factors.sample_size_adequate do
      {:eligible, :gold}
    else
      {:not_eligible, :gold}
    end
  end

  defp assess_silver_tier_eligibility(factors) do
    if factors.has_meaningful_fix and
         factors.confidence_level >= 0.85 and
         factors.consistency_score >= 0.85 and
         factors.pass_to_fail_count <= 1 and
         factors.flaky_test_count <= 1 do
      {:eligible, :silver}
    else
      {:not_eligible, :silver}
    end
  end

  defp assess_bronze_tier_eligibility(factors) do
    if factors.has_meaningful_fix and
         factors.confidence_level >= 0.70 and
         factors.consistency_score >= 0.70 and
         factors.pass_to_fail_count <= 2 and
         factors.flaky_test_count <= 2 do
      {:eligible, :bronze}
    else
      {:not_eligible, :bronze}
    end
  end

  defp assess_unsuitability(factors) do
    unsuitable_conditions = [
      not factors.has_meaningful_fix,
      factors.confidence_level < 0.50,
      factors.consistency_score < 0.50,
      factors.flaky_test_count > 3,
      factors.pass_to_fail_count > 3
    ]

    if Enum.any?(unsuitable_conditions) do
      {:eligible, :unsuitable}
    else
      {:not_eligible, :unsuitable}
    end
  end

  defp determine_final_tier({:ok, {_factors, assessment_results}}) do
    # Select the highest quality tier for which the validation is eligible
    tier_priority = [:gold, :silver, :bronze, :unsuitable]

    final_tier =
      tier_priority
      |> Enum.find(fn tier ->
        Enum.any?(assessment_results, &match?({:eligible, ^tier}, &1))
      end)
      |> case do
        # Fallback
        nil -> :unsuitable
        tier -> tier
      end

    Logger.debug("Quality assessment complete: #{final_tier} tier")
    {:ok, final_tier}
  end

  defp determine_final_tier({:error, reason}) do
    {:error, reason}
  end
end
