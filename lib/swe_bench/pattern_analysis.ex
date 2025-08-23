defmodule SweBench.PatternAnalysis do
  @moduledoc """
  Main interface for pattern matching and function clause analysis.

  Coordinates AST parsing, exhaustiveness checking, clause ordering
  analysis, and quality scoring for comprehensive pattern evaluation.
  """

  require Logger

  alias SweBench.PatternAnalysis.{ASTParser, ExhaustivenessChecker, ClauseAnalyzer, QualityScorer}

  @doc """
  Performs comprehensive pattern analysis on Elixir source code.
  """
  def analyze_patterns(source_code) when is_binary(source_code) do
    Logger.info("Starting comprehensive pattern analysis")

    with {:ok, ast_analysis} <- ASTParser.parse_source(source_code),
         {:ok, function_analyses} <- analyze_all_functions(ast_analysis.functions),
         {:ok, coverage_matrix} <- build_coverage_matrix(ast_analysis.functions),
         {:ok, overall_metrics} <- calculate_overall_metrics(function_analyses) do
      complete_analysis = %{
        ast_analysis: ast_analysis,
        function_analyses: function_analyses,
        coverage_matrix: coverage_matrix,
        overall_metrics: overall_metrics,
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Pattern analysis complete: #{length(function_analyses)} functions analyzed")
      {:ok, complete_analysis}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes patterns from a file path.
  """
  def analyze_file(file_path) do
    Logger.info("Analyzing patterns in file: #{file_path}")

    case File.read(file_path) do
      {:ok, source_code} ->
        analyze_patterns(source_code)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Generates a comprehensive pattern analysis report.
  """
  def generate_analysis_report(analysis) do
    report = %{
      summary: %{
        total_functions: length(analysis.function_analyses),
        average_quality_score: calculate_average_quality_score(analysis.function_analyses),
        total_clauses: calculate_total_clauses(analysis.function_analyses),
        functions_with_issues: count_functions_with_issues(analysis.function_analyses)
      },
      detailed_findings: %{
        exhaustiveness_issues: extract_exhaustiveness_issues(analysis.function_analyses),
        ordering_issues: extract_ordering_issues(analysis.function_analyses),
        quality_concerns: extract_quality_concerns(analysis.function_analyses)
      },
      recommendations: generate_overall_recommendations(analysis.function_analyses),
      metrics: analysis.overall_metrics,
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  @doc """
  Validates pattern matching quality against thresholds.
  """
  def validate_pattern_quality(analysis, thresholds \\ default_thresholds()) do
    validation_results =
      Enum.map(analysis.function_analyses, fn function_analysis ->
        validate_single_function(function_analysis, thresholds)
      end)

    overall_validation = %{
      functions_validated: length(validation_results),
      functions_passed: Enum.count(validation_results, & &1.passed),
      functions_failed: Enum.count(validation_results, &(not &1.passed)),
      overall_pass_rate: calculate_pass_rate(validation_results),
      detailed_results: validation_results
    }

    {:ok, overall_validation}
  end

  # Private helper functions

  defp analyze_all_functions(functions) do
    function_analyses =
      Enum.map(functions, fn function ->
        {:ok, exhaustiveness} = ExhaustivenessChecker.analyze_function_exhaustiveness(function)
        {:ok, ordering} = ClauseAnalyzer.analyze_clause_ordering(function)
        {:ok, quality} = QualityScorer.calculate_quality_score(function)

        %{
          function: function,
          exhaustiveness: exhaustiveness,
          ordering: ordering,
          quality: quality
        }
      end)

    {:ok, function_analyses}
  end

  defp build_coverage_matrix(functions) do
    coverage_matrix = ASTParser.build_pattern_coverage_matrix(functions)
    {:ok, coverage_matrix}
  end

  defp calculate_overall_metrics(function_analyses) do
    quality_scores = Enum.map(function_analyses, & &1.quality.overall_score)
    exhaustiveness_scores = Enum.map(function_analyses, & &1.exhaustiveness.exhaustiveness_score)
    ordering_scores = Enum.map(function_analyses, & &1.ordering.ordering_score)

    metrics = %{
      average_quality_score: safe_average(quality_scores),
      average_exhaustiveness_score: safe_average(exhaustiveness_scores),
      average_ordering_score: safe_average(ordering_scores),
      total_functions_analyzed: length(function_analyses),
      high_quality_functions: count_high_quality_functions(function_analyses),
      quality_distribution: calculate_quality_distribution(quality_scores)
    }

    {:ok, metrics}
  end

  defp calculate_average_quality_score(function_analyses) do
    scores = Enum.map(function_analyses, & &1.quality.overall_score)
    safe_average(scores)
  end

  defp calculate_total_clauses(function_analyses) do
    Enum.sum(
      Enum.map(function_analyses, fn analysis ->
        analysis.exhaustiveness.total_clauses
      end)
    )
  end

  defp count_functions_with_issues(function_analyses) do
    Enum.count(function_analyses, fn analysis ->
      has_exhaustiveness_issues?(analysis.exhaustiveness) or
        has_ordering_issues?(analysis.ordering) or
        has_quality_issues?(analysis.quality)
    end)
  end

  defp extract_exhaustiveness_issues(function_analyses) do
    Enum.filter(function_analyses, fn analysis ->
      has_exhaustiveness_issues?(analysis.exhaustiveness)
    end)
    |> Enum.map(fn analysis ->
      %{
        function: analysis.function.name,
        score: analysis.exhaustiveness.exhaustiveness_score,
        missing_patterns: analysis.exhaustiveness.missing_patterns
      }
    end)
  end

  defp extract_ordering_issues(function_analyses) do
    Enum.filter(function_analyses, fn analysis ->
      has_ordering_issues?(analysis.ordering)
    end)
    |> Enum.map(fn analysis ->
      %{
        function: analysis.function.name,
        score: analysis.ordering.ordering_score,
        issues: analysis.ordering.ordering_issues
      }
    end)
  end

  defp extract_quality_concerns(function_analyses) do
    Enum.filter(function_analyses, fn analysis ->
      has_quality_issues?(analysis.quality)
    end)
    |> Enum.map(fn analysis ->
      %{
        function: analysis.function.name,
        overall_score: analysis.quality.overall_score,
        low_scores: identify_low_quality_areas(analysis.quality)
      }
    end)
  end

  defp generate_overall_recommendations(function_analyses) do
    recommendations = []

    # Global recommendations based on analysis
    low_quality_count = count_functions_with_issues(function_analyses)
    total_functions = length(function_analyses)

    recommendations =
      if low_quality_count > total_functions / 2 do
        ["Consider improving pattern matching across multiple functions" | recommendations]
      else
        recommendations
      end

    avg_score = calculate_average_quality_score(function_analyses)

    recommendations =
      if avg_score < 70 do
        [
          "Overall pattern matching quality could be improved (score: #{avg_score})"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Pattern matching quality appears good across analyzed functions"]
    else
      recommendations
    end
  end

  defp default_thresholds do
    %{
      minimum_quality_score: 60,
      minimum_exhaustiveness_score: 70,
      minimum_ordering_score: 80
    }
  end

  defp validate_single_function(function_analysis, thresholds) do
    quality_pass = function_analysis.quality.overall_score >= thresholds.minimum_quality_score

    exhaustiveness_pass =
      function_analysis.exhaustiveness.exhaustiveness_score >=
        thresholds.minimum_exhaustiveness_score

    ordering_pass = function_analysis.ordering.ordering_score >= thresholds.minimum_ordering_score

    %{
      function_name: function_analysis.function.name,
      passed: quality_pass and exhaustiveness_pass and ordering_pass,
      quality_pass: quality_pass,
      exhaustiveness_pass: exhaustiveness_pass,
      ordering_pass: ordering_pass,
      scores: %{
        quality: function_analysis.quality.overall_score,
        exhaustiveness: function_analysis.exhaustiveness.exhaustiveness_score,
        ordering: function_analysis.ordering.ordering_score
      }
    }
  end

  defp calculate_pass_rate(validation_results) do
    passed_count = Enum.count(validation_results, & &1.passed)
    total_count = length(validation_results)

    if total_count > 0, do: passed_count / total_count * 100, else: 0
  end

  defp safe_average([]), do: 0

  defp safe_average(values) do
    Enum.sum(values) / length(values)
  end

  defp count_high_quality_functions(function_analyses) do
    Enum.count(function_analyses, fn analysis ->
      analysis.quality.overall_score >= 80
    end)
  end

  defp calculate_quality_distribution(scores) do
    Enum.frequencies_by(scores, fn score ->
      cond do
        score >= 90 -> :excellent
        score >= 75 -> :good
        score >= 60 -> :fair
        score >= 40 -> :poor
        true -> :very_poor
      end
    end)
  end

  defp has_exhaustiveness_issues?(exhaustiveness) do
    exhaustiveness.exhaustiveness_score < 70 or
      map_size(exhaustiveness.missing_patterns) > 0
  end

  defp has_ordering_issues?(ordering) do
    ordering.ordering_score < 80 or
      length(ordering.ordering_issues) > 0
  end

  defp has_quality_issues?(quality) do
    quality.overall_score < 60
  end

  defp identify_low_quality_areas(quality) do
    areas = []

    areas = if quality.specificity_score < 50, do: [:specificity | areas], else: areas
    areas = if quality.destructuring_score < 50, do: [:destructuring | areas], else: areas
    areas = if quality.idiomaticity_score < 50, do: [:idiomaticity | areas], else: areas
    areas = if quality.clarity_score < 50, do: [:clarity | areas], else: areas

    areas
  end
end
