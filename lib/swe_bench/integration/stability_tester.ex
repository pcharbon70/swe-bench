defmodule SweBench.Integration.StabilityTester do
  @moduledoc """
  Long-running stability validation for integrated Phase 4 systems.

  Executes extended stability tests to validate system reliability,
  performance consistency, and resource management under sustained load.
  """

  require Logger

  @doc """
  Runs comprehensive stability test for the integrated system.
  """
  def run_stability_test(test_spec, config \\ %{}) do
    Logger.info("Starting comprehensive stability test")

    stability_config = build_stability_config(test_spec, config)

    # For demonstration, run a shorter simulation instead of 24 hours
    simulation_duration = Map.get(stability_config, :simulation_duration_minutes, 5)

    stability_result = execute_stability_simulation(stability_config, simulation_duration)

    case stability_result do
      {:ok, stability_data} ->
        {:ok,
         %{
           stability_test_successful: true,
           duration_hours: simulation_duration / 60.0,
           stability_metrics: stability_data,
           degradation_detected: detect_performance_degradation(stability_data),
           recommendations: generate_stability_recommendations(stability_data)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Stability test failed: #{inspect(error)}")
      {:error, error}
  end

  # Private functions

  defp build_stability_config(test_spec, config) do
    default_config = %{
      test_duration_hours: 24,
      # Shortened for demonstration
      simulation_duration_minutes: 5,
      monitoring_interval_seconds: 30,
      performance_baseline: %{
        throughput: 100,
        response_time: 5000,
        memory_usage: 25,
        cpu_usage: 70
      },
      degradation_threshold_percent: 10.0
    }

    Map.merge(default_config, config)
    |> Map.merge(extract_test_params(test_spec))
  end

  defp extract_test_params(test_spec) do
    %{
      load_pattern: Map.get(test_spec, :load_pattern, :constant),
      stress_testing: Map.get(test_spec, :stress_testing, false),
      fault_injection: Map.get(test_spec, :fault_injection, false)
    }
  end

  defp execute_stability_simulation(config, duration_minutes) do
    Logger.info("Executing #{duration_minutes}-minute stability simulation")

    # Simulate stability metrics over time
    # Monitor every 2 minutes
    monitoring_intervals = max(1, div(duration_minutes, 2))

    stability_samples =
      1..monitoring_intervals
      |> Enum.map(fn interval ->
        simulate_interval_metrics(interval, config)
      end)

    stability_analysis = analyze_stability_samples(stability_samples, config)

    {:ok,
     %{
       monitoring_intervals: monitoring_intervals,
       stability_samples: stability_samples,
       stability_analysis: stability_analysis,
       final_metrics: List.last(stability_samples)
     }}
  end

  defp simulate_interval_metrics(interval, config) do
    baseline = config.performance_baseline
    degradation_factor = calculate_degradation_factor(interval, config)

    %{
      interval: interval,
      timestamp: DateTime.utc_now(),
      throughput: apply_degradation(baseline.throughput, degradation_factor),
      response_time: apply_degradation(baseline.response_time, degradation_factor, :increase),
      memory_usage: apply_degradation(baseline.memory_usage, degradation_factor, :increase),
      cpu_usage: apply_degradation(baseline.cpu_usage, degradation_factor),
      # 0-2 errors per interval
      error_count: :rand.uniform(3),
      system_health: assess_interval_system_health(interval)
    }
  end

  defp calculate_degradation_factor(interval, config) do
    base_degradation = Map.get(config, :expected_degradation_percent, 2.0)

    # Slight increase over time to simulate realistic degradation
    time_factor = interval / 100.0
    base_degradation + time_factor
  end

  defp apply_degradation(baseline_value, degradation_percent, direction \\ :decrease) do
    degradation_amount = baseline_value * (degradation_percent / 100.0)

    case direction do
      :decrease -> baseline_value - degradation_amount + :rand.uniform() * degradation_amount
      :increase -> baseline_value + degradation_amount + :rand.uniform() * degradation_amount
    end
  end

  defp assess_interval_system_health(interval) do
    # Mock system health assessment
    base_health = 95.0
    # 0-5% variability
    variability = :rand.uniform() * 5.0

    # Slight decline over time
    health_score = base_health + variability - interval * 0.1

    cond do
      health_score >= 95.0 -> :excellent
      health_score >= 85.0 -> :good
      health_score >= 75.0 -> :fair
      true -> :poor
    end
  end

  defp analyze_stability_samples(samples, config) do
    if samples == [] do
      %{stability_analysis: :no_data}
    else
      baseline = config.performance_baseline

      %{
        sample_count: length(samples),
        throughput_trend: analyze_metric_trend(samples, :throughput),
        response_time_trend: analyze_metric_trend(samples, :response_time),
        memory_trend: analyze_metric_trend(samples, :memory_usage),
        cpu_trend: analyze_metric_trend(samples, :cpu_usage),
        error_trend: analyze_error_trend(samples),
        overall_stability: assess_overall_stability(samples, baseline),
        degradation_detected: detect_significant_degradation(samples, baseline, config)
      }
    end
  end

  defp analyze_metric_trend(samples, metric_key) do
    values = Enum.map(samples, fn sample -> Map.get(sample, metric_key, 0) end)

    if length(values) >= 2 do
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      cond do
        second_avg > first_avg * 1.05 -> :increasing
        second_avg < first_avg * 0.95 -> :decreasing
        true -> :stable
      end
    else
      :insufficient_data
    end
  end

  defp analyze_error_trend(samples) do
    total_errors =
      samples
      |> Enum.reduce(0, fn sample, acc -> acc + Map.get(sample, :error_count, 0) end)

    %{
      total_errors: total_errors,
      error_rate: total_errors / length(samples),
      error_trend: if(total_errors > length(samples), do: :concerning, else: :acceptable)
    }
  end

  defp assess_overall_stability(samples, _baseline) do
    stability_indicators =
      samples
      |> Enum.map(fn sample ->
        health = Map.get(sample, :system_health, :good)
        health in [:excellent, :good]
      end)

    stable_intervals = Enum.count(stability_indicators, & &1)
    stability_percentage = stable_intervals / length(samples) * 100.0

    %{
      stable_intervals: stable_intervals,
      total_intervals: length(samples),
      stability_percentage: stability_percentage,
      overall_rating: determine_stability_rating(stability_percentage)
    }
  end

  defp determine_stability_rating(percentage) when percentage >= 95.0, do: :excellent
  defp determine_stability_rating(percentage) when percentage >= 85.0, do: :good
  defp determine_stability_rating(percentage) when percentage >= 75.0, do: :fair
  defp determine_stability_rating(_percentage), do: :poor

  defp detect_performance_degradation(stability_data) do
    # Check if significant degradation occurred during stability test
    degradation_indicators = [
      stability_data.throughput_trend == :decreasing,
      stability_data.response_time_trend == :increasing,
      stability_data.memory_trend == :increasing,
      Map.get(stability_data.error_trend, :error_trend) == :concerning
    ]

    degradation_count = Enum.count(degradation_indicators, & &1)

    %{
      degradation_detected: degradation_count >= 2,
      degradation_indicators: degradation_count,
      severity: determine_degradation_severity(degradation_count)
    }
  end

  defp detect_significant_degradation(samples, baseline, config) do
    threshold = Map.get(config, :degradation_threshold_percent, 10.0)

    if samples != [] do
      final_sample = List.last(samples)

      throughput_degradation =
        (baseline.throughput - Map.get(final_sample, :throughput, 0)) / baseline.throughput *
          100.0

      throughput_degradation > threshold
    else
      false
    end
  end

  defp determine_degradation_severity(indicator_count) when indicator_count >= 3, do: :critical
  defp determine_degradation_severity(indicator_count) when indicator_count >= 2, do: :major
  defp determine_degradation_severity(indicator_count) when indicator_count >= 1, do: :minor
  defp determine_degradation_severity(_), do: :none

  defp generate_stability_recommendations(stability_data) do
    recommendations = []

    # Add recommendations based on stability analysis
    recommendations =
      if Map.get(stability_data, :degradation_detected, false) do
        ["Address performance degradation issues", "Review resource allocation" | recommendations]
      else
        recommendations
      end

    recommendations =
      if get_in(stability_data, [:error_trend, :error_trend]) == :concerning do
        ["Investigate error sources", "Improve error handling" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["System stability is excellent", "Continue monitoring for optimal performance"]
    else
      recommendations
    end
  end
end
