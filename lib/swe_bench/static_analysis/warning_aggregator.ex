defmodule SweBench.StaticAnalysis.WarningAggregator do
  @moduledoc """
  Aggregates and processes warnings from multiple static analysis tools.

  Collects warnings from Credo and Dialyzer, deduplicates similar issues,
  prioritizes warnings by impact, maps to source code locations,
  and generates comprehensive reports.
  """

  require Logger

  # alias SweBench.StaticAnalysis.{CredoAnalyzer, DialyzerIntegration}

  @priority_weights %{
    :critical => 10,
    :high => 7,
    :medium => 4,
    :low => 2,
    :info => 1
  }

  @doc """
  Aggregates warnings from all static analysis sources.

  ## Parameters
    - credo_result: Result from Credo analysis
    - dialyzer_result: Result from Dialyzer analysis
    - opts: Aggregation options including deduplication and prioritization settings

  ## Returns
    - {:ok, aggregated_warnings} - Successfully aggregated and processed warnings
    - {:error, reason} - Aggregation error
  """
  def aggregate_all_warnings(credo_result, dialyzer_result, opts \\ []) do
    Logger.info("Aggregating warnings from Credo and Dialyzer analysis")

    with {:ok, credo_warnings} <- extract_credo_warnings(credo_result),
         {:ok, dialyzer_warnings} <- extract_dialyzer_warnings(dialyzer_result),
         {:ok, unified_warnings} <- unify_warning_formats(credo_warnings, dialyzer_warnings),
         {:ok, deduplicated_warnings} <- deduplicate_similar_warnings(unified_warnings, opts),
         {:ok, prioritized_warnings} <- prioritize_warnings_by_impact(deduplicated_warnings),
         {:ok, location_mapped_warnings} <- map_warnings_to_locations(prioritized_warnings),
         {:ok, comprehensive_report} <-
           generate_comprehensive_report(location_mapped_warnings, credo_result, dialyzer_result) do
      aggregation_result = %{
        total_warnings: length(location_mapped_warnings),
        credo_warnings_count: length(credo_warnings),
        dialyzer_warnings_count: length(dialyzer_warnings),
        duplicates_removed: length(unified_warnings) - length(deduplicated_warnings),
        prioritized_warnings: prioritized_warnings,
        location_mapped_warnings: location_mapped_warnings,
        comprehensive_report: comprehensive_report,
        aggregated_at: DateTime.utc_now()
      }

      Logger.info(
        "Warning aggregation complete: #{aggregation_result.total_warnings} warnings processed"
      )

      {:ok, aggregation_result}
    else
      {:error, reason} ->
        Logger.warning("Warning aggregation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.4.3.1: Collect all static analysis warnings
  defp extract_credo_warnings(credo_result) do
    case credo_result do
      %{categorized_issues: categorized} ->
        warnings =
          categorized.design ++
            categorized.readability ++
            categorized.refactor ++
            categorized.warning ++
            categorized.consistency

        normalized_warnings =
          warnings
          |> Enum.map(&normalize_credo_warning/1)

        {:ok, normalized_warnings}

      _ ->
        {:error, :invalid_credo_result}
    end
  end

  defp normalize_credo_warning(credo_issue) do
    %{
      source: :credo,
      category: credo_issue.category,
      severity: map_credo_severity(credo_issue.category),
      message: credo_issue.message,
      filename: credo_issue.filename,
      line_no: credo_issue.line_no,
      column: credo_issue.column,
      check_name: credo_issue.check,
      priority: credo_issue.priority,
      impact_level: assess_credo_impact(credo_issue)
    }
  end

  defp map_credo_severity(category) do
    case category do
      "warning" -> :high
      "design" -> :high
      "refactor" -> :medium
      "readability" -> :medium
      "consistency" -> :low
      _ -> :info
    end
  end

  defp assess_credo_impact(credo_issue) do
    # Assess impact based on check type and category
    high_impact_checks = [
      "Credo.Check.Warning.UnsafeToAtom",
      "Credo.Check.Warning.UnsafeExec",
      "Credo.Check.Design.DuplicatedCode"
    ]

    if credo_issue.check in high_impact_checks do
      :critical
    else
      case credo_issue.category do
        "warning" -> :high
        "design" -> :medium
        "refactor" -> :medium
        "readability" -> :low
        "consistency" -> :low
        _ -> :info
      end
    end
  end

  defp extract_dialyzer_warnings(dialyzer_result) do
    case dialyzer_result do
      %{categorized_warnings: categorized} ->
        all_warnings =
          categorized.by_severity.error ++
            categorized.by_severity.warning ++
            categorized.by_severity.info

        normalized_warnings =
          all_warnings
          |> Enum.map(&normalize_dialyzer_warning/1)

        {:ok, normalized_warnings}

      _ ->
        {:error, :invalid_dialyzer_result}
    end
  end

  defp normalize_dialyzer_warning(dialyzer_warning) do
    %{
      source: :dialyzer,
      category: "type_analysis",
      severity: map_dialyzer_severity(dialyzer_warning.severity),
      message: dialyzer_warning.message,
      filename: dialyzer_warning.filename,
      line_no: dialyzer_warning.line_no,
      column: nil,
      check_name: "dialyzer_#{dialyzer_warning.warning_type}",
      priority: nil,
      warning_type: dialyzer_warning.warning_type,
      impact_level: assess_dialyzer_impact(dialyzer_warning)
    }
  end

  defp map_dialyzer_severity("error"), do: :critical
  defp map_dialyzer_severity("warning"), do: :high
  defp map_dialyzer_severity("info"), do: :medium
  defp map_dialyzer_severity(_), do: :low

  defp assess_dialyzer_impact(dialyzer_warning) do
    warning_type = dialyzer_warning.warning_type

    cond do
      critical_dialyzer_warning?(warning_type) -> :critical
      high_priority_dialyzer_warning?(warning_type) -> :high
      medium_priority_dialyzer_warning?(warning_type) -> :medium
      low_priority_dialyzer_warning?(warning_type) -> :low
      true -> :info
    end
  end

  defp critical_dialyzer_warning?(type) do
    type in [:no_return, :no_match, :no_fail_call]
  end

  defp high_priority_dialyzer_warning?(type) do
    type in [:contract_violation, :race_condition]
  end

  defp medium_priority_dialyzer_warning?(type) do
    type in [:opaque_violation, :callback_issue]
  end

  defp low_priority_dialyzer_warning?(type) do
    type in [:unused_function]
  end

  # Task 2.4.3.2: Deduplicate similar warnings
  defp unify_warning_formats(credo_warnings, dialyzer_warnings) do
    unified_warnings = credo_warnings ++ dialyzer_warnings
    {:ok, unified_warnings}
  end

  defp deduplicate_similar_warnings(warnings, opts) do
    enable_deduplication = Keyword.get(opts, :deduplicate, true)

    if enable_deduplication do
      deduplicated =
        warnings
        |> Enum.uniq_by(&create_warning_signature/1)

      Logger.debug("Deduplication: #{length(warnings)} -> #{length(deduplicated)} warnings")
      {:ok, deduplicated}
    else
      {:ok, warnings}
    end
  end

  defp create_warning_signature(warning) do
    # Create unique signature for deduplication
    "#{warning.filename}:#{warning.line_no}:#{warning.check_name}"
  end

  # Task 2.4.3.3: Prioritize warnings by impact
  defp prioritize_warnings_by_impact(warnings) do
    prioritized_warnings =
      warnings
      |> Enum.map(&add_priority_score/1)
      |> Enum.sort_by(& &1.priority_score, :desc)

    priority_groups = group_warnings_by_priority(prioritized_warnings)

    prioritization_result = %{
      warnings: prioritized_warnings,
      priority_groups: priority_groups,
      critical_count: length(Map.get(priority_groups, :critical, [])),
      high_count: length(Map.get(priority_groups, :high, [])),
      medium_count: length(Map.get(priority_groups, :medium, [])),
      low_count: length(Map.get(priority_groups, :low, [])),
      info_count: length(Map.get(priority_groups, :info, []))
    }

    {:ok, prioritization_result}
  end

  defp add_priority_score(warning) do
    base_score = Map.get(@priority_weights, warning.impact_level, 1)

    # Boost score for certain files or patterns
    location_bonus = calculate_location_bonus(warning)

    # Boost score for security-related issues
    security_bonus = calculate_security_bonus(warning)

    total_score = base_score + location_bonus + security_bonus

    Map.put(warning, :priority_score, total_score)
  end

  defp calculate_location_bonus(warning) do
    filename = warning.filename || ""

    cond do
      # Core library code
      String.contains?(filename, "lib/") -> 2
      # Web interface code
      String.contains?(filename, "web/") -> 1
      # Test code
      String.contains?(filename, "test/") -> 0
      # Default bonus
      true -> 1
    end
  end

  defp calculate_security_bonus(warning) do
    message = String.downcase(warning.message)

    security_keywords = ["unsafe", "security", "injection", "atom", "exec"]

    if Enum.any?(security_keywords, &String.contains?(message, &1)) do
      # High security bonus
      5
    else
      0
    end
  end

  defp group_warnings_by_priority(prioritized_warnings) do
    prioritized_warnings
    |> Enum.group_by(& &1.impact_level)
  end

  # Task 2.4.3.4: Map warnings to code locations
  defp map_warnings_to_locations(prioritized_warnings) do
    location_mapped =
      prioritized_warnings.warnings
      |> Enum.map(&enhance_location_context/1)

    location_analysis = analyze_warning_locations(location_mapped)

    mapping_result = %{
      warnings: location_mapped,
      location_analysis: location_analysis,
      files_affected: count_affected_files(location_mapped),
      hotspots: identify_warning_hotspots(location_mapped)
    }

    {:ok, mapping_result}
  end

  defp enhance_location_context(warning) do
    enhanced_warning =
      Map.merge(warning, %{
        file_type: classify_file_type(warning.filename),
        module_name: extract_module_name(warning.filename),
        relative_path: normalize_file_path(warning.filename)
      })

    enhanced_warning
  end

  defp classify_file_type(filename) do
    cond do
      String.ends_with?(filename, ".ex") -> :elixir_source
      String.ends_with?(filename, ".exs") -> :elixir_script
      String.contains?(filename, "test/") -> :test_file
      String.contains?(filename, "lib/") -> :library_file
      String.contains?(filename, "web/") -> :web_file
      true -> :unknown
    end
  end

  defp extract_module_name(filename) do
    # Extract likely module name from file path
    case Path.basename(filename, ".ex") do
      basename when basename != "" ->
        basename
        |> String.split("_")
        |> Enum.map_join(".", &String.capitalize/1)

      _ ->
        "Unknown"
    end
  end

  defp normalize_file_path(filename) do
    # Normalize file path for consistent reporting
    case filename do
      nil -> "unknown"
      path -> Path.relative_to_cwd(path)
    end
  end

  defp analyze_warning_locations(warnings) do
    files_with_warnings =
      warnings
      |> Enum.group_by(& &1.relative_path)

    %{
      total_files_affected: map_size(files_with_warnings),
      warnings_per_file: calculate_warnings_per_file(files_with_warnings),
      most_problematic_file: find_most_problematic_file(files_with_warnings),
      file_type_distribution: calculate_file_type_distribution(warnings)
    }
  end

  defp calculate_warnings_per_file(files_with_warnings) do
    if map_size(files_with_warnings) > 0 do
      total_warnings =
        files_with_warnings
        |> Map.values()
        |> List.flatten()
        |> length()

      total_warnings / map_size(files_with_warnings)
    else
      0
    end
  end

  defp find_most_problematic_file(files_with_warnings) do
    case Enum.max_by(files_with_warnings, fn {_file, warnings} -> length(warnings) end, fn ->
           {nil, []}
         end) do
      {file, [_ | _] = warnings} ->
        %{file: file, warning_count: length(warnings)}

      _ ->
        %{file: nil, warning_count: 0}
    end
  end

  defp calculate_file_type_distribution(warnings) do
    warnings
    |> Enum.group_by(& &1.file_type)
    |> Enum.into(%{}, fn {type, type_warnings} ->
      {type, length(type_warnings)}
    end)
  end

  defp count_affected_files(warnings) do
    warnings
    |> Enum.map(& &1.relative_path)
    |> Enum.uniq()
    |> length()
  end

  defp identify_warning_hotspots(warnings) do
    # Identify files or modules with high warning density
    file_warning_counts =
      warnings
      |> Enum.group_by(& &1.relative_path)
      |> Enum.map(fn {file, file_warnings} ->
        %{
          file: file,
          warning_count: length(file_warnings),
          critical_count: count_critical_warnings(file_warnings),
          warning_density: calculate_warning_density(file_warnings)
        }
      end)
      # Only files with 4+ warnings
      |> Enum.filter(fn hotspot -> hotspot.warning_count > 3 end)
      |> Enum.sort_by(& &1.warning_density, :desc)

    %{
      hotspots: file_warning_counts,
      hotspot_count: length(file_warning_counts),
      most_critical_hotspot: List.first(file_warning_counts)
    }
  end

  defp count_critical_warnings(warnings) do
    Enum.count(warnings, fn warning ->
      warning.impact_level in [:critical, :high]
    end)
  end

  defp calculate_warning_density(warnings) do
    # Simple density calculation - in production would consider LOC
    critical_count = count_critical_warnings(warnings)
    total_count = length(warnings)

    if total_count > 0 do
      (critical_count * 2 + total_count) / total_count
    else
      0
    end
  end

  # Task 2.4.3.5: Generate comprehensive reports
  defp generate_comprehensive_report(location_mapped_warnings, credo_result, dialyzer_result) do
    report = %{
      executive_summary:
        create_executive_summary(location_mapped_warnings, credo_result, dialyzer_result),
      detailed_analysis: create_detailed_analysis(location_mapped_warnings),
      tool_comparison: create_tool_comparison(credo_result, dialyzer_result),
      actionable_recommendations: create_actionable_recommendations(location_mapped_warnings),
      quality_trends: analyze_quality_trends(location_mapped_warnings)
    }

    {:ok, report}
  end

  defp create_executive_summary(location_mapped_warnings, credo_result, dialyzer_result) do
    %{
      overall_quality_grade: calculate_overall_quality_grade(credo_result, dialyzer_result),
      total_issues: location_mapped_warnings.files_affected,
      critical_issues: location_mapped_warnings.hotspots.hotspot_count,
      credo_score: credo_result.credo_score,
      dialyzer_score: dialyzer_result.type_safety_score,
      composite_score:
        calculate_composite_score(credo_result.credo_score, dialyzer_result.type_safety_score),
      primary_concerns: identify_primary_concerns(location_mapped_warnings)
    }
  end

  defp calculate_overall_quality_grade(credo_result, dialyzer_result) do
    composite_score =
      calculate_composite_score(credo_result.credo_score, dialyzer_result.type_safety_score)

    cond do
      composite_score >= 90 -> :excellent
      composite_score >= 80 -> :good
      composite_score >= 70 -> :acceptable
      composite_score >= 60 -> :needs_improvement
      true -> :poor
    end
  end

  defp calculate_composite_score(credo_score, dialyzer_score) do
    # Weight Credo slightly higher due to broader coverage
    round(credo_score * 0.6 + dialyzer_score * 0.4)
  end

  defp identify_primary_concerns(location_mapped_warnings) do
    # Identify the most critical categories of issues
    critical_warnings =
      location_mapped_warnings.warnings
      |> Enum.filter(fn warning ->
        warning.impact_level in [:critical, :high]
      end)

    if Enum.empty?(critical_warnings) do
      [:minor_style_issues]
    else
      critical_warnings
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {category, warnings} ->
        {category, length(warnings)}
      end)
      |> Enum.sort_by(fn {_category, count} -> count end, :desc)
      |> Enum.take(3)
      |> Enum.map(fn {category, _count} -> String.to_atom(category) end)
    end
  end

  defp create_detailed_analysis(location_mapped_warnings) do
    %{
      warning_distribution: calculate_warning_distribution(location_mapped_warnings.warnings),
      file_analysis: location_mapped_warnings.location_analysis,
      hotspot_analysis: location_mapped_warnings.hotspots,
      impact_breakdown: create_impact_breakdown(location_mapped_warnings.warnings)
    }
  end

  defp calculate_warning_distribution(warnings) do
    %{
      by_source: Enum.frequencies_by(warnings, & &1.source),
      by_severity: Enum.frequencies_by(warnings, & &1.severity),
      by_impact: Enum.frequencies_by(warnings, & &1.impact_level),
      by_category: Enum.frequencies_by(warnings, & &1.category)
    }
  end

  defp create_impact_breakdown(warnings) do
    impact_groups = Enum.group_by(warnings, & &1.impact_level)

    Enum.into(impact_groups, %{}, fn {impact, impact_warnings} ->
      {impact,
       %{
         count: length(impact_warnings),
         # First 3 examples
         examples: Enum.take(impact_warnings, 3),
         files_affected: count_unique_files(impact_warnings)
       }}
    end)
  end

  defp count_unique_files(warnings) do
    warnings
    |> Enum.map(& &1.relative_path)
    |> Enum.uniq()
    |> length()
  end

  defp create_tool_comparison(credo_result, dialyzer_result) do
    %{
      credo_analysis: %{
        score: credo_result.credo_score,
        issues_found: credo_result.categorized_issues.total_issues,
        analysis_time_ms: credo_result.analysis_duration_ms,
        coverage: "code_quality_and_style"
      },
      dialyzer_analysis: %{
        score: dialyzer_result.type_safety_score,
        warnings_found: dialyzer_result.categorized_warnings.total_warnings,
        analysis_time_ms: dialyzer_result.analysis_duration_ms,
        coverage: "type_safety_and_contracts"
      },
      complementary_coverage: %{
        overlapping_areas: ["function_definitions", "module_structure"],
        unique_credo_coverage: ["code_style", "readability", "complexity"],
        unique_dialyzer_coverage: ["type_specifications", "contract_compliance", "data_flow"]
      }
    }
  end

  defp create_actionable_recommendations(location_mapped_warnings) do
    hotspots = location_mapped_warnings.hotspots.hotspots

    recommendations = []

    recommendations =
      if length(hotspots) > 0 do
        top_hotspot = List.first(hotspots)

        [
          "Priority: Address #{top_hotspot.warning_count} warnings in #{top_hotspot.file}"
          | recommendations
        ]
      else
        recommendations
      end

    critical_warnings =
      location_mapped_warnings.warnings
      |> Enum.filter(fn warning -> warning.impact_level == :critical end)

    recommendations =
      if length(critical_warnings) > 0 do
        ["Immediate: Fix #{length(critical_warnings)} critical issues" | recommendations]
      else
        recommendations
      end

    # File-specific recommendations
    file_recommendations = generate_file_specific_recommendations(location_mapped_warnings)

    recommendations ++ file_recommendations
  end

  defp generate_file_specific_recommendations(location_mapped_warnings) do
    # Generate recommendations based on file-specific warning patterns
    files_analysis = location_mapped_warnings.location_analysis

    recommendations = []

    recommendations =
      if files_analysis.warnings_per_file > 5 do
        [
          "Consider breaking up large files - average #{files_analysis.warnings_per_file} warnings per file"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if files_analysis.most_problematic_file.warning_count > 10 do
        file = files_analysis.most_problematic_file.file
        count = files_analysis.most_problematic_file.warning_count
        ["Focus refactoring efforts on #{file} (#{count} warnings)" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp analyze_quality_trends(location_mapped_warnings) do
    # Analyze trends in warning patterns
    %{
      warning_concentration: calculate_warning_concentration(location_mapped_warnings.warnings),
      complexity_indicators: extract_complexity_trends(location_mapped_warnings.warnings),
      type_safety_trends: extract_type_safety_trends(location_mapped_warnings.warnings)
    }
  end

  defp calculate_warning_concentration(warnings) do
    total_files = count_unique_files(warnings)
    total_warnings = length(warnings)

    if total_files > 0 do
      %{
        warnings_per_file: total_warnings / total_files,
        concentration_level: classify_concentration(total_warnings / total_files)
      }
    else
      %{warnings_per_file: 0, concentration_level: :none}
    end
  end

  defp classify_concentration(warnings_per_file) do
    cond do
      warnings_per_file > 10 -> :very_high
      warnings_per_file > 5 -> :high
      warnings_per_file > 2 -> :moderate
      warnings_per_file > 0 -> :low
      true -> :none
    end
  end

  defp extract_complexity_trends(warnings) do
    complexity_warnings =
      warnings
      |> Enum.filter(fn warning ->
        String.contains?(warning.check_name, "complexity") or
          String.contains?(warning.check_name, "nesting") or
          String.contains?(warning.check_name, "ABC")
      end)

    %{
      complexity_warning_count: length(complexity_warnings),
      complexity_affected_files: count_unique_files(complexity_warnings),
      complexity_trend: classify_complexity_trend(complexity_warnings)
    }
  end

  defp classify_complexity_trend(complexity_warnings) do
    count = length(complexity_warnings)

    cond do
      count > 10 -> :concerning
      count > 5 -> :moderate
      count > 0 -> :minor
      true -> :none
    end
  end

  defp extract_type_safety_trends(warnings) do
    type_warnings =
      warnings
      |> Enum.filter(&(&1.source == :dialyzer))

    %{
      type_warning_count: length(type_warnings),
      type_affected_files: count_unique_files(type_warnings),
      type_safety_trend: classify_type_safety_trend(type_warnings)
    }
  end

  defp classify_type_safety_trend(type_warnings) do
    critical_type_warnings =
      Enum.count(type_warnings, fn warning ->
        warning.impact_level in [:critical, :high]
      end)

    cond do
      critical_type_warnings > 5 -> :poor
      critical_type_warnings > 2 -> :needs_attention
      critical_type_warnings > 0 -> :minor_issues
      length(type_warnings) > 0 -> :informational_only
      true -> :excellent
    end
  end

  @doc """
  Validates aggregated warning results against quality thresholds.
  """
  def validate_aggregation_results(
        aggregation_result,
        thresholds \\ default_aggregation_thresholds()
      ) do
    validation = %{
      warning_count_acceptable:
        aggregation_result.total_warnings <= thresholds.max_total_warnings,
      critical_count_acceptable:
        aggregation_result.prioritized_warnings.critical_count <= thresholds.max_critical_warnings,
      hotspot_count_acceptable:
        aggregation_result.location_mapped_warnings.hotspots.hotspot_count <=
          thresholds.max_hotspots,
      files_affected_acceptable:
        aggregation_result.location_mapped_warnings.files_affected <=
          thresholds.max_affected_files
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_aggregation_validation_issues(validation, aggregation_result)
    }
  end

  defp default_aggregation_thresholds do
    %{
      max_total_warnings: 100,
      max_critical_warnings: 5,
      max_hotspots: 3,
      max_affected_files: 20
    }
  end

  defp collect_aggregation_validation_issues(validation, aggregation_result) do
    issues = []

    issues =
      if validation.warning_count_acceptable do
        issues
      else
        ["Total warning count exceeds threshold: #{aggregation_result.total_warnings}" | issues]
      end

    issues =
      if validation.critical_count_acceptable do
        issues
      else
        count = aggregation_result.prioritized_warnings.critical_count
        ["Critical warning count exceeds threshold: #{count}" | issues]
      end

    issues =
      if validation.hotspot_count_acceptable do
        issues
      else
        count = aggregation_result.location_mapped_warnings.hotspots.hotspot_count
        ["Warning hotspot count exceeds threshold: #{count}" | issues]
      end

    issues
  end
end
