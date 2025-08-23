defmodule SweBench.PatternAnalysis.ClauseAnalyzer do
  @moduledoc """
  Function clause ordering analysis.

  Detects unreachable clauses, identifies overly general patterns,
  and suggests optimal clause ordering for pattern matching.
  """

  require Logger

  @doc """
  Analyzes clause ordering for a function.
  """
  def analyze_clause_ordering(function_analysis) do
    Logger.debug(
      "Analyzing clause ordering for #{function_analysis.name}/#{function_analysis.arity}"
    )

    ordering_analysis = %{
      function_name: function_analysis.name,
      function_arity: function_analysis.arity,
      clause_count: length(function_analysis.clauses),
      unreachable_clauses: find_unreachable_clauses(function_analysis.clauses),
      ordering_issues: identify_ordering_issues(function_analysis.clauses),
      suggested_ordering: suggest_optimal_ordering(function_analysis.clauses),
      guard_precedence: analyze_guard_precedence(function_analysis.clauses),
      redundant_patterns: detect_redundant_patterns(function_analysis.clauses),
      ordering_score: calculate_ordering_score(function_analysis.clauses)
    }

    {:ok, ordering_analysis}
  end

  @doc """
  Finds unreachable clauses due to ordering.
  """
  def find_unreachable_clauses(clauses) do
    {_reachable, unreachable} =
      Enum.reduce(clauses, {[], []}, fn clause, {reachable, unreachable} ->
        if clause_is_reachable?(clause, reachable) do
          {[clause | reachable], unreachable}
        else
          {reachable, [clause | unreachable]}
        end
      end)

    Enum.reverse(unreachable)
  end

  @doc """
  Identifies overly general patterns placed early.
  """
  def identify_overly_general_patterns(clauses) do
    Enum.with_index(clauses)
    |> Enum.filter(fn {clause, index} ->
      is_overly_general?(clause) and not is_last_clause?(index, clauses)
    end)
    |> Enum.map(fn {clause, index} -> {clause, index} end)
  end

  @doc """
  Suggests optimal clause ordering based on specificity.
  """
  def suggest_optimal_ordering(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.sort_by(
      fn {clause, _index} ->
        calculate_clause_specificity(clause)
      end,
      :desc
    )
    |> Enum.map(fn {clause, original_index} ->
      %{clause: clause, original_index: original_index}
    end)
  end

  @doc """
  Validates guard clause precedence rules.
  """
  def validate_guard_precedence(clauses) do
    precedence_issues = []

    # Check for guards that should come before non-guarded clauses
    precedence_issues = precedence_issues ++ check_guard_before_general(clauses)

    # Check for overly complex guards early in function
    precedence_issues = precedence_issues ++ check_complex_guards_early(clauses)

    %{
      issues: precedence_issues,
      valid_precedence: length(precedence_issues) == 0,
      suggestions: generate_precedence_suggestions(precedence_issues)
    }
  end

  @doc """
  Detects redundant patterns across clauses.
  """
  def detect_redundant_patterns(clauses) do
    pattern_signatures = Enum.map(clauses, &extract_pattern_signature/1)

    redundant_groups =
      pattern_signatures
      |> Enum.with_index()
      |> Enum.group_by(fn {signature, _index} -> signature end)
      |> Enum.filter(fn {_signature, occurrences} -> length(occurrences) > 1 end)
      |> Map.new(fn {signature, occurrences} ->
        indices = Enum.map(occurrences, fn {_sig, index} -> index end)
        {signature, indices}
      end)

    %{
      redundant_groups: redundant_groups,
      total_redundant: map_size(redundant_groups),
      affected_clauses: count_affected_clauses(redundant_groups)
    }
  end

  # Private helper functions

  defp clause_is_reachable?(clause, preceding_clauses) do
    # Check if any preceding clause would match all cases this clause handles
    not Enum.any?(preceding_clauses, fn preceding ->
      clause_subsumes?(preceding, clause)
    end)
  end

  defp clause_subsumes?(clause1, clause2) do
    # Simplified subsumption check
    # Would need more sophisticated analysis in production
    patterns1 = clause1.patterns
    patterns2 = clause2.patterns

    length(patterns1) == length(patterns2) &&
      Enum.zip(patterns1, patterns2)
      |> Enum.all?(fn {p1, p2} -> pattern_subsumes?(p1, p2) end)
  end

  defp pattern_subsumes?(pattern1, pattern2) do
    case {pattern1.type, pattern2.type} do
      {:wildcard, _} -> true
      {:variable, _} -> true
      {type, type} -> true
      _ -> false
    end
  end

  defp is_overly_general?(clause) do
    # Check if clause uses mostly wildcards or variables
    general_patterns =
      Enum.count(clause.patterns, fn pattern ->
        pattern.type in [:wildcard, :variable, :variable_with_context]
      end)

    total_patterns = length(clause.patterns)
    general_ratio = if total_patterns > 0, do: general_patterns / total_patterns, else: 0

    # More than 70% general patterns
    general_ratio > 0.7
  end

  defp is_last_clause?(index, clauses) do
    index == length(clauses) - 1
  end

  defp calculate_clause_specificity(clause) do
    # Calculate specificity score for ordering
    pattern_specificity = Enum.sum(Enum.map(clause.patterns, & &1.specificity))
    guard_bonus = if clause.guard, do: clause.guard_complexity * 2, else: 0

    pattern_specificity + guard_bonus
  end

  defp identify_ordering_issues(clauses) do
    issues = []

    # Check for unreachable clauses
    unreachable = find_unreachable_clauses(clauses)

    issues =
      if length(unreachable) > 0,
        do: [{:unreachable_clauses, length(unreachable)} | issues],
        else: issues

    # Check for overly general patterns early
    overly_general = identify_overly_general_patterns(clauses)

    issues =
      if length(overly_general) > 0,
        do: [{:overly_general_early, length(overly_general)} | issues],
        else: issues

    # Check for suboptimal ordering
    final_issues =
      if not optimally_ordered?(clauses) do
        [{:suboptimal_ordering, true} | issues]
      else
        issues
      end

    final_issues
  end

  defp optimally_ordered?(clauses) do
    specificities = Enum.map(clauses, &calculate_clause_specificity/1)

    # Check if clauses are in descending order of specificity
    specificities == Enum.sort(specificities, :desc)
  end

  defp analyze_guard_precedence(clauses) do
    precedence_validation = validate_guard_precedence(clauses)

    %{
      precedence_valid: precedence_validation.valid_precedence,
      issues_found: length(precedence_validation.issues),
      recommendations: precedence_validation.suggestions
    }
  end

  defp check_guard_before_general(clauses) do
    issues = []

    # Look for guarded clauses that come after general unguarded clauses
    Enum.with_index(clauses)
    |> Enum.reduce(issues, fn {clause, index}, acc ->
      if clause.guard do
        # Check if there are general patterns before this guarded clause
        preceding_general =
          clauses
          |> Enum.take(index)
          |> Enum.any?(&(not &1.guard and is_overly_general?(&1)))

        if preceding_general do
          [{:guarded_after_general, index} | acc]
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp check_complex_guards_early(clauses) do
    issues = []

    # Check for overly complex guards in early clauses
    Enum.with_index(clauses)
    |> Enum.reduce(issues, fn {clause, index}, acc ->
      if clause.guard and clause.guard_complexity > 3 and index < 2 do
        [{:complex_guard_early, index} | acc]
      else
        acc
      end
    end)
  end

  defp generate_precedence_suggestions(issues) do
    suggestions = []

    suggestions =
      if Enum.any?(issues, &match?({:guarded_after_general, _}, &1)) do
        ["Move guarded clauses before general unguarded clauses" | suggestions]
      else
        suggestions
      end

    suggestions =
      if Enum.any?(issues, &match?({:complex_guard_early, _}, &1)) do
        ["Consider simplifying complex guards in early clauses" | suggestions]
      else
        suggestions
      end

    suggestions
  end

  defp extract_pattern_signature(clause) do
    # Create a signature representing the pattern structure
    Enum.map(clause.patterns, fn pattern ->
      {pattern.type, pattern.specificity}
    end)
  end

  defp count_affected_clauses(redundant_groups) do
    redundant_groups
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp calculate_ordering_score(clauses) do
    issues = identify_ordering_issues(clauses)

    base_score = 100

    # Deduct points for issues
    score =
      Enum.reduce(issues, base_score, fn issue, acc ->
        case issue do
          {:unreachable_clauses, count} -> acc - count * 15
          {:overly_general_early, count} -> acc - count * 10
          {:suboptimal_ordering, true} -> acc - 20
          _ -> acc
        end
      end)

    max(0, score)
  end
end
