defmodule SweBench.TestRunner.Analyzer do
  @moduledoc """
  Test result analyzer for detecting transitions and generating evaluation metrics.

  This module provides sophisticated analysis of test execution results including:
  - FAIL_TO_PASS transition detection for evaluation scoring
  - PASS_TO_PASS stability verification
  - Test flakiness detection and filtering
  - Coverage metrics calculation
  - Structured JSON report generation
  """

  require Logger

  @doc """
  Analyzes execution results and enriches them with evaluation metrics.
  """
  def analyze_execution_results(raw_results, opts \\ []) do
    Logger.debug("Analyzing execution results")

    include_coverage = Keyword.get(opts, :include_coverage, true)
    include_timing = Keyword.get(opts, :include_timing, true)
    _include_transitions = Keyword.get(opts, :include_transitions, false)

    analysis = %{
      basic_metrics: calculate_basic_metrics(raw_results),
      failure_analysis: analyze_failures(raw_results),
      timing_analysis: if(include_timing, do: analyze_timing(raw_results), else: %{}),
      coverage_analysis: if(include_coverage, do: analyze_coverage(raw_results), else: %{}),
      quality_metrics: calculate_quality_metrics(raw_results)
    }

    enriched_results =
      raw_results
      |> Map.put(:analysis, analysis)
      |> Map.put(:analyzed_at, DateTime.utc_now())

    {:ok, enriched_results}
  end

  @doc """
  Detects test transitions between base and patched code execution.

  This is the core function for SWE-bench evaluation scoring.
  """
  def detect_transitions(base_results, patched_results) do
    Logger.info("Detecting test transitions between base and patched results")

    base_tests = extract_test_map(base_results)
    patched_tests = extract_test_map(patched_results)

    transitions = %{
      fail_to_pass: detect_fail_to_pass(base_tests, patched_tests),
      pass_to_pass: detect_pass_to_pass(base_tests, patched_tests),
      pass_to_fail: detect_pass_to_fail(base_tests, patched_tests),
      new_tests: detect_new_tests(base_tests, patched_tests),
      removed_tests: detect_removed_tests(base_tests, patched_tests),
      flaky_tests: detect_flaky_tests(base_tests, patched_tests)
    }

    {:ok, transitions}
  end

  @doc """
  Detects test flakiness by analyzing multiple execution results.
  """
  def detect_flakiness(execution_results_list) when is_list(execution_results_list) do
    Logger.debug("Analyzing #{length(execution_results_list)} executions for flakiness")

    if length(execution_results_list) < 2 do
      {:ok, %{flaky_tests: [], stable_tests: []}}
    else
      test_outcomes =
        execution_results_list
        |> Enum.map(&extract_test_map/1)
        |> analyze_test_consistency()

      {:ok, test_outcomes}
    end
  end

  @doc """
  Calculates test coverage metrics from execution results.
  """
  def calculate_coverage_metrics(results, base_results \\ nil) do
    Logger.debug("Calculating coverage metrics")

    coverage_data = Map.get(results, :coverage, %{})

    metrics = %{
      line_coverage: calculate_line_coverage(coverage_data),
      function_coverage: calculate_function_coverage(coverage_data),
      module_coverage: calculate_module_coverage(coverage_data),
      coverage_delta:
        if(base_results, do: calculate_coverage_delta(coverage_data, base_results), else: nil)
    }

    {:ok, metrics}
  end

  @doc """
  Generates structured JSON report for test execution results.
  """
  def generate_json_report(results, opts \\ []) do
    Logger.debug("Generating JSON report")

    include_raw_data = Keyword.get(opts, :include_raw_data, false)
    format_version = Keyword.get(opts, :format_version, "1.0")

    report = %{
      format_version: format_version,
      generated_at: DateTime.utc_now(),
      execution_summary: extract_execution_summary(results),
      test_results: extract_test_summary(results),
      analysis: Map.get(results, :analysis, %{}),
      raw_data: if(include_raw_data, do: results, else: nil)
    }

    case Jason.encode(report, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encoding_failed, reason}}
    end
  end

  # Private Functions

  defp calculate_basic_metrics(results) do
    stats = Map.get(results, :stats, %{})

    %{
      total_tests: Map.get(stats, :total, 0),
      passed_tests: Map.get(stats, :passed, 0),
      failed_tests: Map.get(stats, :failed, 0),
      skipped_tests: Map.get(stats, :skipped, 0),
      success_rate: calculate_success_rate(stats),
      failure_rate: calculate_failure_rate(stats)
    }
  end

  defp analyze_failures(results) do
    failures = Map.get(results, :failures, [])

    %{
      total_failures: length(failures),
      assertion_failures: count_assertion_failures(failures),
      exception_failures: count_exception_failures(failures),
      timeout_failures: count_timeout_failures(failures),
      failure_categories: categorize_failures(failures),
      common_failure_patterns: identify_failure_patterns(failures)
    }
  end

  defp analyze_timing(results) do
    timing = Map.get(results, :timing, %{})
    tests = Map.get(results, :tests, [])

    test_times = extract_test_execution_times(tests)

    %{
      total_execution_time: Map.get(timing, :total_time_us, 0),
      load_time: Map.get(timing, :load_time_us, 0),
      average_test_time: calculate_average(test_times),
      median_test_time: calculate_median(test_times),
      slowest_tests: find_slowest_tests(tests, 5),
      fastest_tests: find_fastest_tests(tests, 5)
    }
  end

  defp analyze_coverage(results) do
    coverage = Map.get(results, :coverage, %{})

    %{
      overall_coverage: Map.get(coverage, :coverage, 0.0),
      lines_covered: Map.get(coverage, :lines_covered, 0),
      lines_total: Map.get(coverage, :lines_total, 0),
      functions_covered: Map.get(coverage, :functions_covered, 0),
      functions_total: Map.get(coverage, :functions_total, 0),
      modules_covered: Map.get(coverage, :modules_covered, 0),
      modules_total: Map.get(coverage, :modules_total, 0)
    }
  end

  defp calculate_quality_metrics(results) do
    failures = Map.get(results, :failures, [])
    stats = Map.get(results, :stats, %{})

    %{
      test_quality_score: calculate_test_quality_score(stats, failures),
      assertion_diversity: calculate_assertion_diversity(failures),
      error_pattern_score: calculate_error_pattern_score(failures),
      stability_score: calculate_stability_score(results)
    }
  end

  defp extract_test_map(results) do
    tests = Map.get(results, :tests, [])

    tests
    |> Enum.flat_map(fn module_info ->
      module_tests = Map.get(module_info, :tests, [])

      Enum.map(module_tests, fn test ->
        test_id = "#{module_info.module}.#{test.name}"
        {test_id, test.state}
      end)
    end)
    |> Map.new()
  end

  defp detect_fail_to_pass(base_tests, patched_tests) do
    base_tests
    |> Enum.filter(fn {test_id, state} ->
      state == :failed and Map.get(patched_tests, test_id) == :passed
    end)
    |> Enum.map(fn {test_id, _} -> test_id end)
  end

  defp detect_pass_to_pass(base_tests, patched_tests) do
    base_tests
    |> Enum.filter(fn {test_id, state} ->
      state == :passed and Map.get(patched_tests, test_id) == :passed
    end)
    |> Enum.map(fn {test_id, _} -> test_id end)
  end

  defp detect_pass_to_fail(base_tests, patched_tests) do
    base_tests
    |> Enum.filter(fn {test_id, state} ->
      state == :passed and Map.get(patched_tests, test_id) == :failed
    end)
    |> Enum.map(fn {test_id, _} -> test_id end)
  end

  defp detect_new_tests(base_tests, patched_tests) do
    patched_test_ids = Map.keys(patched_tests)
    base_test_ids = Map.keys(base_tests)

    patched_test_ids -- base_test_ids
  end

  defp detect_removed_tests(base_tests, patched_tests) do
    base_test_ids = Map.keys(base_tests)
    patched_test_ids = Map.keys(patched_tests)

    base_test_ids -- patched_test_ids
  end

  defp detect_flaky_tests(base_tests, patched_tests) do
    # Simple flakiness detection - in production would be more sophisticated
    base_test_ids = Map.keys(base_tests)
    patched_test_ids = Map.keys(patched_tests)

    common_tests = base_test_ids -- (base_test_ids -- patched_test_ids)

    Enum.filter(common_tests, fn test_id ->
      base_state = Map.get(base_tests, test_id)
      patched_state = Map.get(patched_tests, test_id)

      # Consider flaky if state changed but not a clear fix
      base_state != patched_state and
        not (base_state == :failed and patched_state == :passed)
    end)
  end

  defp analyze_test_consistency(test_maps) do
    all_test_ids =
      test_maps
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    {flaky, stable} =
      Enum.split_with(all_test_ids, fn test_id ->
        states = Enum.map(test_maps, fn test_map -> Map.get(test_map, test_id, :missing) end)
        states |> Enum.uniq() |> length() > 1
      end)

    %{
      flaky_tests: flaky,
      stable_tests: stable,
      consistency_rate: length(stable) / length(all_test_ids) * 100
    }
  end

  defp calculate_success_rate(stats) do
    total = Map.get(stats, :total, 0)
    passed = Map.get(stats, :passed, 0)

    if total > 0, do: passed / total * 100, else: 0.0
  end

  defp calculate_failure_rate(stats) do
    total = Map.get(stats, :total, 0)
    failed = Map.get(stats, :failed, 0)

    if total > 0, do: failed / total * 100, else: 0.0
  end

  defp count_assertion_failures(failures) do
    Enum.count(failures, fn failure ->
      Map.get(failure, :assertion_type, :non_assertion_failure) != :non_assertion_failure
    end)
  end

  defp count_exception_failures(failures) do
    Enum.count(failures, fn failure ->
      Map.get(failure, :assertion_type, :non_assertion_failure) == :non_assertion_failure
    end)
  end

  defp count_timeout_failures(failures) do
    Enum.count(failures, fn failure ->
      failure_message = Map.get(failure, :failure_message, "")

      String.contains?(failure_message, "timeout") or
        String.contains?(failure_message, "timed out")
    end)
  end

  defp categorize_failures(failures) do
    failures
    |> Enum.group_by(fn failure ->
      Map.get(failure, :assertion_type, :unknown)
    end)
    |> Enum.map(fn {category, category_failures} ->
      {category, length(category_failures)}
    end)
    |> Map.new()
  end

  defp identify_failure_patterns(failures) do
    # Identify common patterns in failure messages
    patterns =
      failures
      |> Enum.map(fn failure -> Map.get(failure, :failure_message, "") end)
      |> Enum.filter(fn message -> String.length(message) > 0 end)
      |> Enum.frequencies_by(fn message ->
        # Extract key phrases from failure messages
        message
        |> String.split()
        |> Enum.take(3)
        |> Enum.join(" ")
      end)
      |> Enum.filter(fn {_pattern, count} -> count > 1 end)
      |> Enum.sort_by(fn {_pattern, count} -> count end, :desc)
      |> Enum.take(10)

    patterns
  end

  defp extract_test_execution_times(tests) do
    tests
    |> Enum.flat_map(fn module_info ->
      Map.get(module_info, :tests, [])
    end)
    |> Enum.map(fn test -> Map.get(test, :execution_time_us, 0) end)
    |> Enum.filter(fn time -> time > 0 end)
  end

  defp calculate_average([]), do: 0.0

  defp calculate_average(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_median([]), do: 0.0

  defp calculate_median(values) do
    sorted = Enum.sort(values)
    length = length(sorted)

    if rem(length, 2) == 0 do
      # Even number of elements
      mid1 = Enum.at(sorted, div(length, 2) - 1)
      mid2 = Enum.at(sorted, div(length, 2))
      (mid1 + mid2) / 2
    else
      # Odd number of elements
      Enum.at(sorted, div(length, 2))
    end
  end

  defp find_slowest_tests(tests, count) do
    tests
    |> Enum.flat_map(fn module_info ->
      module_tests = Map.get(module_info, :tests, [])

      Enum.map(module_tests, fn test ->
        %{
          test_id: "#{module_info.module}.#{test.name}",
          execution_time_us: Map.get(test, :execution_time_us, 0),
          module: module_info.module,
          name: test.name
        }
      end)
    end)
    |> Enum.filter(fn test -> test.execution_time_us > 0 end)
    |> Enum.sort_by(fn test -> test.execution_time_us end, :desc)
    |> Enum.take(count)
  end

  defp find_fastest_tests(tests, count) do
    tests
    |> Enum.flat_map(fn module_info ->
      module_tests = Map.get(module_info, :tests, [])

      Enum.map(module_tests, fn test ->
        %{
          test_id: "#{module_info.module}.#{test.name}",
          execution_time_us: Map.get(test, :execution_time_us, 0),
          module: module_info.module,
          name: test.name
        }
      end)
    end)
    |> Enum.filter(fn test -> test.execution_time_us > 0 end)
    |> Enum.sort_by(fn test -> test.execution_time_us end, :asc)
    |> Enum.take(count)
  end

  defp calculate_line_coverage(coverage_data) do
    covered = Map.get(coverage_data, :lines_covered, 0)
    total = Map.get(coverage_data, :lines_total, 0)

    if total > 0, do: covered / total * 100, else: 0.0
  end

  defp calculate_function_coverage(coverage_data) do
    covered = Map.get(coverage_data, :functions_covered, 0)
    total = Map.get(coverage_data, :functions_total, 0)

    if total > 0, do: covered / total * 100, else: 0.0
  end

  defp calculate_module_coverage(coverage_data) do
    covered = Map.get(coverage_data, :modules_covered, 0)
    total = Map.get(coverage_data, :modules_total, 0)

    if total > 0, do: covered / total * 100, else: 0.0
  end

  defp calculate_coverage_delta(current_coverage, base_results) do
    base_coverage = Map.get(base_results, :coverage, %{})

    %{
      line_coverage_delta:
        calculate_line_coverage(current_coverage) - calculate_line_coverage(base_coverage),
      function_coverage_delta:
        calculate_function_coverage(current_coverage) - calculate_function_coverage(base_coverage),
      module_coverage_delta:
        calculate_module_coverage(current_coverage) - calculate_module_coverage(base_coverage)
    }
  end

  defp calculate_test_quality_score(stats, failures) do
    total = Map.get(stats, :total, 0)
    passed = Map.get(stats, :passed, 0)

    if total == 0 do
      0.0
    else
      base_score = passed / total * 100

      # Adjust score based on failure types
      assertion_failures = count_assertion_failures(failures)
      exception_failures = count_exception_failures(failures)

      # Penalize exception failures more than assertion failures
      penalty = assertion_failures * 2 + exception_failures * 5

      max(0.0, base_score - penalty)
    end
  end

  defp calculate_assertion_diversity(failures) do
    assertion_types =
      failures
      |> Enum.map(fn failure -> Map.get(failure, :assertion_type, :unknown) end)
      |> Enum.frequencies()

    total_assertions = Map.values(assertion_types) |> Enum.sum()

    if total_assertions > 0 do
      # Calculate Shannon diversity index for assertion types
      assertion_types
      |> Enum.map(&calculate_diversity_score(&1, total_assertions))
      |> Enum.sum()
    else
      0.0
    end
  end

  defp calculate_error_pattern_score(failures) do
    patterns = identify_failure_patterns(failures)

    # Score based on pattern diversity (more diverse patterns = better tests)
    pattern_count = length(patterns)
    total_failures = length(failures)

    if total_failures > 0 do
      # Higher score for more diverse error patterns
      min(100.0, pattern_count / total_failures * 100)
    else
      # No failures is perfect score
      100.0
    end
  end

  defp calculate_stability_score(results) do
    # Score based on deterministic behavior indicators
    stats = Map.get(results, :stats, %{})
    timing = Map.get(results, :timing, %{})

    base_score = 100.0

    # Penalize for timeouts or very long execution
    total_time = Map.get(timing, :total_time_us, 0)
    # 60 seconds
    time_penalty = if total_time > 60_000_000, do: 20, else: 0

    # Penalize for skipped tests (might indicate flakiness)
    skipped = Map.get(stats, :skipped, 0)
    total = Map.get(stats, :total, 1)
    skip_penalty = skipped / total * 30

    max(0.0, base_score - time_penalty - skip_penalty)
  end

  defp extract_execution_summary(results) do
    %{
      execution_id: Map.get(results, :execution_id),
      timestamp: Map.get(results, :timestamp),
      execution_time_us: Map.get(results, :execution_time_us, 0),
      exit_code: Map.get(results, :exit_code, 0),
      success: Map.get(results, :exit_code, 1) == 0
    }
  end

  defp extract_test_summary(results) do
    stats = Map.get(results, :stats, %{})
    summary = Map.get(results, :summary, %{})

    Map.merge(stats, summary)
  end

  defp calculate_diversity_score({_type, count}, total_assertions) do
    proportion = count / total_assertions
    if proportion > 0, do: -proportion * :math.log2(proportion), else: 0
  end
end
