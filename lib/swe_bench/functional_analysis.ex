defmodule SweBench.FunctionalAnalysis do
  @moduledoc """
  Main interface for functional programming analysis.

  Coordinates function purity checking, immutability analysis, pipeline detection,
  and recursion analysis for comprehensive functional programming evaluation.
  """

  require Logger

  alias SweBench.FunctionalAnalysis.{
    FunctionPurityChecker,
    ImmutabilityAnalyzer,
    PipelineDetector,
    RecursionAnalyzer
  }

  @doc """
  Performs comprehensive functional programming analysis on Elixir source code.
  """
  def analyze_code(source_code, opts \\ []) when is_binary(source_code) do
    Logger.info("Starting comprehensive functional analysis")

    with {:ok, purity_analysis} <-
           FunctionPurityChecker.analyze_function_purity(source_code, opts),
         {:ok, immutability_analysis} <-
           ImmutabilityAnalyzer.analyze_immutability(source_code, opts),
         {:ok, pipeline_analysis} <- PipelineDetector.analyze_pipeline_usage(source_code, opts),
         {:ok, recursion_analysis} <-
           RecursionAnalyzer.analyze_recursion_patterns(source_code, opts) do
      complete_analysis = %{
        purity_analysis: purity_analysis,
        immutability_analysis: immutability_analysis,
        pipeline_analysis: pipeline_analysis,
        recursion_analysis: recursion_analysis,
        overall_score:
          calculate_overall_functional_score(
            purity_analysis,
            immutability_analysis,
            pipeline_analysis,
            recursion_analysis
          ),
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Functional analysis complete")
      {:ok, complete_analysis}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes functional programming patterns from a file path.
  """
  def analyze_file(file_path, opts \\ []) do
    Logger.info("Analyzing functional patterns in file: #{file_path}")

    case File.read(file_path) do
      {:ok, source_code} ->
        analyze_code(source_code, opts)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp calculate_overall_functional_score(
         purity_analysis,
         immutability_analysis,
         pipeline_analysis,
         recursion_analysis
       ) do
    purity_score = get_score_from_analysis(purity_analysis, :purity_percentage, 0.0)

    immutability_score =
      get_score_from_analysis(immutability_analysis, :immutability_percentage, 0.0)

    pipeline_score = get_score_from_analysis(pipeline_analysis, :pipeline_usage_score, 0.0)
    recursion_score = get_score_from_analysis(recursion_analysis, :recursion_quality_score, 0.0)

    # Weight the scores: purity and immutability are most important
    weighted_score =
      purity_score * 0.4 + immutability_score * 0.3 + pipeline_score * 0.2 + recursion_score * 0.1

    round(weighted_score * 100) / 100
  end

  defp get_score_from_analysis(analysis, key, default) do
    case analysis do
      %{^key => score} when is_number(score) -> score
      _ -> default
    end
  end
end
