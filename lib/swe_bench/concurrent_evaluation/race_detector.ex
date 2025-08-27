defmodule SweBench.ConcurrentEvaluation.RaceDetector do
  @moduledoc """
  Race condition analysis using timing patterns and shared state monitoring.

  Detects timing-dependent behaviors, message ordering dependencies,
  ETS concurrent access patterns, and atomicity violations.
  """

  use GenServer
  require Logger

  alias SweBench.ConcurrentEvaluation.DecisionEngine

  defstruct [
    :config,
    :monitoring_tier,
    :access_patterns,
    :timing_samples,
    :race_statistics
  ]

  @doc """
  Starts the race detector with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Detects race conditions in the given solution.
  """
  def detect_race_conditions(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:detect_race_conditions, solution_data, monitoring_tier}, 60_000)
  end

  @doc """
  Returns current race detection statistics.
  """
  def get_race_statistics do
    GenServer.call(__MODULE__, :get_race_statistics)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      monitoring_tier: :standard,
      access_patterns: %{},
      timing_samples: [],
      race_statistics: initialize_race_statistics()
    }

    Logger.info("RaceDetector initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:detect_race_conditions, solution_data, monitoring_tier}, _from, state) do
    monitoring_config = DecisionEngine.get_monitoring_config(monitoring_tier)

    race_analysis = perform_race_detection(solution_data, monitoring_config, state)

    {:reply, {:ok, race_analysis}, state}
  rescue
    error ->
      Logger.error("Race detection failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  @impl true
  def handle_call(:get_race_statistics, _from, state) do
    {:reply, state.race_statistics, state}
  end

  # Private functions

  defp perform_race_detection(solution_data, monitoring_config, _state) do
    race_detection_mode = Map.get(monitoring_config, :race_detection, :pattern_based)

    case race_detection_mode do
      :statistical ->
        perform_statistical_race_detection(solution_data, monitoring_config)

      :pattern_based ->
        perform_pattern_race_detection(solution_data, monitoring_config)

      :comprehensive ->
        perform_comprehensive_race_detection(solution_data, monitoring_config)

      _ ->
        perform_basic_race_detection(solution_data)
    end
  end

  defp perform_basic_race_detection(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    basic_patterns = analyze_basic_race_patterns(solution_code)

    %{
      detection_mode: :basic,
      race_conditions_detected: basic_patterns.potential_races,
      shared_state_access: basic_patterns.shared_state_patterns,
      timing_dependencies: basic_patterns.timing_patterns,
      atomicity_violations: basic_patterns.atomicity_issues,
      confidence_level: :low,
      issues_detected: basic_patterns.issue_count,
      score: calculate_basic_race_score(basic_patterns)
    }
  end

  defp perform_statistical_race_detection(solution_data, monitoring_config) do
    solution_code = Map.get(solution_data, :solution_code, "")
    sampling_rate = Map.get(monitoring_config, :process_sampling_rate, 0.1)

    # Run multiple executions with statistical sampling
    sample_count = max(5, trunc(1.0 / sampling_rate))

    samples =
      1..sample_count
      |> Enum.map(fn _i ->
        execute_with_race_monitoring(solution_code, :statistical)
      end)
      |> Enum.filter(fn {status, _} -> status == :ok end)
      |> Enum.map(fn {_, result} -> result end)

    statistical_analysis = analyze_execution_variance(samples)

    %{
      detection_mode: :statistical,
      sample_count: sample_count,
      race_conditions_detected: statistical_analysis.race_indicators,
      execution_variance: statistical_analysis.timing_variance,
      confidence_level: statistical_analysis.confidence_level,
      issues_detected: statistical_analysis.issue_count,
      score: calculate_statistical_race_score(statistical_analysis)
    }
  end

  defp perform_pattern_race_detection(solution_data, _monitoring_config) do
    solution_code = Map.get(solution_data, :solution_code, "")

    # Analyze code patterns for race condition indicators
    pattern_analysis = %{
      ets_patterns: analyze_ets_race_patterns(solution_code),
      genserver_patterns: analyze_genserver_race_patterns(solution_code),
      message_patterns: analyze_message_race_patterns(solution_code),
      shared_state_patterns: analyze_shared_state_patterns(solution_code)
    }

    # Execute with pattern-specific monitoring
    execution_result = execute_with_race_monitoring(solution_code, :pattern_based)

    combined_analysis = combine_pattern_and_runtime_analysis(pattern_analysis, execution_result)

    %{
      detection_mode: :pattern_based,
      pattern_analysis: pattern_analysis,
      execution_analysis: execution_result,
      race_conditions_detected: combined_analysis.race_count,
      confidence_level: :medium,
      issues_detected: combined_analysis.issue_count,
      score: calculate_pattern_race_score(combined_analysis)
    }
  end

  defp perform_comprehensive_race_detection(solution_data, monitoring_config) do
    # Combine all detection methods for maximum accuracy
    basic_result = perform_basic_race_detection(solution_data)
    statistical_result = perform_statistical_race_detection(solution_data, monitoring_config)
    pattern_result = perform_pattern_race_detection(solution_data, monitoring_config)

    comprehensive_analysis =
      combine_all_analyses([
        basic_result,
        statistical_result,
        pattern_result
      ])

    %{
      detection_mode: :comprehensive,
      basic_analysis: basic_result,
      statistical_analysis: statistical_result,
      pattern_analysis: pattern_result,
      combined_analysis: comprehensive_analysis,
      confidence_level: :high,
      race_conditions_detected: comprehensive_analysis.total_races,
      issues_detected: comprehensive_analysis.total_issues,
      score: calculate_comprehensive_race_score(comprehensive_analysis)
    }
  end

  defp analyze_basic_race_patterns(code) do
    patterns = %{
      ets_without_locks:
        count_pattern(code, ":ets.insert") > 0 and count_pattern(code, ":ets.lookup") > 0,
      shared_agent_access:
        String.contains?(code, "Agent.get") and String.contains?(code, "Agent.update"),
      concurrent_map_access:
        String.contains?(code, "Map.put") and String.contains?(code, "spawn"),
      genserver_cast_race:
        String.contains?(code, "GenServer.cast") and String.contains?(code, "GenServer.call")
    }

    potential_races = Enum.count(patterns, fn {_, detected} -> detected end)

    %{
      shared_state_patterns: patterns,
      potential_races: potential_races,
      timing_patterns: analyze_timing_dependencies(code),
      atomicity_issues: analyze_atomicity_violations(code),
      issue_count: potential_races
    }
  end

  defp count_pattern(code, pattern) do
    code
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  defp analyze_timing_dependencies(code) do
    %{
      has_sleep_statements:
        String.contains?(code, "Process.sleep") or String.contains?(code, ":timer.sleep"),
      has_receive_timeouts: String.contains?(code, "after "),
      has_genserver_timeouts: String.contains?(code, "timeout:"),
      timing_complexity: estimate_timing_complexity(code)
    }
  end

  defp estimate_timing_complexity(code) do
    timing_constructs = [
      String.contains?(code, "after "),
      String.contains?(code, "timeout"),
      String.contains?(code, "Process.sleep"),
      String.contains?(code, "Task.await")
    ]

    case Enum.count(timing_constructs, & &1) do
      0 -> :none
      1 -> :low
      2 -> :medium
      _ -> :high
    end
  end

  defp analyze_atomicity_violations(code) do
    %{
      read_modify_write: analyze_rmw_patterns(code),
      check_then_act: analyze_check_act_patterns(code),
      compound_operations: analyze_compound_operations(code)
    }
  end

  defp analyze_rmw_patterns(code) do
    # Look for read-modify-write patterns that could be non-atomic
    String.contains?(code, "Agent.get") and
      String.contains?(code, "Agent.update") and
      not String.contains?(code, "Agent.get_and_update")
  end

  defp analyze_check_act_patterns(code) do
    # Look for check-then-act patterns
    String.contains?(code, "if ") and String.contains?(code, "GenServer.")
  end

  defp analyze_compound_operations(code) do
    # Look for compound operations that should be atomic
    ets_compound = String.contains?(code, ":ets.lookup") and String.contains?(code, ":ets.insert")
    map_compound = String.contains?(code, "Map.get") and String.contains?(code, "Map.put")

    ets_compound or map_compound
  end

  defp execute_with_race_monitoring(_code, _mode) do
    # Mock execution with race monitoring
    # This would integrate with actual test execution
    {:ok,
     %{
       execution_time: :rand.uniform(1000),
       race_events_detected: :rand.uniform(3),
       timing_variance: :rand.uniform() * 0.1
     }}
  end

  defp analyze_execution_variance(samples) when samples == [] do
    %{
      race_indicators: 0,
      timing_variance: 0.0,
      confidence_level: :none,
      issue_count: 0
    }
  end

  defp analyze_execution_variance(samples) do
    execution_times =
      Enum.map(samples, fn sample ->
        Map.get(sample, :execution_time, 0)
      end)

    variance = calculate_variance(execution_times)
    mean_time = Enum.sum(execution_times) / length(execution_times)

    # High variance might indicate race conditions
    coefficient_of_variation = if mean_time > 0, do: :math.sqrt(variance) / mean_time, else: 0.0

    %{
      race_indicators: if(coefficient_of_variation > 0.3, do: 1, else: 0),
      timing_variance: variance,
      coefficient_of_variation: coefficient_of_variation,
      confidence_level: determine_confidence_level(length(samples), coefficient_of_variation),
      issue_count: if(coefficient_of_variation > 0.5, do: 1, else: 0)
    }
  end

  defp calculate_variance(values) when length(values) < 2, do: 0.0

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)

    variance_sum =
      values
      |> Enum.reduce(0, fn value, acc -> acc + :math.pow(value - mean, 2) end)

    variance_sum / (length(values) - 1)
  end

  defp determine_confidence_level(sample_count, variance)
       when sample_count >= 10 and variance < 0.2,
       do: :high

  defp determine_confidence_level(sample_count, variance)
       when sample_count >= 5 and variance < 0.4,
       do: :medium

  defp determine_confidence_level(_, _), do: :low

  defp analyze_ets_race_patterns(code) do
    %{
      concurrent_inserts: count_pattern(code, ":ets.insert") > 1,
      read_write_cycles:
        count_pattern(code, ":ets.lookup") > 0 and count_pattern(code, ":ets.insert") > 0,
      missing_concurrency_type:
        String.contains?(code, ":ets.new") and not String.contains?(code, "read_concurrency")
    }
  end

  defp analyze_genserver_race_patterns(code) do
    %{
      cast_call_mixing:
        String.contains?(code, "GenServer.cast") and String.contains?(code, "GenServer.call"),
      state_dependencies: analyze_state_dependency_patterns(code),
      concurrent_state_updates: count_pattern(code, "handle_cast") > 1
    }
  end

  defp analyze_state_dependency_patterns(code) do
    # Look for patterns where state depends on external factors
    String.contains?(code, "get_state") or String.contains?(code, "put_state")
  end

  defp analyze_message_race_patterns(code) do
    %{
      selective_receive: String.contains?(code, "receive do") and String.contains?(code, "->"),
      message_ordering: analyze_message_ordering_dependencies(code),
      unordered_processing: has_unordered_message_processing?(code)
    }
  end

  defp analyze_message_ordering_dependencies(code) do
    # Check for patterns that depend on message order
    String.contains?(code, "receive") and
      (String.contains?(code, "after ") or String.contains?(code, "timeout"))
  end

  defp has_unordered_message_processing?(code) do
    String.contains?(code, "Task.async") and String.contains?(code, "receive")
  end

  defp analyze_shared_state_patterns(code) do
    %{
      global_state:
        String.contains?(code, ":persistent_term") or String.contains?(code, "Application."),
      process_dictionary:
        String.contains?(code, "Process.put") or String.contains?(code, "Process.get"),
      shared_ets: String.contains?(code, ":ets.new") and String.contains?(code, "public"),
      agent_sharing: count_pattern(code, "Agent.") > 1
    }
  end

  defp combine_pattern_and_runtime_analysis(pattern_analysis, execution_result) do
    pattern_issues = count_pattern_issues(pattern_analysis)

    runtime_issues =
      case execution_result do
        {:ok, result} -> Map.get(result, :race_events_detected, 0)
        {:error, _} -> 1
      end

    %{
      pattern_issues: pattern_issues,
      runtime_issues: runtime_issues,
      race_count: pattern_issues + runtime_issues,
      issue_count: pattern_issues + runtime_issues
    }
  end

  defp count_pattern_issues(pattern_analysis) do
    pattern_analysis
    |> Enum.reduce(0, fn {_category, patterns}, acc ->
      category_issues =
        patterns
        |> Enum.count(fn {_pattern, detected} -> detected end)

      acc + category_issues
    end)
  end

  defp combine_all_analyses(analyses) do
    total_races =
      analyses
      |> Enum.reduce(0, fn analysis, acc ->
        acc + Map.get(analysis, :race_conditions_detected, 0)
      end)

    total_issues =
      analyses
      |> Enum.reduce(0, fn analysis, acc ->
        acc + Map.get(analysis, :issues_detected, 0)
      end)

    %{
      total_races: total_races,
      total_issues: total_issues,
      analysis_count: length(analyses)
    }
  end

  defp calculate_basic_race_score(patterns) do
    issue_count = Map.get(patterns, :issue_count, 0)
    max(0.0, 100.0 - issue_count * 25.0)
  end

  defp calculate_statistical_race_score(analysis) do
    variance = Map.get(analysis, :coefficient_of_variation, 0.0)
    issue_count = Map.get(analysis, :issue_count, 0)

    base_score = max(0.0, 100.0 - issue_count * 30.0)
    variance_penalty = min(20.0, variance * 50.0)

    max(0.0, base_score - variance_penalty)
  end

  defp calculate_pattern_race_score(analysis) do
    issue_count = Map.get(analysis, :issue_count, 0)
    runtime_issues = Map.get(analysis, :runtime_issues, 0)

    max(0.0, 100.0 - issue_count * 15.0 - runtime_issues * 25.0)
  end

  defp calculate_comprehensive_race_score(analysis) do
    total_issues = Map.get(analysis, :total_issues, 0)
    analysis_count = Map.get(analysis, :analysis_count, 1)

    # Average penalty across all analysis types
    penalty_per_issue = 100.0 / max(1, analysis_count) * 0.2

    max(0.0, 100.0 - total_issues * penalty_per_issue)
  end

  defp initialize_race_statistics do
    %{
      total_detections: 0,
      races_found: 0,
      false_positives: 0,
      detection_accuracy: 0.0
    }
  end
end
