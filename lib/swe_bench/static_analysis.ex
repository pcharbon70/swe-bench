defmodule SweBench.StaticAnalysis do
  @moduledoc """
  Main interface for static analysis.

  Coordinates Credo analysis, Dialyzer type checking, warning aggregation,
  and quality calculation for comprehensive static code analysis.
  """

  require Logger

  alias SweBench.StaticAnalysis.{
    CredoAnalyzer,
    DialyzerIntegration,
    QualityCalculator,
    WarningAggregator
  }

  @doc """
  Performs comprehensive static analysis on Elixir source code.
  """
  def analyze_code(source_code, opts \\ []) when is_binary(source_code) do
    Logger.info("Starting comprehensive static analysis")

    # Create temporary file for analysis since tools expect file paths
    temp_file_path = create_temp_file(source_code)

    try do
      with {:ok, credo_analysis} <- CredoAnalyzer.analyze_code_quality(temp_file_path, opts),
           {:ok, dialyzer_analysis} <-
             DialyzerIntegration.analyze_type_safety(temp_file_path, opts),
           {:ok, aggregated_warnings} <-
             WarningAggregator.aggregate_all_warnings(credo_analysis, dialyzer_analysis, opts),
           {:ok, quality_metrics} <-
             QualityCalculator.calculate_quality_metrics(
               temp_file_path,
               %{credo: credo_analysis, dialyzer: dialyzer_analysis},
               opts
             ) do
        complete_analysis = %{
          credo_analysis: credo_analysis,
          dialyzer_analysis: dialyzer_analysis,
          aggregated_warnings: aggregated_warnings,
          quality_metrics: quality_metrics,
          overall_score:
            calculate_overall_static_score(credo_analysis, dialyzer_analysis, quality_metrics),
          analyzed_at: DateTime.utc_now()
        }

        Logger.info("Static analysis complete")
        {:ok, complete_analysis}
      else
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(temp_file_path)
    end
  end

  @doc """
  Analyzes static code quality from a file path.
  """
  def analyze_file(file_path, opts \\ []) do
    Logger.info("Analyzing static quality in file: #{file_path}")

    with {:ok, credo_analysis} <- CredoAnalyzer.analyze_code_quality(file_path, opts),
         {:ok, dialyzer_analysis} <- DialyzerIntegration.analyze_type_safety(file_path, opts),
         {:ok, aggregated_warnings} <-
           WarningAggregator.aggregate_all_warnings(credo_analysis, dialyzer_analysis, opts),
         {:ok, quality_metrics} <-
           QualityCalculator.calculate_quality_metrics(
             file_path,
             %{credo: credo_analysis, dialyzer: dialyzer_analysis},
             opts
           ) do
      complete_analysis = %{
        credo_analysis: credo_analysis,
        dialyzer_analysis: dialyzer_analysis,
        aggregated_warnings: aggregated_warnings,
        quality_metrics: quality_metrics,
        overall_score:
          calculate_overall_static_score(credo_analysis, dialyzer_analysis, quality_metrics),
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Static analysis complete")
      {:ok, complete_analysis}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_temp_file(source_code) do
    temp_dir = System.tmp_dir!()
    temp_file = Path.join(temp_dir, "swe_bench_#{:rand.uniform(999_999)}.ex")
    File.write!(temp_file, source_code)
    temp_file
  end

  defp calculate_overall_static_score(credo_analysis, dialyzer_analysis, quality_metrics) do
    credo_score = get_score_from_analysis(credo_analysis, :quality_score, 0.0)
    dialyzer_score = get_score_from_analysis(dialyzer_analysis, :type_safety_score, 0.0)
    quality_score = get_score_from_analysis(quality_metrics, :overall_quality_score, 0.0)

    # Weight the scores: quality metrics most important, then credo, then dialyzer
    weighted_score = quality_score * 0.5 + credo_score * 0.3 + dialyzer_score * 0.2

    round(weighted_score * 100) / 100
  end

  defp get_score_from_analysis(analysis, key, default) do
    case analysis do
      %{^key => score} when is_number(score) -> score
      _ -> default
    end
  end
end
