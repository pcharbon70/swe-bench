defmodule SweBench.PatternAnalysis.ExhaustivenessChecker do
  @moduledoc """
  Pattern matching exhaustiveness analysis.

  Analyzes pattern completeness for functions, identifies missing
  pattern cases, and validates guard expression coverage.
  """

  require Logger

  # alias SweBench.PatternAnalysis.ASTParser - for future integration

  @doc """
  Analyzes pattern exhaustiveness for a function.
  """
  def analyze_function_exhaustiveness(function_analysis) do
    Logger.debug(
      "Analyzing exhaustiveness for function #{function_analysis.name}/#{function_analysis.arity}"
    )

    exhaustiveness = %{
      function_name: function_analysis.name,
      function_arity: function_analysis.arity,
      total_clauses: length(function_analysis.clauses),
      pattern_coverage: calculate_pattern_coverage(function_analysis.clauses),
      missing_patterns: identify_missing_patterns(function_analysis.clauses),
      catch_all_analysis: analyze_catch_all_clauses(function_analysis.clauses),
      guard_coverage: calculate_guard_coverage(function_analysis.clauses),
      exhaustiveness_score: calculate_exhaustiveness_score(function_analysis.clauses)
    }

    {:ok, exhaustiveness}
  end

  @doc """
  Identifies missing pattern cases for common Elixir types.
  """
  def identify_missing_patterns(clauses) do
    covered_patterns = extract_covered_patterns(clauses)

    missing = %{
      boolean_patterns: missing_boolean_patterns(covered_patterns),
      atom_patterns: missing_common_atom_patterns(covered_patterns),
      tuple_patterns: missing_tuple_arity_patterns(covered_patterns),
      list_patterns: missing_list_patterns(covered_patterns),
      result_tuple_patterns: missing_result_tuple_patterns(covered_patterns)
    }

    # Filter out empty missing pattern sets
    missing
    |> Enum.filter(fn {_type, patterns} -> length(patterns) > 0 end)
    |> Map.new()
  end

  @doc """
  Analyzes catch-all clauses and their necessity.
  """
  def analyze_catch_all_clauses(clauses) do
    catch_all_clauses = find_catch_all_clauses(clauses)

    %{
      has_catch_all: length(catch_all_clauses) > 0,
      catch_all_count: length(catch_all_clauses),
      catch_all_positions: Enum.map(catch_all_clauses, & &1.index),
      catch_all_necessity: evaluate_catch_all_necessity(clauses, catch_all_clauses),
      recommendations: generate_catch_all_recommendations(clauses, catch_all_clauses)
    }
  end

  @doc """
  Validates guard expression coverage across function clauses.
  """
  def validate_guard_coverage(clauses) do
    guarded_clauses = Enum.filter(clauses, & &1.guard)
    unguarded_clauses = Enum.filter(clauses, &(not &1.guard))

    coverage_analysis = %{
      total_clauses: length(clauses),
      guarded_clauses: length(guarded_clauses),
      unguarded_clauses: length(unguarded_clauses),
      guard_coverage_ratio: length(guarded_clauses) / max(1, length(clauses)),
      guard_complexity_distribution: analyze_guard_complexity_distribution(guarded_clauses),
      guard_effectiveness: evaluate_guard_effectiveness(guarded_clauses)
    }

    {:ok, coverage_analysis}
  end

  @doc """
  Generates exhaustiveness report for a function.
  """
  def generate_exhaustiveness_report(function_analysis) do
    {:ok, exhaustiveness} = analyze_function_exhaustiveness(function_analysis)

    report = %{
      summary: %{
        function: "#{exhaustiveness.function_name}/#{exhaustiveness.function_arity}",
        exhaustiveness_score: exhaustiveness.exhaustiveness_score,
        pattern_coverage_score: exhaustiveness.pattern_coverage.coverage_score,
        total_clauses: exhaustiveness.total_clauses
      },
      findings: %{
        missing_patterns: exhaustiveness.missing_patterns,
        catch_all_analysis: exhaustiveness.catch_all_analysis,
        guard_coverage: exhaustiveness.guard_coverage
      },
      recommendations: generate_exhaustiveness_recommendations(exhaustiveness),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  # Private helper functions

  defp calculate_guard_coverage(clauses) do
    guarded_clauses = Enum.filter(clauses, & &1.guard)

    %{
      total_clauses: length(clauses),
      guarded_clauses: length(guarded_clauses),
      coverage_ratio:
        if(length(clauses) > 0, do: length(guarded_clauses) / length(clauses), else: 0)
    }
  end

  defp calculate_pattern_coverage(clauses) do
    all_patterns = Enum.flat_map(clauses, & &1.patterns)
    pattern_types = Enum.map(all_patterns, & &1.type)

    type_coverage = Enum.frequencies(pattern_types)

    %{
      total_patterns: length(all_patterns),
      unique_pattern_types: length(Map.keys(type_coverage)),
      type_distribution: type_coverage,
      coverage_score: calculate_coverage_score(type_coverage)
    }
  end

  defp calculate_coverage_score(type_coverage) do
    # Score based on pattern diversity and specificity
    base_score = min(50, map_size(type_coverage) * 10)

    specificity_bonus =
      if Map.has_key?(type_coverage, :literal_atom) or
           Map.has_key?(type_coverage, :literal_number) or
           Map.has_key?(type_coverage, :literal_string),
         do: 20,
         else: 0

    structural_bonus =
      if Map.has_key?(type_coverage, :tuple) or
           Map.has_key?(type_coverage, :map) or
           Map.has_key?(type_coverage, :list),
         do: 15,
         else: 0

    wildcard_penalty = if Map.has_key?(type_coverage, :wildcard), do: -10, else: 0

    min(100, base_score + specificity_bonus + structural_bonus + wildcard_penalty)
  end

  defp extract_covered_patterns(clauses) do
    clauses
    |> Enum.flat_map(& &1.patterns)
    |> Enum.map(& &1.type)
    |> MapSet.new()
  end

  defp missing_boolean_patterns(covered) do
    # true, false are atoms in Elixir
    _boolean_patterns = [:literal_atom]
    required = MapSet.new([true, false])

    if :literal_atom in covered do
      # Assume boolean coverage if atoms are used
      []
    else
      MapSet.to_list(required)
    end
  end

  defp missing_common_atom_patterns(covered) do
    if :literal_atom in covered do
      []
    else
      [:ok, :error, nil]
    end
  end

  defp missing_tuple_arity_patterns(covered) do
    if :tuple in covered or :two_tuple in covered do
      []
    else
      # Common tuple arities
      [{2}, {3}, {4}]
    end
  end

  defp missing_list_patterns(covered) do
    if :list in covered do
      []
    else
      [:empty_list, :non_empty_list]
    end
  end

  defp missing_result_tuple_patterns(covered) do
    if :tuple in covered or :two_tuple in covered do
      []
    else
      [:ok_tuple, :error_tuple]
    end
  end

  defp find_catch_all_clauses(clauses) do
    Enum.filter(clauses, fn clause ->
      catch_all_clause?(clause)
    end)
  end

  defp catch_all_clause?(clause) do
    # Check if clause uses only wildcards or variables
    Enum.all?(clause.patterns, fn pattern ->
      pattern.type in [:wildcard, :variable, :variable_with_context]
    end)
  end

  defp evaluate_catch_all_necessity(clauses, catch_all_clauses) do
    if Enum.empty?(catch_all_clauses) do
      :may_need_catch_all
    else
      # Check if catch-all is in the right position (usually last)
      last_clause = List.last(clauses)

      if last_clause in catch_all_clauses do
        :appropriately_placed
      else
        :poorly_positioned
      end
    end
  end

  defp generate_catch_all_recommendations(clauses, catch_all_clauses) do
    recommendations = []

    recommendations =
      if Enum.empty?(catch_all_clauses) and length(clauses) > 2 do
        ["Consider adding a catch-all clause for unhandled cases" | recommendations]
      else
        recommendations
      end

    recommendations =
      if length(catch_all_clauses) > 1 do
        ["Multiple catch-all clauses detected - consider consolidating" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_guard_complexity_distribution(guarded_clauses) do
    complexities = Enum.map(guarded_clauses, & &1.guard_complexity)

    %{
      min_complexity: Enum.min(complexities, fn -> 0 end),
      max_complexity: Enum.max(complexities, fn -> 0 end),
      average_complexity:
        if(length(complexities) > 0, do: Enum.sum(complexities) / length(complexities), else: 0),
      complexity_distribution: Enum.frequencies(complexities)
    }
  end

  defp evaluate_guard_effectiveness(guarded_clauses) do
    if Enum.empty?(guarded_clauses) do
      %{effectiveness: :no_guards, score: 0}
    else
      avg_complexity =
        Enum.sum(Enum.map(guarded_clauses, & &1.guard_complexity)) / length(guarded_clauses)

      effectiveness =
        cond do
          avg_complexity > 3 -> :high_complexity
          avg_complexity > 1 -> :moderate_complexity
          true -> :simple_guards
        end

      score = round(min(100, avg_complexity * 25))

      %{effectiveness: effectiveness, score: score, average_complexity: avg_complexity}
    end
  end

  defp generate_exhaustiveness_recommendations(exhaustiveness) do
    recommendations = []

    recommendations =
      if exhaustiveness.exhaustiveness_score < 70 do
        [
          "Improve pattern coverage - current score: #{exhaustiveness.exhaustiveness_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if length(Map.keys(exhaustiveness.missing_patterns)) > 0 do
        [
          "Consider adding patterns for: #{inspect(Map.keys(exhaustiveness.missing_patterns))}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if exhaustiveness.catch_all_analysis.catch_all_necessity == :may_need_catch_all do
        ["Consider adding a catch-all clause for error handling" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["Pattern matching appears comprehensive"]
    else
      recommendations
    end
  end

  defp calculate_exhaustiveness_score(clauses) do
    pattern_score = calculate_pattern_diversity_score(clauses)
    guard_score = calculate_guard_utilization_score(clauses)
    catch_all_score = calculate_catch_all_appropriateness_score(clauses)

    # Weighted average
    total_score = pattern_score * 0.5 + guard_score * 0.3 + catch_all_score * 0.2
    round(total_score)
  end

  defp calculate_pattern_diversity_score(clauses) do
    pattern_types = Enum.flat_map(clauses, & &1.patterns) |> Enum.map(& &1.type) |> Enum.uniq()
    diversity_score = min(100, length(pattern_types) * 15)
    diversity_score
  end

  defp calculate_guard_utilization_score(clauses) do
    guarded_ratio = Enum.count(clauses, & &1.guard) / max(1, length(clauses))
    round(guarded_ratio * 100)
  end

  defp calculate_catch_all_appropriateness_score(clauses) do
    catch_all_clauses = find_catch_all_clauses(clauses)

    cond do
      # May need catch-all
      Enum.empty?(catch_all_clauses) and length(clauses) > 3 -> 60
      # Good
      length(catch_all_clauses) == 1 -> 100
      # Too many catch-alls
      length(catch_all_clauses) > 1 -> 40
      # Default case
      true -> 80
    end
  end
end
