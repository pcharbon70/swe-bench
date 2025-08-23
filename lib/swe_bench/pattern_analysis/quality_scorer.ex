defmodule SweBench.PatternAnalysis.QualityScorer do
  @moduledoc """
  Pattern matching quality scoring system.

  Scores pattern specificity, destructuring effectiveness, and
  idiomatic pattern usage for comprehensive quality assessment.
  """

  require Logger

  @doc """
  Calculates overall pattern matching quality score for a function.
  """
  def calculate_quality_score(function_analysis) do
    Logger.debug(
      "Calculating quality score for #{function_analysis.name}/#{function_analysis.arity}"
    )

    quality_metrics = %{
      specificity_score: score_pattern_specificity(function_analysis.clauses),
      destructuring_score: score_destructuring_effectiveness(function_analysis.clauses),
      idiomaticity_score: score_idiomatic_usage(function_analysis.clauses),
      clarity_score: score_pattern_clarity(function_analysis.clauses),
      # Will be calculated
      overall_score: 0
    }

    # Calculate weighted overall score
    overall_score = calculate_weighted_score(quality_metrics)
    final_metrics = Map.put(quality_metrics, :overall_score, overall_score)

    {:ok, final_metrics}
  end

  @doc """
  Scores pattern specificity and clarity.
  """
  def score_pattern_specificity(clauses) do
    specificities =
      Enum.flat_map(clauses, fn clause ->
        Enum.map(clause.patterns, & &1.specificity)
      end)

    if length(specificities) > 0 do
      average_specificity = Enum.sum(specificities) / length(specificities)
      # Scale to 0-100
      round(average_specificity * 20)
    else
      0
    end
  end

  @doc """
  Evaluates destructuring effectiveness.
  """
  def score_destructuring_effectiveness(clauses) do
    destructuring_scores =
      Enum.flat_map(clauses, fn clause ->
        Enum.map(clause.patterns, &calculate_destructuring_score/1)
      end)

    if length(destructuring_scores) > 0 do
      average_score = Enum.sum(destructuring_scores) / length(destructuring_scores)
      round(average_score)
    else
      0
    end
  end

  @doc """
  Assesses pattern matching vs conditional logic usage.
  """
  def assess_pattern_vs_conditional(function_analysis) do
    total_clauses = length(function_analysis.clauses)

    assessment = %{
      total_clauses: total_clauses,
      uses_pattern_matching: total_clauses > 1,
      pattern_matching_score: calculate_pattern_matching_score(total_clauses),
      recommendation: generate_pattern_vs_conditional_recommendation(total_clauses)
    }

    {:ok, assessment}
  end

  @doc """
  Rates idiomatic pattern usage following Elixir conventions.
  """
  def score_idiomatic_usage(clauses) do
    idiom_scores = Enum.map(clauses, &score_clause_idiomaticity/1)

    if length(idiom_scores) > 0 do
      average_idiom_score = Enum.sum(idiom_scores) / length(idiom_scores)
      round(average_idiom_score)
    else
      # Neutral score if no patterns
      50
    end
  end

  @doc """
  Scores pattern clarity and readability.
  """
  def score_pattern_clarity(clauses) do
    clarity_scores = Enum.map(clauses, &calculate_clause_clarity/1)

    if length(clarity_scores) > 0 do
      average_clarity = Enum.sum(clarity_scores) / length(clarity_scores)
      round(average_clarity)
    else
      0
    end
  end

  # Private helper functions

  defp calculate_destructuring_score(pattern) do
    base_score = get_base_destructuring_score(pattern.type)

    # Bonus for deep destructuring
    depth_bonus = min(20, pattern.destructuring_depth * 5)

    min(100, base_score + depth_bonus)
  end

  defp get_base_destructuring_score(pattern_type) do
    cond do
      high_destructuring_pattern?(pattern_type) -> get_high_score(pattern_type)
      medium_destructuring_pattern?(pattern_type) -> get_medium_score(pattern_type)
      low_destructuring_pattern?(pattern_type) -> get_low_score(pattern_type)
      true -> 40
    end
  end

  defp high_destructuring_pattern?(type), do: type in [:map, :tuple, :two_tuple]

  defp medium_destructuring_pattern?(type),
    do: type in [:list, :literal_atom, :literal_number, :literal_string]

  defp low_destructuring_pattern?(type), do: type in [:variable, :wildcard]

  defp get_high_score(:map), do: 80
  defp get_high_score(:tuple), do: 70
  defp get_high_score(:two_tuple), do: 65

  defp get_medium_score(:list), do: 60
  defp get_medium_score(_), do: 50

  defp get_low_score(:variable), do: 30
  defp get_low_score(:wildcard), do: 20

  defp calculate_pattern_matching_score(clause_count) do
    case clause_count do
      # Single clause - limited pattern matching
      1 -> 30
      # Two clauses - basic pattern matching
      2 -> 60
      # Three clauses - good pattern matching
      3 -> 80
      # Bonus for more clauses
      count when count > 3 -> min(100, 80 + (count - 3) * 5)
      _ -> 0
    end
  end

  defp generate_pattern_vs_conditional_recommendation(clause_count) do
    cond do
      clause_count == 1 -> "Consider if pattern matching could be used instead of conditionals"
      clause_count >= 2 -> "Good use of pattern matching in function heads"
      true -> "No pattern matching detected"
    end
  end

  defp score_clause_idiomaticity(clause) do
    base_score = 50

    # Bonus for using specific patterns over general ones
    specificity_bonus = calculate_specificity_bonus(clause.patterns)

    # Bonus for appropriate guard usage
    guard_bonus = calculate_guard_bonus(clause)

    # Penalty for overly complex patterns
    complexity_penalty = calculate_complexity_penalty(clause.patterns)

    final_score = base_score + specificity_bonus + guard_bonus - complexity_penalty
    max(0, min(100, final_score))
  end

  defp calculate_specificity_bonus(patterns) do
    specific_patterns =
      Enum.count(patterns, fn pattern ->
        pattern.type in [:literal_atom, :literal_number, :literal_string, :tuple, :map]
      end)

    min(30, specific_patterns * 10)
  end

  defp calculate_guard_bonus(clause) do
    cond do
      clause.guard == nil -> 0
      clause.guard_complexity >= 1 and clause.guard_complexity <= 3 -> 15
      # Complex guards get less bonus
      clause.guard_complexity > 3 -> 5
      true -> 0
    end
  end

  defp calculate_complexity_penalty(patterns) do
    overly_complex =
      Enum.count(patterns, fn pattern ->
        pattern.complexity > 5
      end)

    overly_complex * 5
  end

  defp calculate_clause_clarity(clause) do
    base_clarity = 50

    # Clear patterns are specific and not overly complex
    pattern_clarity =
      Enum.map(clause.patterns, fn pattern ->
        specificity_factor = min(20, pattern.specificity * 4)
        complexity_factor = max(-15, -(pattern.complexity - 3) * 3)

        max(0, 50 + specificity_factor + complexity_factor)
      end)

    if length(pattern_clarity) > 0 do
      Enum.sum(pattern_clarity) / length(pattern_clarity)
    else
      base_clarity
    end
  end

  defp calculate_weighted_score(metrics) do
    # Weighted average of all quality metrics
    weights = %{
      specificity_score: 0.3,
      destructuring_score: 0.25,
      idiomaticity_score: 0.25,
      clarity_score: 0.2
    }

    weighted_sum =
      weights.specificity_score * metrics.specificity_score +
        weights.destructuring_score * metrics.destructuring_score +
        weights.idiomaticity_score * metrics.idiomaticity_score +
        weights.clarity_score * metrics.clarity_score

    round(weighted_sum)
  end
end
