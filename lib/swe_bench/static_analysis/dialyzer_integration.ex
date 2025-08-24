defmodule SweBench.StaticAnalysis.DialyzerIntegration do
  @moduledoc """
  Integrates Dialyzer for comprehensive type checking and analysis.

  Manages PLT (Persistent Lookup Table) files, executes type analysis on
  patched code, categorizes type warnings, detects spec violations,
  and calculates type safety scores.
  """

  require Logger

  # 5 minutes for Dialyzer analysis
  @dialyzer_timeout 300_000
  # 10 minutes for PLT building
  @plt_build_timeout 600_000
  @default_plt_name "swe_bench_evaluation.plt"

  # @warning_severities %{
  #   "no_return" => :error,
  #   "no_match" => :error,
  #   "no_fail_call" => :error,
  #   "no_opaque" => :warning,
  #   "race_condition" => :warning,
  #   "no_unused" => :info,
  #   "unknown" => :info
  # }

  @doc """
  Performs comprehensive Dialyzer type analysis on source code.

  ## Parameters
    - source_path: Path to the source code directory to analyze
    - opts: Analysis options including PLT path and warning levels

  ## Returns
    - {:ok, analysis_result} - Successful analysis with categorized warnings
    - {:error, reason} - Analysis error
  """
  def analyze_type_safety(source_path, opts \\ []) do
    Logger.info("Starting Dialyzer type analysis for #{source_path}")

    with {:ok, plt_info} <- ensure_plt_available(source_path, opts),
         {:ok, dialyzer_output} <- execute_dialyzer_analysis(source_path, plt_info, opts),
         {:ok, parsed_warnings} <- parse_dialyzer_output(dialyzer_output),
         {:ok, categorized_warnings} <- categorize_type_warnings(parsed_warnings),
         {:ok, spec_violations} <- detect_spec_violations(parsed_warnings),
         {:ok, type_safety_score} <-
           calculate_type_safety_score(categorized_warnings, spec_violations) do
      analysis_result = %{
        source_path: source_path,
        plt_info: plt_info,
        raw_output: dialyzer_output,
        parsed_warnings: parsed_warnings,
        categorized_warnings: categorized_warnings,
        spec_violations: spec_violations,
        type_safety_score: type_safety_score,
        analyzed_at: DateTime.utc_now(),
        analysis_duration_ms: dialyzer_output.execution_time_ms
      }

      Logger.info(
        "Dialyzer analysis complete: score #{type_safety_score}, #{length(parsed_warnings)} warnings found"
      )

      {:ok, analysis_result}
    else
      {:error, reason} ->
        Logger.warning("Dialyzer analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.4.2.1: Build PLT (Persistent Lookup Table) files
  defp ensure_plt_available(source_path, opts) do
    plt_path = get_plt_path(source_path, opts)
    force_rebuild = Keyword.get(opts, :force_plt_rebuild, false)

    if File.exists?(plt_path) and not force_rebuild do
      {:ok, load_existing_plt_info(plt_path)}
    else
      build_plt_for_project(source_path, plt_path, opts)
    end
  end

  defp get_plt_path(source_path, opts) do
    case Keyword.get(opts, :plt_path) do
      nil ->
        plt_dir = Path.join(source_path, "_dialyzer_cache")
        File.mkdir_p!(plt_dir)
        Path.join(plt_dir, @default_plt_name)

      custom_path ->
        custom_path
    end
  end

  defp load_existing_plt_info(plt_path) do
    case File.stat(plt_path) do
      {:ok, stat} ->
        %{
          plt_path: plt_path,
          exists: true,
          size_bytes: stat.size,
          modified_at: stat.mtime,
          build_required: false
        }

      {:error, reason} ->
        {:error, {:plt_stat_failed, reason}}
    end
  end

  defp build_plt_for_project(source_path, plt_path, opts) do
    Logger.info("Building PLT for project at #{source_path}")

    timeout = Keyword.get(opts, :plt_timeout, @plt_build_timeout)

    # Get dependencies for PLT
    with {:ok, dependencies} <- extract_project_dependencies(source_path),
         {:ok, plt_apps} <- determine_plt_applications(dependencies, opts),
         {:ok, build_result} <- execute_plt_build(source_path, plt_path, plt_apps, timeout) do
      plt_info = %{
        plt_path: plt_path,
        exists: true,
        size_bytes: get_file_size(plt_path),
        modified_at: DateTime.utc_now(),
        build_required: false,
        applications: plt_apps,
        build_duration_ms: build_result.execution_time_ms
      }

      {:ok, plt_info}
    end
  end

  defp extract_project_dependencies(source_path) do
    mix_exs_path = Path.join(source_path, "mix.exs")

    case File.read(mix_exs_path) do
      {:ok, content} ->
        # Simple dependency extraction - would be more sophisticated in production
        dependencies = extract_deps_from_mix_content(content)
        {:ok, dependencies}

      {:error, reason} ->
        {:error, {:mix_exs_read_failed, reason}}
    end
  end

  defp extract_deps_from_mix_content(content) do
    # Extract dependency names from mix.exs content
    matches = Regex.scan(~r/{:(\w+),/, content)
    Enum.map(matches, fn [_, dep] -> String.to_atom(dep) end)
  end

  defp determine_plt_applications(dependencies, opts) do
    # Default OTP applications for PLT
    default_apps = [:erts, :kernel, :stdlib, :crypto, :public_key, :ssl]

    # Add common Elixir applications
    elixir_apps = [:elixir, :logger, :mix]

    # Add project dependencies (filter to common ones to avoid PLT bloat)
    common_deps = filter_common_dependencies(dependencies)

    plt_apps = default_apps ++ elixir_apps ++ common_deps

    # Allow override of PLT applications
    final_apps = Keyword.get(opts, :plt_apps, plt_apps) |> Enum.uniq()

    {:ok, final_apps}
  end

  defp filter_common_dependencies(dependencies) do
    # Include only well-known dependencies to avoid PLT build issues
    common_deps = [:jason, :plug, :ecto, :phoenix, :httpoison, :hackney, :cowboy]

    Enum.filter(dependencies, fn dep -> dep in common_deps end)
  end

  defp execute_plt_build(source_path, plt_path, plt_apps, timeout) do
    start_time = System.monotonic_time(:millisecond)

    # Remove existing PLT to ensure clean build
    File.rm(plt_path)

    plt_args = [
      "dialyzer",
      "--build_plt",
      "--output_plt",
      plt_path,
      "--apps" | Enum.map(plt_apps, &Atom.to_string/1)
    ]

    Logger.debug("Building PLT with apps: #{inspect(plt_apps)}")

    case System.cmd("mix", plt_args,
           cd: source_path,
           stderr_to_stdout: true,
           timeout: timeout
         ) do
      {output, 0} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        {:ok,
         %{
           output: output,
           exit_code: 0,
           execution_time_ms: duration,
           plt_path: plt_path
         }}

      {output, exit_code} ->
        {:error, {:plt_build_failed, exit_code, output}}
    end
  rescue
    error ->
      {:error, {:plt_build_exception, error}}
  end

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, stat} -> stat.size
      {:error, _} -> 0
    end
  end

  # Task 2.4.2.2: Run type analysis on patched code
  defp execute_dialyzer_analysis(source_path, plt_info, opts) do
    timeout = Keyword.get(opts, :timeout, @dialyzer_timeout)
    warning_flags = get_warning_flags(opts)

    dialyzer_args = build_dialyzer_arguments(source_path, plt_info, warning_flags)

    Logger.debug("Executing Dialyzer with args: #{inspect(dialyzer_args)}")

    start_time = System.monotonic_time(:millisecond)

    case System.cmd("mix", dialyzer_args,
           cd: source_path,
           stderr_to_stdout: true,
           timeout: timeout
         ) do
      {output, exit_code} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        # Dialyzer may exit with non-zero if warnings are found
        {:ok,
         %{
           output: output,
           exit_code: exit_code,
           execution_time_ms: duration,
           plt_used: plt_info.plt_path
         }}
    end
  rescue
    error ->
      {:error, {:dialyzer_execution_failed, error}}
  end

  defp get_warning_flags(opts) do
    Keyword.get(opts, :warning_flags, [
      :no_return,
      :no_unused,
      :no_improper_lists,
      :no_fun_app,
      :no_match,
      :no_opaque,
      :no_fail_call,
      :no_contracts,
      :no_behaviours,
      :no_undefined_callbacks,
      :unmatched_returns,
      :error_handling,
      :race_conditions
    ])
  end

  defp build_dialyzer_arguments(source_path, plt_info, warning_flags) do
    args = ["dialyzer"]

    # Add PLT path
    args = args ++ ["--plt", plt_info.plt_path]

    # Add warning flags
    args =
      args ++
        Enum.flat_map(warning_flags, fn flag ->
          ["-W#{flag}"]
        end)

    # Add source paths to analyze
    lib_path = Path.join(source_path, "lib")

    args =
      if File.dir?(lib_path) do
        args ++ [lib_path]
      else
        args ++ [source_path]
      end

    args
  end

  defp parse_dialyzer_output(dialyzer_output) do
    warnings = parse_dialyzer_warnings(dialyzer_output.output)

    parsed_result = %{
      warnings: warnings,
      total_warnings: length(warnings),
      execution_time_ms: dialyzer_output.execution_time_ms,
      exit_code: dialyzer_output.exit_code,
      plt_used: dialyzer_output.plt_used
    }

    {:ok, parsed_result}
  end

  defp parse_dialyzer_warnings(output) do
    # Parse Dialyzer warning format: "filename:line: Warning: message"
    output
    |> String.split("\n")
    |> Enum.filter(&dialyzer_warning_line?/1)
    |> Enum.map(&parse_single_warning/1)
    |> Enum.reject(&is_nil/1)
  end

  defp dialyzer_warning_line?(line) do
    String.contains?(line, ": Warning:") or
      String.contains?(line, ": Error:")
  end

  defp parse_single_warning(line) do
    case Regex.run(~r/^(.+):(\d+): (Warning|Error): (.+)$/, line) do
      [_, filename, line_no, severity, message] ->
        %{
          filename: filename,
          line_no: String.to_integer(line_no),
          severity: String.downcase(severity),
          message: String.trim(message),
          warning_type: classify_warning_type(message),
          raw_line: line
        }

      _ ->
        nil
    end
  end

  defp classify_warning_type(message) do
    cond do
      critical_warning?(message) -> classify_critical_warning(message)
      behavioral_warning?(message) -> classify_behavioral_warning(message)
      true -> :unknown
    end
  end

  defp critical_warning?(message) do
    String.contains?(message, "no_return") or
      String.contains?(message, "no_match") or
      String.contains?(message, "no_fail_call")
  end

  defp classify_critical_warning(message) do
    cond do
      String.contains?(message, "no_return") -> :no_return
      String.contains?(message, "no_match") -> :no_match
      String.contains?(message, "no_fail_call") -> :no_fail_call
    end
  end

  defp behavioral_warning?(message) do
    String.contains?(message, "contract") or
      String.contains?(message, "opaque") or
      String.contains?(message, "race") or
      String.contains?(message, "unused") or
      String.contains?(message, "callback")
  end

  defp classify_behavioral_warning(message) do
    cond do
      String.contains?(message, "contract") -> :contract_violation
      String.contains?(message, "opaque") -> :opaque_violation
      String.contains?(message, "race") -> :race_condition
      String.contains?(message, "unused") -> :unused_function
      String.contains?(message, "callback") -> :callback_issue
    end
  end

  # Task 2.4.2.3: Categorize type warnings
  defp categorize_type_warnings(parsed_warnings) do
    warnings_by_severity =
      parsed_warnings.warnings
      |> Enum.group_by(& &1.severity)

    warnings_by_type =
      parsed_warnings.warnings
      |> Enum.group_by(& &1.warning_type)

    categorized = %{
      by_severity: %{
        error: Map.get(warnings_by_severity, "error", []),
        warning: Map.get(warnings_by_severity, "warning", []),
        info: Map.get(warnings_by_severity, "info", [])
      },
      by_type: warnings_by_type,
      total_warnings: parsed_warnings.total_warnings,
      error_count: length(Map.get(warnings_by_severity, "error", [])),
      warning_count: length(Map.get(warnings_by_severity, "warning", [])),
      info_count: length(Map.get(warnings_by_severity, "info", []))
    }

    # Add statistical analysis
    stats = calculate_warning_statistics(categorized)
    final_categorization = Map.merge(categorized, stats)

    {:ok, final_categorization}
  end

  defp calculate_warning_statistics(categorized) do
    total = categorized.total_warnings

    %{
      most_common_type: find_most_common_warning_type(categorized.by_type),
      error_percentage: calculate_percentage(categorized.error_count, total),
      warning_percentage: calculate_percentage(categorized.warning_count, total),
      info_percentage: calculate_percentage(categorized.info_count, total),
      critical_warnings: categorized.error_count + categorized.warning_count
    }
  end

  defp find_most_common_warning_type(warnings_by_type) do
    case Enum.max_by(warnings_by_type, fn {_type, warnings} -> length(warnings) end, fn ->
           {nil, []}
         end) do
      {type, [_ | _]} -> type
      _ -> :none
    end
  end

  defp calculate_percentage(count, total) when total > 0, do: count / total * 100
  defp calculate_percentage(_count, 0), do: 0

  # Task 2.4.2.4: Detect spec violations
  defp detect_spec_violations(parsed_warnings) do
    spec_related_warnings =
      parsed_warnings.warnings
      |> Enum.filter(&spec_violation_warning?/1)

    violations = %{
      spec_violations: spec_related_warnings,
      violation_count: length(spec_related_warnings),
      contract_violations: filter_contract_violations(spec_related_warnings),
      callback_violations: filter_callback_violations(spec_related_warnings),
      return_type_violations: filter_return_type_violations(spec_related_warnings)
    }

    {:ok, violations}
  end

  defp spec_violation_warning?(warning) do
    warning.warning_type in [:contract_violation, :callback_issue] or
      String.contains?(warning.message, "spec") or
      String.contains?(warning.message, "contract") or
      String.contains?(warning.message, "callback")
  end

  defp filter_contract_violations(warnings) do
    Enum.filter(warnings, fn warning ->
      warning.warning_type == :contract_violation or
        String.contains?(warning.message, "contract")
    end)
  end

  defp filter_callback_violations(warnings) do
    Enum.filter(warnings, fn warning ->
      warning.warning_type == :callback_issue or
        String.contains?(warning.message, "callback")
    end)
  end

  defp filter_return_type_violations(warnings) do
    Enum.filter(warnings, fn warning ->
      String.contains?(warning.message, "return") and
        String.contains?(warning.message, "type")
    end)
  end

  # Task 2.4.2.5: Calculate type safety score
  defp calculate_type_safety_score(categorized_warnings, spec_violations) do
    base_score = 100

    # Penalize based on warning severity
    error_penalty = categorized_warnings.error_count * 15
    warning_penalty = categorized_warnings.warning_count * 8
    info_penalty = categorized_warnings.info_count * 3

    # Additional penalty for spec violations
    spec_penalty = spec_violations.violation_count * 10

    total_penalty = error_penalty + warning_penalty + info_penalty + spec_penalty

    type_safety_score = max(0, base_score - total_penalty)

    {:ok, round(type_safety_score)}
  end

  @doc """
  Manages PLT cache lifecycle and optimization.
  """
  def manage_plt_cache(source_path, action, opts \\ []) do
    plt_path = get_plt_path(source_path, opts)

    case action do
      :clean ->
        clean_plt_cache(plt_path)

      :info ->
        get_plt_cache_info(plt_path)

      :rebuild ->
        force_plt_rebuild(source_path, plt_path, opts)

      :validate ->
        validate_plt_integrity(plt_path)

      _ ->
        {:error, {:unknown_action, action}}
    end
  end

  defp clean_plt_cache(plt_path) do
    case File.rm(plt_path) do
      :ok -> {:ok, :cleaned}
      {:error, :enoent} -> {:ok, :already_clean}
      {:error, reason} -> {:error, {:cleanup_failed, reason}}
    end
  end

  defp get_plt_cache_info(plt_path) do
    if File.exists?(plt_path) do
      case File.stat(plt_path) do
        {:ok, stat} ->
          {:ok,
           %{
             exists: true,
             size_mb: stat.size / (1024 * 1024),
             modified_at: stat.mtime,
             age_hours: calculate_age_hours(stat.mtime)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, %{exists: false}}
    end
  end

  defp calculate_age_hours(mtime) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    mtime_unix = mtime |> DateTime.from_unix!() |> DateTime.to_unix()
    (now - mtime_unix) / 3600
  end

  defp force_plt_rebuild(source_path, plt_path, opts) do
    File.rm(plt_path)
    build_plt_for_project(source_path, plt_path, opts)
  end

  defp validate_plt_integrity(plt_path) do
    if File.exists?(plt_path) do
      # Basic integrity check - file exists and has reasonable size
      case File.stat(plt_path) do
        # At least 1MB
        {:ok, stat} when stat.size > 1_000_000 ->
          {:ok, :valid}

        {:ok, _stat} ->
          {:error, :plt_too_small}

        {:error, reason} ->
          {:error, {:plt_stat_failed, reason}}
      end
    else
      {:error, :plt_not_found}
    end
  end

  @doc """
  Generates comprehensive Dialyzer analysis report.
  """
  def generate_dialyzer_report(analysis_result) do
    report = %{
      summary: %{
        type_safety_score: analysis_result.type_safety_score,
        total_warnings: analysis_result.categorized_warnings.total_warnings,
        critical_warnings: analysis_result.categorized_warnings.critical_warnings,
        spec_violations: analysis_result.spec_violations.violation_count,
        analysis_duration_ms: analysis_result.analysis_duration_ms
      },
      warning_breakdown: %{
        by_severity: analysis_result.categorized_warnings.by_severity,
        by_type: analysis_result.categorized_warnings.by_type,
        statistics: %{
          most_common_type: analysis_result.categorized_warnings.most_common_type,
          error_percentage: analysis_result.categorized_warnings.error_percentage,
          warning_percentage: analysis_result.categorized_warnings.warning_percentage
        }
      },
      spec_analysis: analysis_result.spec_violations,
      plt_info: analysis_result.plt_info,
      recommendations: generate_dialyzer_recommendations(analysis_result),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_dialyzer_recommendations(analysis_result) do
    recommendations = []
    warnings = analysis_result.categorized_warnings
    violations = analysis_result.spec_violations

    recommendations =
      if warnings.error_count > 0 do
        ["Fix #{warnings.error_count} critical type errors" | recommendations]
      else
        recommendations
      end

    recommendations =
      if warnings.warning_count > 5 do
        [
          "Address #{warnings.warning_count} type warnings for better type safety"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if violations.violation_count > 0 do
        ["Review #{violations.violation_count} spec violations" | recommendations]
      else
        recommendations
      end

    recommendations =
      if analysis_result.type_safety_score < 70 do
        [
          "Improve overall type safety - current score: #{analysis_result.type_safety_score}"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Type analysis shows good type safety practices"]
    else
      recommendations
    end
  end

  @doc """
  Validates Dialyzer analysis results against quality thresholds.
  """
  def validate_dialyzer_results(analysis_result, thresholds \\ default_dialyzer_thresholds()) do
    validation = %{
      score_acceptable: analysis_result.type_safety_score >= thresholds.minimum_type_safety_score,
      no_critical_errors:
        analysis_result.categorized_warnings.error_count <= thresholds.max_error_count,
      warnings_acceptable:
        analysis_result.categorized_warnings.warning_count <= thresholds.max_warning_count,
      spec_violations_acceptable:
        analysis_result.spec_violations.violation_count <= thresholds.max_spec_violations
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_dialyzer_validation_issues(validation, analysis_result)
    }
  end

  defp default_dialyzer_thresholds do
    %{
      minimum_type_safety_score: 75,
      max_error_count: 0,
      max_warning_count: 10,
      max_spec_violations: 3
    }
  end

  defp collect_dialyzer_validation_issues(validation, analysis_result) do
    issues = []

    issues =
      if validation.score_acceptable do
        issues
      else
        ["Type safety score below threshold: #{analysis_result.type_safety_score}" | issues]
      end

    issues =
      if validation.no_critical_errors do
        issues
      else
        [
          "Critical type errors present: #{analysis_result.categorized_warnings.error_count}"
          | issues
        ]
      end

    issues =
      if validation.warnings_acceptable do
        issues
      else
        ["Too many type warnings: #{analysis_result.categorized_warnings.warning_count}" | issues]
      end

    issues =
      if validation.spec_violations_acceptable do
        issues
      else
        ["Spec violations detected: #{analysis_result.spec_violations.violation_count}" | issues]
      end

    issues
  end

  @doc """
  Checks if Dialyzer is available and properly configured.
  """
  def dialyzer_available?(source_path) do
    case System.cmd("mix", ["help", "dialyzer"], cd: source_path, stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
