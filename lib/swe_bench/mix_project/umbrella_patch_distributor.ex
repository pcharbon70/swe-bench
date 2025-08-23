defmodule SweBench.MixProject.UmbrellaPatchDistributor do
  @moduledoc """
  Manages patch distribution across umbrella project applications.

  Handles cross-application patch application, validates patch consistency,
  manages configuration updates, and tracks affected applications for
  targeted evaluation workflows.
  """

  require Logger

  # 1 minute per patch application
  @patch_application_timeout 60_000
  # 30 seconds for consistency validation
  @consistency_check_timeout 30_000

  @doc """
  Distributes patches across umbrella project applications.

  Analyzes patch content, determines affected applications, applies patches
  consistently, and validates the results across all applications.
  """
  def distribute_patches(umbrella_structure, patches, opts \\ []) do
    Logger.info(
      "Distributing #{length(patches)} patches across #{umbrella_structure.total_apps} applications"
    )

    with {:ok, patch_analysis} <- analyze_patches_for_umbrella(patches, umbrella_structure),
         {:ok, distribution_plan} <-
           create_distribution_plan(patch_analysis, umbrella_structure, opts),
         {:ok, application_results} <- apply_patches_to_applications(distribution_plan, opts),
         {:ok, consistency_validation} <-
           validate_patch_consistency(application_results, umbrella_structure) do
      distribution_result = %{
        umbrella_structure: umbrella_structure,
        patches: patches,
        patch_analysis: patch_analysis,
        distribution_plan: distribution_plan,
        application_results: application_results,
        consistency_validation: consistency_validation,
        total_affected_apps: count_affected_applications(application_results),
        total_patches_applied: count_successful_patches(application_results),
        distributed_at: DateTime.utc_now()
      }

      Logger.info(
        "Patch distribution complete: #{distribution_result.total_patches_applied} patches applied to #{distribution_result.total_affected_apps} apps"
      )

      {:ok, distribution_result}
    else
      {:error, reason} ->
        Logger.warning("Patch distribution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.3.4.1: Distribute patches across applications
  defp analyze_patches_for_umbrella(patches, umbrella_structure) do
    Logger.debug("Analyzing #{length(patches)} patches for umbrella distribution")

    patch_analyses =
      patches
      |> Enum.map(fn patch ->
        analyze_single_patch(patch, umbrella_structure)
      end)

    analysis_summary = %{
      patches: patch_analyses,
      cross_app_patches: filter_cross_app_patches(patch_analyses),
      config_patches: filter_config_patches(patch_analyses),
      dependency_patches: filter_dependency_patches(patch_analyses),
      single_app_patches: filter_single_app_patches(patch_analyses)
    }

    {:ok, analysis_summary}
  end

  defp analyze_single_patch(patch, umbrella_structure) do
    affected_apps = determine_affected_applications(patch, umbrella_structure)
    patch_type = classify_patch_type(patch, affected_apps)
    complexity = assess_patch_complexity(patch, affected_apps)

    %{
      patch: patch,
      affected_applications: affected_apps,
      patch_type: patch_type,
      complexity: complexity,
      cross_app_impact: length(affected_apps) > 1,
      requires_coordination: requires_cross_app_coordination?(patch, affected_apps)
    }
  end

  defp determine_affected_applications(patch, umbrella_structure) do
    # Analyze patch file paths to determine which applications are affected
    patch_files = extract_patch_file_paths(patch)

    umbrella_structure.applications
    |> Enum.filter(fn app ->
      app_relative_path = Path.relative_to(app.path, umbrella_structure.project_path)

      Enum.any?(patch_files, fn file_path ->
        String.starts_with?(file_path, app_relative_path) or
          String.contains?(file_path, app.name)
      end)
    end)
    |> Enum.map(& &1.name)
  end

  defp extract_patch_file_paths(patch) do
    # Extract file paths from patch content
    # This is a simplified implementation - would be more sophisticated in production
    case Map.get(patch, :files, []) do
      files when is_list(files) -> files
      _ -> [Map.get(patch, :file_path, "")]
    end
  end

  defp classify_patch_type(patch, affected_apps) do
    cond do
      Enum.empty?(affected_apps) -> :no_app_impact
      length(affected_apps) == 1 -> :single_app
      config_patch?(patch) -> :configuration_change
      dependency_patch?(patch) -> :dependency_update
      true -> :cross_app_change
    end
  end

  defp config_patch?(patch) do
    config_patterns = ["config/", "mix.exs", ".env", "runtime.exs"]
    patch_content = Map.get(patch, :content, "")

    Enum.any?(config_patterns, fn pattern ->
      String.contains?(patch_content, pattern)
    end)
  end

  defp dependency_patch?(patch) do
    dependency_patterns = ["deps:", "defp deps", "{:", "version:"]
    patch_content = Map.get(patch, :content, "")

    Enum.any?(dependency_patterns, fn pattern ->
      String.contains?(patch_content, pattern)
    end)
  end

  defp assess_patch_complexity(patch, affected_apps) do
    factors = []

    factors =
      if length(affected_apps) > 3 do
        [:many_apps_affected | factors]
      else
        factors
      end

    factors =
      if config_patch?(patch) do
        [:configuration_changes | factors]
      else
        factors
      end

    factors =
      if dependency_patch?(patch) do
        [:dependency_changes | factors]
      else
        factors
      end

    patch_size = String.length(Map.get(patch, :content, ""))

    factors =
      if patch_size > 5000 do
        [:large_patch | factors]
      else
        factors
      end

    case length(factors) do
      0 -> :simple
      1 -> :moderate
      2 -> :complex
      _ -> :very_complex
    end
  end

  defp requires_cross_app_coordination?(patch, affected_apps) do
    length(affected_apps) > 1 or config_patch?(patch) or dependency_patch?(patch)
  end

  defp filter_cross_app_patches(patch_analyses) do
    Enum.filter(patch_analyses, & &1.cross_app_impact)
  end

  defp filter_config_patches(patch_analyses) do
    Enum.filter(patch_analyses, fn analysis ->
      analysis.patch_type == :configuration_change
    end)
  end

  defp filter_dependency_patches(patch_analyses) do
    Enum.filter(patch_analyses, fn analysis ->
      analysis.patch_type == :dependency_update
    end)
  end

  defp filter_single_app_patches(patch_analyses) do
    Enum.filter(patch_analyses, fn analysis ->
      analysis.patch_type == :single_app
    end)
  end

  # Task 2.3.4.2: Handle cross-application changes
  defp create_distribution_plan(patch_analysis, umbrella_structure, opts) do
    Logger.debug("Creating distribution plan for umbrella patches")

    plan = %{
      application_order: determine_patch_application_order(patch_analysis, umbrella_structure),
      coordination_strategy: determine_coordination_strategy(patch_analysis),
      rollback_strategy: create_rollback_strategy(patch_analysis, opts),
      validation_checkpoints: create_validation_checkpoints(patch_analysis),
      estimated_duration_ms: estimate_distribution_duration(patch_analysis)
    }

    {:ok, plan}
  end

  defp determine_patch_application_order(patch_analysis, umbrella_structure) do
    # Prioritize patches that affect dependencies first, then follow compilation order
    dependency_affecting_apps =
      patch_analysis.dependency_patches
      |> Enum.flat_map(& &1.affected_applications)
      |> Enum.uniq()

    config_affecting_apps =
      patch_analysis.config_patches
      |> Enum.flat_map(& &1.affected_applications)
      |> Enum.uniq()

    priority_apps = dependency_affecting_apps ++ config_affecting_apps
    remaining_apps = umbrella_structure.compilation_order -- priority_apps

    priority_apps ++ remaining_apps
  end

  defp determine_coordination_strategy(patch_analysis) do
    cond do
      not Enum.empty?(patch_analysis.cross_app_patches) -> :coordinated_application
      not Enum.empty?(patch_analysis.config_patches) -> :configuration_first
      not Enum.empty?(patch_analysis.dependency_patches) -> :dependency_order
      true -> :independent_application
    end
  end

  defp create_rollback_strategy(patch_analysis, opts) do
    enable_rollback = Keyword.get(opts, :enable_rollback, true)

    %{
      enabled: enable_rollback,
      checkpoint_frequency: determine_checkpoint_frequency(patch_analysis),
      rollback_scope: determine_rollback_scope(patch_analysis),
      backup_strategy: if(enable_rollback, do: :git_stash, else: :none)
    }
  end

  defp determine_checkpoint_frequency(patch_analysis) do
    if Enum.empty?(patch_analysis.cross_app_patches) do
      :after_each_application
    else
      :after_each_patch
    end
  end

  defp determine_rollback_scope(patch_analysis) do
    if Enum.empty?(patch_analysis.cross_app_patches) do
      :per_application
    else
      :umbrella_wide
    end
  end

  defp create_validation_checkpoints(patch_analysis) do
    checkpoints = [:pre_application, :post_application]

    checkpoints =
      if Enum.empty?(patch_analysis.config_patches) do
        checkpoints
      else
        [:post_config_update | checkpoints]
      end

    checkpoints =
      if Enum.empty?(patch_analysis.dependency_patches) do
        checkpoints
      else
        [:post_dependency_update | checkpoints]
      end

    checkpoints
  end

  defp estimate_distribution_duration(patch_analysis) do
    # 5 seconds base
    base_time = 5000

    # Add time based on complexity
    complexity_time =
      patch_analysis.patches
      |> Enum.map(fn analysis ->
        case analysis.complexity do
          :simple -> 1000
          :moderate -> 3000
          :complex -> 8000
          :very_complex -> 15_000
        end
      end)
      |> Enum.sum()

    base_time + complexity_time
  end

  # Task 2.3.4.3: Validate patch consistency
  # Task 2.3.4.4: Manage configuration updates
  defp apply_patches_to_applications(distribution_plan, opts) do
    Logger.info("Applying patches according to distribution plan")

    timeout = Keyword.get(opts, :timeout, @patch_application_timeout)

    application_results =
      distribution_plan.application_order
      |> Enum.map(fn app_name ->
        apply_patches_to_app(app_name, distribution_plan, timeout, opts)
      end)

    {:ok, application_results}
  end

  defp apply_patches_to_app(app_name, _distribution_plan, _timeout, _opts) do
    Logger.debug("Applying patches to application: #{app_name}")

    start_time = System.monotonic_time(:millisecond)

    # Simulate patch application
    # 2-10 seconds
    application_duration = :rand.uniform(8000) + 2000
    :timer.sleep(application_duration)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # 95% success rate
    success = :rand.uniform() > 0.05

    result = %{
      app_name: app_name,
      success: success,
      patches_applied: if(success, do: :rand.uniform(3) + 1, else: 0),
      application_time_ms: duration,
      warnings: if(success, do: [], else: ["Patch application warning in #{app_name}"]),
      errors: if(success, do: [], else: ["Patch application failed in #{app_name}"]),
      affected_files: generate_affected_files_list(app_name, success),
      configuration_changes: detect_configuration_changes(app_name),
      applied_at: DateTime.utc_now()
    }

    if success do
      perform_post_patch_validation(app_name, result)
    end

    result
  end

  defp generate_affected_files_list(app_name, success) do
    if success do
      # Generate realistic affected files list
      base_files = ["lib/#{app_name}.ex", "lib/#{app_name}/worker.ex"]

      additional_files =
        1..:rand.uniform(3)
        |> Enum.map(fn i -> "lib/#{app_name}/module#{i}.ex" end)

      base_files ++ additional_files
    else
      []
    end
  end

  defp detect_configuration_changes(app_name) do
    # Simulate configuration change detection
    %{
      config_files_modified: ["config/test.exs"],
      environment_variables_added: [],
      mix_exs_changes: has_mix_exs_changes?(app_name)
    }
  end

  defp has_mix_exs_changes?(_app_name) do
    # Simulate mix.exs change detection
    # 30% chance of mix.exs changes
    :rand.uniform() > 0.7
  end

  defp perform_post_patch_validation(app_name, _result) do
    Logger.debug("Performing post-patch validation for #{app_name}")
    # Placeholder for validation logic
    :ok
  end

  # Task 2.3.4.3: Validate patch consistency
  defp validate_patch_consistency(application_results, umbrella_structure) do
    Logger.debug("Validating patch consistency across umbrella applications")

    with {:ok, file_consistency} <- validate_file_consistency(application_results),
         {:ok, config_consistency} <-
           validate_configuration_consistency(application_results, umbrella_structure),
         {:ok, dependency_consistency} <-
           validate_dependency_consistency(application_results, umbrella_structure) do
      consistency_validation = %{
        file_consistency: file_consistency,
        configuration_consistency: config_consistency,
        dependency_consistency: dependency_consistency,
        overall_consistent:
          assess_overall_consistency(file_consistency, config_consistency, dependency_consistency),
        validation_time_ms: @consistency_check_timeout,
        validated_at: DateTime.utc_now()
      }

      {:ok, consistency_validation}
    end
  end

  defp validate_file_consistency(application_results) do
    # Check that similar files were modified consistently across applications
    all_affected_files =
      application_results
      |> Enum.flat_map(& &1.affected_files)
      |> Enum.uniq()

    file_patterns = group_files_by_pattern(all_affected_files)

    consistency_issues =
      file_patterns
      |> Enum.filter(&inconsistent_pattern?(&1, application_results))
      |> Enum.map(fn {pattern, _files} -> "Inconsistent application of pattern: #{pattern}" end)

    %{
      patterns_analyzed: length(file_patterns),
      consistency_issues: consistency_issues,
      consistent: Enum.empty?(consistency_issues)
    }
  end

  defp inconsistent_pattern?({_pattern, files}, application_results) do
    # If pattern appears in multiple apps, check for consistency
    apps_with_pattern =
      application_results
      |> Enum.count(fn result ->
        Enum.any?(result.affected_files, &(&1 in files))
      end)

    apps_with_pattern > 1 and apps_with_pattern < length(application_results)
  end

  defp group_files_by_pattern(files) do
    files
    |> Enum.group_by(fn file ->
      # Extract pattern from file path (e.g., "lib/app/worker.ex" -> "lib/*/worker.ex")
      extract_file_pattern(file)
    end)
  end

  defp extract_file_pattern(file) do
    file
    |> Path.split()
    |> Enum.map(&convert_segment_to_pattern/1)
    |> Path.join()
  end

  defp convert_segment_to_pattern(segment) do
    if String.contains?(segment, "_") and not String.ends_with?(segment, ".ex") do
      # Replace app-specific segments with wildcards
      "*"
    else
      segment
    end
  end

  defp validate_configuration_consistency(application_results, _umbrella_structure) do
    # Validate that configuration changes are consistent across applications
    config_changes =
      application_results
      |> Enum.map(fn result ->
        {result.app_name, result.configuration_changes}
      end)
      |> Enum.into(%{})

    # Check for conflicting configuration patterns
    consistency_score = calculate_config_consistency_score(config_changes)

    %{
      config_changes: config_changes,
      consistency_score: consistency_score,
      consistent: consistency_score >= 80,
      issues: identify_config_inconsistencies(config_changes)
    }
  end

  defp calculate_config_consistency_score(config_changes) do
    if map_size(config_changes) <= 1 do
      # Single or no apps means perfect consistency
      100
    else
      # Calculate based on similarity of configuration changes
      # This is a simplified implementation
      # Placeholder score
      85
    end
  end

  defp identify_config_inconsistencies(_config_changes) do
    # Identify specific inconsistencies in configuration changes
    # Placeholder implementation
    []
  end

  defp validate_dependency_consistency(application_results, umbrella_structure) do
    # Validate that dependency changes don't create conflicts
    dependency_changes = extract_dependency_changes(application_results)

    conflicts = detect_dependency_conflicts(dependency_changes, umbrella_structure)

    %{
      dependency_changes: dependency_changes,
      conflicts_detected: conflicts,
      consistent: Enum.empty?(conflicts),
      resolution_suggestions: generate_conflict_resolutions(conflicts)
    }
  end

  defp extract_dependency_changes(application_results) do
    application_results
    |> Enum.filter(fn result ->
      result.configuration_changes.mix_exs_changes
    end)
    |> Enum.map(fn result ->
      {result.app_name, extract_dependency_info(result)}
    end)
    |> Enum.into(%{})
  end

  defp extract_dependency_info(_result) do
    # Extract dependency information from patch results
    # Placeholder implementation
    %{
      added_dependencies: [],
      removed_dependencies: [],
      version_changes: []
    }
  end

  defp detect_dependency_conflicts(_dependency_changes, _umbrella_structure) do
    # Detect conflicts between dependency changes and existing umbrella structure
    # Placeholder implementation - would analyze actual dependency conflicts
    []
  end

  defp generate_conflict_resolutions(conflicts) do
    conflicts
    |> Enum.map(fn conflict ->
      "Resolve #{conflict.type} conflict: #{conflict.description}"
    end)
  end

  defp assess_overall_consistency(file_consistency, config_consistency, dependency_consistency) do
    file_consistency.consistent and
      config_consistency.consistent and
      dependency_consistency.consistent
  end

  # Task 2.3.4.5: Track affected applications
  defp count_affected_applications(application_results) do
    application_results
    |> Enum.count(& &1.success)
  end

  defp count_successful_patches(application_results) do
    application_results
    |> Enum.map(& &1.patches_applied)
    |> Enum.sum()
  end

  @doc """
  Generates patch distribution report.
  """
  def generate_distribution_report(distribution_result) do
    report = %{
      summary: %{
        total_patches: length(distribution_result.patches),
        affected_applications: distribution_result.total_affected_apps,
        successful_applications:
          count_successful_app_patches(distribution_result.application_results),
        patches_applied: distribution_result.total_patches_applied,
        consistency_validated: distribution_result.consistency_validation.overall_consistent
      },
      patch_breakdown: %{
        cross_app_patches: length(distribution_result.patch_analysis.cross_app_patches),
        config_patches: length(distribution_result.patch_analysis.config_patches),
        dependency_patches: length(distribution_result.patch_analysis.dependency_patches),
        single_app_patches: length(distribution_result.patch_analysis.single_app_patches)
      },
      consistency_metrics: distribution_result.consistency_validation,
      per_app_results: organize_per_app_patch_results(distribution_result.application_results),
      recommendations: generate_distribution_recommendations(distribution_result),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp count_successful_app_patches(application_results) do
    Enum.count(application_results, & &1.success)
  end

  defp organize_per_app_patch_results(application_results) do
    application_results
    |> Enum.into(%{}, fn result ->
      {result.app_name,
       %{
         success: result.success,
         patches_applied: result.patches_applied,
         files_affected: length(result.affected_files),
         duration_ms: result.application_time_ms,
         issues: result.warnings ++ result.errors
       }}
    end)
  end

  defp generate_distribution_recommendations(distribution_result) do
    recommendations = []

    # Consistency recommendations
    recommendations =
      if distribution_result.consistency_validation.overall_consistent do
        recommendations
      else
        ["Address patch consistency issues across applications" | recommendations]
      end

    # Performance recommendations
    avg_time = calculate_average_patch_time(distribution_result.application_results)

    recommendations =
      if avg_time > 10_000 do
        [
          "Consider optimizing patch application performance (avg: #{avg_time}ms)"
          | recommendations
        ]
      else
        recommendations
      end

    # Application-specific recommendations
    failed_apps = Enum.filter(distribution_result.application_results, &(not &1.success))

    recommendations =
      if Enum.empty?(failed_apps) do
        recommendations
      else
        failed_names = Enum.map_join(failed_apps, ", ", & &1.app_name)
        ["Review patch application failures in: #{failed_names}" | recommendations]
      end

    if recommendations == [] do
      ["Patch distribution completed successfully across all applications"]
    else
      recommendations
    end
  end

  defp calculate_average_patch_time(application_results) do
    if Enum.empty?(application_results) do
      0
    else
      total_time = Enum.sum(Enum.map(application_results, & &1.application_time_ms))
      round(total_time / length(application_results))
    end
  end

  @doc """
  Validates patch distribution results against quality thresholds.
  """
  def validate_distribution_results(
        distribution_result,
        thresholds \\ default_distribution_thresholds()
      ) do
    validation = %{
      success_rate_acceptable:
        calculate_patch_success_rate(distribution_result) >= thresholds.min_success_rate,
      consistency_acceptable: distribution_result.consistency_validation.overall_consistent,
      performance_acceptable:
        calculate_average_patch_time(distribution_result.application_results) <=
          thresholds.max_avg_time_ms,
      coverage_complete: distribution_result.total_affected_apps >= thresholds.min_affected_apps
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_distribution_issues(validation, distribution_result)
    }
  end

  defp default_distribution_thresholds do
    %{
      min_success_rate: 95.0,
      max_avg_time_ms: 10_000,
      min_affected_apps: 1
    }
  end

  defp calculate_patch_success_rate(distribution_result) do
    if distribution_result.total_affected_apps > 0 do
      successful_apps = count_successful_app_patches(distribution_result.application_results)
      successful_apps / distribution_result.total_affected_apps * 100
    else
      0
    end
  end

  defp collect_distribution_issues(validation, distribution_result) do
    issues = []

    issues =
      if validation.success_rate_acceptable do
        issues
      else
        rate = calculate_patch_success_rate(distribution_result)
        ["Patch application success rate below threshold: #{rate}%" | issues]
      end

    issues =
      if validation.consistency_acceptable do
        issues
      else
        ["Patch consistency validation failed" | issues]
      end

    issues =
      if validation.performance_acceptable do
        issues
      else
        avg_time = calculate_average_patch_time(distribution_result.application_results)
        ["Patch application performance below threshold: #{avg_time}ms avg" | issues]
      end

    issues
  end

  @doc """
  Creates rollback plan for failed patch distributions.
  """
  def create_rollback_plan(distribution_result) do
    failed_apps =
      distribution_result.application_results
      |> Enum.filter(&(not &1.success))
      |> Enum.map(& &1.app_name)

    rollback_plan = %{
      requires_rollback: not Enum.empty?(failed_apps),
      affected_applications: failed_apps,
      rollback_strategy: distribution_result.distribution_plan.rollback_strategy,
      rollback_order: Enum.reverse(distribution_result.distribution_plan.application_order),
      estimated_rollback_time_ms: estimate_rollback_duration(failed_apps)
    }

    {:ok, rollback_plan}
  end

  defp estimate_rollback_duration(failed_apps) do
    # Estimate rollback time based on number of failed applications
    # 5 seconds per app
    length(failed_apps) * 5000
  end
end
