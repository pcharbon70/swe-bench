defmodule SweBench.StaticAnalysis.CredoAnalyzer do
  @moduledoc """
  Integrates Credo for comprehensive code quality analysis.

  Configures Credo with strict settings, executes analysis on generated code,
  categorizes issues by severity, extracts readability and complexity metrics,
  and generates quality scores for evaluation.
  """

  require Logger

  # 2 minutes for Credo analysis
  @credo_timeout 120_000
  @default_config_path ".credo.exs"

  @severity_weights %{
    "design" => 1.0,
    "readability" => 0.8,
    "refactor" => 0.6,
    "warning" => 0.4,
    "consistency" => 0.3
  }

  @doc """
  Performs comprehensive Credo analysis on source code.

  ## Parameters
    - source_path: Path to the source code directory to analyze
    - opts: Analysis options including configuration and output format

  ## Returns
    - {:ok, analysis_result} - Successful analysis with categorized findings
    - {:error, reason} - Analysis error
  """
  def analyze_code_quality(source_path, opts \\ []) do
    Logger.info("Starting Credo analysis for #{source_path}")

    with {:ok, config} <- prepare_credo_configuration(source_path, opts),
         {:ok, credo_output} <- execute_credo_analysis(source_path, config, opts),
         {:ok, parsed_results} <- parse_credo_output(credo_output),
         {:ok, categorized_issues} <- categorize_issues_by_severity(parsed_results),
         {:ok, quality_metrics} <- extract_quality_metrics(parsed_results, categorized_issues),
         {:ok, credo_score} <- calculate_credo_score(categorized_issues, quality_metrics) do
      analysis_result = %{
        source_path: source_path,
        configuration: config,
        raw_output: credo_output,
        parsed_results: parsed_results,
        categorized_issues: categorized_issues,
        quality_metrics: quality_metrics,
        credo_score: credo_score,
        analyzed_at: DateTime.utc_now(),
        analysis_duration_ms: quality_metrics.execution_time_ms
      }

      Logger.info(
        "Credo analysis complete: score #{credo_score}, #{length(parsed_results.issues)} issues found"
      )

      {:ok, analysis_result}
    else
      {:error, reason} ->
        Logger.warning("Credo analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.4.1.1: Configure Credo with strict settings
  defp prepare_credo_configuration(source_path, opts) do
    config_path = Keyword.get(opts, :config_path, @default_config_path)
    full_config_path = Path.join(source_path, config_path)

    config = %{
      config_path: full_config_path,
      strict_mode: Keyword.get(opts, :strict, true),
      checks_enabled: get_enabled_checks(opts),
      output_format: Keyword.get(opts, :format, "json"),
      all_priorities: Keyword.get(opts, :all_priorities, true)
    }

    case ensure_credo_config_exists(full_config_path, config) do
      :ok -> {:ok, config}
      {:error, reason} -> {:error, {:config_preparation_failed, reason}}
    end
  end

  defp get_enabled_checks(opts) do
    Keyword.get(opts, :checks, [
      "design",
      "readability",
      "refactor",
      "warning",
      "consistency"
    ])
  end

  defp ensure_credo_config_exists(config_path, config) do
    if File.exists?(config_path) do
      :ok
    else
      case create_default_credo_config(config_path, config) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp create_default_credo_config(config_path, config) do
    default_config = generate_strict_credo_config(config)

    case File.write(config_path, default_config) do
      :ok ->
        Logger.debug("Created default Credo configuration at #{config_path}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_strict_credo_config(config) do
    """
    %{
      configs: [
        %{
          name: "default",
          files: %{
            included: ["lib/", "src/", "test/", "web/", "apps/"],
            excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
          },
          plugins: [],
          requires: [],
          strict: #{config.strict_mode},
          parse_timeout: 5000,
          color: true,
          checks: %{
            enabled: [
              # Design Checks
              {Credo.Check.Design.AliasUsage, []},
              {Credo.Check.Design.DuplicatedCode, []},
              {Credo.Check.Design.TagTODO, []},
              {Credo.Check.Design.TagFIXME, []},

              # Readability Checks
              {Credo.Check.Readability.AliasOrder, []},
              {Credo.Check.Readability.FunctionNames, []},
              {Credo.Check.Readability.LargeNumbers, []},
              {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
              {Credo.Check.Readability.ModuleAttributeNames, []},
              {Credo.Check.Readability.ModuleDoc, []},
              {Credo.Check.Readability.ModuleNames, []},
              {Credo.Check.Readability.ParenthesesInCondition, []},
              {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
              {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
              {Credo.Check.Readability.PredicateNames, []},
              {Credo.Check.Readability.PreferImplicitTry, []},
              {Credo.Check.Readability.RedundantBlankLines, []},
              {Credo.Check.Readability.Semicolons, []},
              {Credo.Check.Readability.SpaceAfterCommas, []},
              {Credo.Check.Readability.StringSigils, []},
              {Credo.Check.Readability.TrailingBlankLine, []},
              {Credo.Check.Readability.TrailingWhiteSpace, []},
              {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
              {Credo.Check.Readability.VariableNames, []},

              # Refactoring Checks
              {Credo.Check.Refactor.ABCSize, []},
              {Credo.Check.Refactor.AppendSingleItem, []},
              {Credo.Check.Refactor.DoubleBooleanNegation, []},
              {Credo.Check.Refactor.FilterCount, []},
              {Credo.Check.Refactor.FilterFilter, []},
              {Credo.Check.Refactor.IoPuts, []},
              {Credo.Check.Refactor.MapInto, []},
              {Credo.Check.Refactor.MapJoin, []},
              {Credo.Check.Refactor.MatchInCondition, []},
              {Credo.Check.Refactor.NegatedConditionsInUnless, []},
              {Credo.Check.Refactor.NegatedConditionsWithElse, []},
              {Credo.Check.Refactor.Nesting, [max_nesting: 2]},
              {Credo.Check.Refactor.UnlessWithElse, []},
              {Credo.Check.Refactor.WithClauses, []},

              # Warning Checks
              {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
              {Credo.Check.Warning.BoolOperationOnSameValues, []},
              {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
              {Credo.Check.Warning.IExPry, []},
              {Credo.Check.Warning.IoInspect, []},
              {Credo.Check.Warning.LazyLogging, []},
              {Credo.Check.Warning.MapGetUnsafePass, []},
              {Credo.Check.Warning.OperationOnSameValues, []},
              {Credo.Check.Warning.OperationWithConstantResult, []},
              {Credo.Check.Warning.RaiseInsideRescue, []},
              {Credo.Check.Warning.SpecWithStruct, []},
              {Credo.Check.Warning.UnsafeExec, []},
              {Credo.Check.Warning.UnsafeToAtom, []},
              {Credo.Check.Warning.UnusedEnumOperation, []},
              {Credo.Check.Warning.UnusedFileOperation, []},
              {Credo.Check.Warning.UnusedKeywordOperation, []},
              {Credo.Check.Warning.UnusedListOperation, []},
              {Credo.Check.Warning.UnusedPathOperation, []},
              {Credo.Check.Warning.UnusedRegexOperation, []},
              {Credo.Check.Warning.UnusedStringOperation, []},

              # Consistency Checks
              {Credo.Check.Consistency.ExceptionNames, []},
              {Credo.Check.Consistency.LineEndings, []},
              {Credo.Check.Consistency.ParameterPatternMatching, []},
              {Credo.Check.Consistency.SpaceAroundOperators, []},
              {Credo.Check.Consistency.SpaceInParentheses, []},
              {Credo.Check.Consistency.TabsOrSpaces, []}
            ]
          }
        }
      ]
    }
    """
  end

  # Task 2.4.1.2: Run analysis on generated code
  defp execute_credo_analysis(source_path, config, opts) do
    timeout = Keyword.get(opts, :timeout, @credo_timeout)

    credo_args = build_credo_arguments(source_path, config)

    Logger.debug("Executing Credo with args: #{inspect(credo_args)}")

    case System.cmd("mix", credo_args,
           cd: source_path,
           stderr_to_stdout: true,
           timeout: timeout
         ) do
      {output, 0} ->
        {:ok, %{output: output, exit_code: 0, execution_time_ms: timeout}}

      {output, exit_code} ->
        # Credo may exit with non-zero code if issues are found, which is expected
        Logger.debug("Credo completed with exit code #{exit_code}")
        {:ok, %{output: output, exit_code: exit_code, execution_time_ms: timeout}}
    end
  rescue
    error ->
      {:error, {:credo_execution_failed, error}}
  end

  defp build_credo_arguments(source_path, config) do
    args = ["credo"]

    args =
      if config.config_path != @default_config_path and File.exists?(config.config_path) do
        args ++ ["--config-file", config.config_path]
      else
        args
      end

    args =
      if config.strict_mode do
        args ++ ["--strict"]
      else
        args
      end

    args =
      if config.all_priorities do
        args ++ ["--all"]
      else
        args
      end

    args ++ ["--format", config.output_format, source_path]
  end

  defp parse_credo_output(credo_output) do
    case Jason.decode(credo_output.output) do
      {:ok, json_data} ->
        parsed_result = %{
          issues: extract_issues_from_json(json_data),
          summary: extract_summary_from_json(json_data),
          config_info: extract_config_info_from_json(json_data),
          execution_time_ms: credo_output.execution_time_ms
        }

        {:ok, parsed_result}

      {:error, _reason} ->
        # If JSON parsing fails, try to extract basic info from text output
        parse_credo_text_output(credo_output.output)
    end
  end

  defp extract_issues_from_json(json_data) do
    issues = Map.get(json_data, "issues", [])

    Enum.map(issues, fn issue ->
      %{
        category: Map.get(issue, "category"),
        check: Map.get(issue, "check"),
        column: Map.get(issue, "column"),
        column_end: Map.get(issue, "column_end"),
        filename: Map.get(issue, "filename"),
        line_no: Map.get(issue, "line_no"),
        message: Map.get(issue, "message"),
        priority: Map.get(issue, "priority"),
        scope: Map.get(issue, "scope"),
        severity: Map.get(issue, "severity"),
        trigger: Map.get(issue, "trigger")
      }
    end)
  end

  defp extract_summary_from_json(json_data) do
    summary = Map.get(json_data, "summary", %{})

    %{
      total: Map.get(summary, "total", 0),
      issues_count: Map.get(summary, "issues_count", 0),
      duplicated_lines: Map.get(summary, "duplicated_lines", 0),
      files_analyzed: Map.get(summary, "files_analyzed", 0)
    }
  end

  defp extract_config_info_from_json(json_data) do
    config_info = Map.get(json_data, "config", %{})

    %{
      checks_enabled: Map.get(config_info, "checks_enabled", []),
      strict_mode: Map.get(config_info, "strict", false),
      files_included: Map.get(config_info, "files_included", []),
      files_excluded: Map.get(config_info, "files_excluded", [])
    }
  end

  defp parse_credo_text_output(text_output) do
    # Fallback text parsing when JSON format fails
    issue_count = count_text_issues(text_output)

    parsed_result = %{
      # Cannot extract detailed issues from text
      issues: [],
      summary: %{
        total: issue_count,
        issues_count: issue_count,
        duplicated_lines: 0,
        files_analyzed: count_analyzed_files(text_output)
      },
      config_info: %{},
      execution_time_ms: 0,
      parse_method: :text_fallback
    }

    {:ok, parsed_result}
  end

  defp count_text_issues(text_output) do
    # Count lines that look like Credo issues
    text_output
    |> String.split("\n")
    |> Enum.count(fn line ->
      String.contains?(line, "[") and
        (String.contains?(line, "R]") or
           String.contains?(line, "F]") or
           String.contains?(line, "W]") or
           String.contains?(line, "D]") or
           String.contains?(line, "C]"))
    end)
  end

  defp count_analyzed_files(text_output) do
    # Estimate files analyzed from output
    case Regex.run(~r/(\d+) source files/, text_output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end

  # Task 2.4.1.3: Categorize issues by severity
  defp categorize_issues_by_severity(parsed_results) do
    issues_by_category =
      parsed_results.issues
      |> Enum.group_by(& &1.category)

    categorized = %{
      design: Map.get(issues_by_category, "design", []),
      readability: Map.get(issues_by_category, "readability", []),
      refactor: Map.get(issues_by_category, "refactor", []),
      warning: Map.get(issues_by_category, "warning", []),
      consistency: Map.get(issues_by_category, "consistency", []),
      total_issues: length(parsed_results.issues)
    }

    # Add severity statistics
    severity_stats = calculate_severity_statistics(categorized)
    final_categorization = Map.merge(categorized, severity_stats)

    {:ok, final_categorization}
  end

  defp calculate_severity_statistics(categorized) do
    %{
      design_count: length(categorized.design),
      readability_count: length(categorized.readability),
      refactor_count: length(categorized.refactor),
      warning_count: length(categorized.warning),
      consistency_count: length(categorized.consistency),
      most_common_category: find_most_common_category(categorized),
      severity_distribution: calculate_severity_distribution(categorized)
    }
  end

  defp find_most_common_category(categorized) do
    category_counts = %{
      design: categorized.design_count,
      readability: categorized.readability_count,
      refactor: categorized.refactor_count,
      warning: categorized.warning_count,
      consistency: categorized.consistency_count
    }

    case Enum.max_by(category_counts, fn {_category, count} -> count end) do
      {category, count} when count > 0 -> category
      _ -> :none
    end
  end

  defp calculate_severity_distribution(categorized) do
    total = categorized.total_issues

    if total > 0 do
      %{
        design_percentage: categorized.design_count / total * 100,
        readability_percentage: categorized.readability_count / total * 100,
        refactor_percentage: categorized.refactor_count / total * 100,
        warning_percentage: categorized.warning_count / total * 100,
        consistency_percentage: categorized.consistency_count / total * 100
      }
    else
      %{
        design_percentage: 0,
        readability_percentage: 0,
        refactor_percentage: 0,
        warning_percentage: 0,
        consistency_percentage: 0
      }
    end
  end

  # Task 2.4.1.4: Extract readability and complexity metrics
  defp extract_quality_metrics(parsed_results, categorized_issues) do
    quality_metrics = %{
      readability_score: calculate_readability_score(categorized_issues),
      complexity_indicators: extract_complexity_indicators(parsed_results),
      maintainability_score: calculate_maintainability_score(categorized_issues),
      code_style_score: calculate_code_style_score(categorized_issues),
      files_analyzed: parsed_results.summary.files_analyzed,
      total_issues: categorized_issues.total_issues,
      execution_time_ms: parsed_results.execution_time_ms
    }

    {:ok, quality_metrics}
  end

  defp calculate_readability_score(categorized_issues) do
    readability_issues = categorized_issues.readability_count
    total_issues = categorized_issues.total_issues

    # Base score of 100, penalize for readability issues
    base_score = 100
    # Max 50 point penalty
    readability_penalty = min(50, readability_issues * 5)

    # Additional penalty if readability issues dominate
    dominance_penalty =
      if readability_issues > total_issues / 2 and total_issues > 0 do
        20
      else
        0
      end

    max(0, base_score - readability_penalty - dominance_penalty)
  end

  defp extract_complexity_indicators(parsed_results) do
    # Extract complexity-related findings from Credo results
    complexity_checks = [
      "Credo.Check.Refactor.ABCSize",
      "Credo.Check.Refactor.CyclomaticComplexity",
      "Credo.Check.Refactor.Nesting",
      "Credo.Check.Refactor.FunctionArity"
    ]

    complexity_issues =
      parsed_results.issues
      |> Enum.filter(fn issue ->
        issue.check in complexity_checks
      end)

    %{
      complexity_issues_count: length(complexity_issues),
      complexity_issues: complexity_issues,
      has_nesting_issues: Enum.any?(complexity_issues, &String.contains?(&1.check, "Nesting")),
      has_abc_issues: Enum.any?(complexity_issues, &String.contains?(&1.check, "ABCSize"))
    }
  end

  defp calculate_maintainability_score(categorized_issues) do
    # Calculate based on refactor and design issues
    refactor_issues = categorized_issues.refactor_count
    design_issues = categorized_issues.design_count

    base_score = 100
    refactor_penalty = min(30, refactor_issues * 3)
    design_penalty = min(25, design_issues * 5)

    max(0, base_score - refactor_penalty - design_penalty)
  end

  defp calculate_code_style_score(categorized_issues) do
    # Calculate based on consistency and readability issues
    consistency_issues = categorized_issues.consistency_count
    readability_issues = categorized_issues.readability_count

    base_score = 100
    consistency_penalty = min(25, consistency_issues * 4)
    style_penalty = min(25, readability_issues * 2)

    max(0, base_score - consistency_penalty - style_penalty)
  end

  # Task 2.4.1.5: Generate Credo score for evaluation
  defp calculate_credo_score(categorized_issues, quality_metrics) do
    # Weighted scoring based on different quality dimensions
    weights = %{
      readability: 0.3,
      maintainability: 0.25,
      code_style: 0.25,
      issue_severity: 0.2
    }

    severity_score = calculate_severity_score(categorized_issues)

    weighted_score =
      quality_metrics.readability_score * weights.readability +
        quality_metrics.maintainability_score * weights.maintainability +
        quality_metrics.code_style_score * weights.code_style +
        severity_score * weights.issue_severity

    credo_score = round(weighted_score)

    {:ok, credo_score}
  end

  defp calculate_severity_score(categorized_issues) do
    total_weighted_penalty =
      categorized_issues.design_count * Map.get(@severity_weights, "design", 1.0) +
        categorized_issues.readability_count * Map.get(@severity_weights, "readability", 0.8) +
        categorized_issues.refactor_count * Map.get(@severity_weights, "refactor", 0.6) +
        categorized_issues.warning_count * Map.get(@severity_weights, "warning", 0.4) +
        categorized_issues.consistency_count * Map.get(@severity_weights, "consistency", 0.3)

    # Convert penalty to score (higher penalty = lower score)
    base_score = 100
    # Max 80 point penalty
    penalty = min(80, total_weighted_penalty * 2)

    # Minimum score of 20
    max(20, base_score - penalty)
  end

  @doc """
  Generates comprehensive Credo analysis report.
  """
  def generate_credo_report(analysis_result) do
    report = %{
      summary: %{
        overall_score: analysis_result.credo_score,
        total_issues: analysis_result.categorized_issues.total_issues,
        files_analyzed: analysis_result.quality_metrics.files_analyzed,
        analysis_duration_ms: analysis_result.analysis_duration_ms,
        most_common_category: analysis_result.categorized_issues.most_common_category
      },
      quality_breakdown: %{
        readability_score: analysis_result.quality_metrics.readability_score,
        maintainability_score: analysis_result.quality_metrics.maintainability_score,
        code_style_score: analysis_result.quality_metrics.code_style_score,
        complexity_indicators: analysis_result.quality_metrics.complexity_indicators
      },
      issue_categorization: analysis_result.categorized_issues,
      recommendations: generate_credo_recommendations(analysis_result),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_credo_recommendations(analysis_result) do
    recommendations = []
    categorized = analysis_result.categorized_issues

    recommendations =
      if categorized.design_count > 5 do
        [
          "Review code design patterns - #{categorized.design_count} design issues found"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if categorized.readability_count > 10 do
        [
          "Improve code readability - #{categorized.readability_count} readability issues found"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if categorized.warning_count > 0 do
        [
          "Address critical warnings - #{categorized.warning_count} warnings found"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis_result.quality_metrics.complexity_indicators.has_nesting_issues do
        ["Reduce function nesting complexity" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["Code quality analysis shows good adherence to Elixir conventions"]
    else
      recommendations
    end
  end

  @doc """
  Validates Credo analysis results against quality thresholds.
  """
  def validate_credo_results(analysis_result, thresholds \\ default_credo_thresholds()) do
    validation = %{
      score_acceptable: analysis_result.credo_score >= thresholds.minimum_credo_score,
      issue_count_acceptable:
        analysis_result.categorized_issues.total_issues <= thresholds.max_total_issues,
      readability_acceptable:
        analysis_result.quality_metrics.readability_score >= thresholds.minimum_readability_score,
      no_critical_warnings:
        analysis_result.categorized_issues.warning_count <= thresholds.max_warning_count
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_credo_validation_issues(validation, analysis_result)
    }
  end

  defp default_credo_thresholds do
    %{
      minimum_credo_score: 70,
      max_total_issues: 50,
      minimum_readability_score: 80,
      max_warning_count: 5
    }
  end

  defp collect_credo_validation_issues(validation, analysis_result) do
    issues = []

    issues =
      if validation.score_acceptable do
        issues
      else
        ["Credo score below threshold: #{analysis_result.credo_score}" | issues]
      end

    issues =
      if validation.issue_count_acceptable do
        issues
      else
        ["Too many Credo issues: #{analysis_result.categorized_issues.total_issues}" | issues]
      end

    issues =
      if validation.readability_acceptable do
        issues
      else
        [
          "Readability score below threshold: #{analysis_result.quality_metrics.readability_score}"
          | issues
        ]
      end

    issues =
      if validation.no_critical_warnings do
        issues
      else
        [
          "Critical warnings present: #{analysis_result.categorized_issues.warning_count}"
          | issues
        ]
      end

    issues
  end

  @doc """
  Checks if Credo is available and properly configured in the environment.
  """
  def credo_available?(source_path) do
    case System.cmd("mix", ["help", "credo"], cd: source_path, stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Creates a custom Credo configuration optimized for SWE-bench evaluation.
  """
  def create_evaluation_config(source_path, opts \\ []) do
    config_path = Path.join(source_path, @default_config_path)

    config = %{
      strict_mode: Keyword.get(opts, :strict, true),
      checks_enabled: get_enabled_checks(opts),
      output_format: "json",
      all_priorities: true
    }

    case create_default_credo_config(config_path, config) do
      :ok -> {:ok, config_path}
      {:error, reason} -> {:error, reason}
    end
  end
end
