defmodule SweBench.Integration.PerformanceValidator do
  @moduledoc """
  Performance validation for integrated Phase 4 systems.

  Validates that performance targets are maintained when all systems
  work together under realistic load conditions.
  """

  require Logger

  @performance_targets %{
    throughput_tasks_per_hour: 100,
    response_time_p95_ms: 10_000,
    memory_usage_gb_max: 32,
    cpu_usage_percent_max: 80,
    error_rate_percent_max: 1.0
  }

  @doc """
  Validates production performance under integrated system load.
  """
  def validate_production_performance(simulation_data) do
    Logger.info("Validating production performance")

    performance_metrics = extract_performance_metrics(simulation_data)
    validation_results = validate_against_targets(performance_metrics)

    %{
      performance_metrics: performance_metrics,
      validation_results: validation_results,
      performance_score: calculate_performance_score(validation_results),
      production_ready: all_targets_met?(validation_results)
    }
  end

  # Private functions

  defp extract_performance_metrics(simulation_data) do
    %{
      throughput: Map.get(simulation_data, :tasks_per_hour, 95),
      response_time_p95: Map.get(simulation_data, :response_time_ms, 8_500),
      memory_usage: Map.get(simulation_data, :memory_usage_gb, 28),
      cpu_usage: Map.get(simulation_data, :cpu_usage_percent, 75),
      error_rate: Map.get(simulation_data, :error_rate_percent, 0.5)
    }
  end

  defp validate_against_targets(metrics) do
    @performance_targets
    |> Enum.map(fn {target_name, target_value} ->
      actual_value = get_metric_value(metrics, target_name)
      validation_result = validate_single_target(target_name, actual_value, target_value)
      {target_name, validation_result}
    end)
    |> Enum.into(%{})
  end

  defp get_metric_value(metrics, :throughput_tasks_per_hour), do: Map.get(metrics, :throughput, 0)

  defp get_metric_value(metrics, :response_time_p95_ms),
    do: Map.get(metrics, :response_time_p95, 0)

  defp get_metric_value(metrics, :memory_usage_gb_max), do: Map.get(metrics, :memory_usage, 0)
  defp get_metric_value(metrics, :cpu_usage_percent_max), do: Map.get(metrics, :cpu_usage, 0)
  defp get_metric_value(metrics, :error_rate_percent_max), do: Map.get(metrics, :error_rate, 0)

  defp validate_single_target(target_name, actual_value, target_value) do
    case target_name do
      name when name in [:throughput_tasks_per_hour] ->
        # Higher is better
        %{
          passed: actual_value >= target_value,
          actual: actual_value,
          target: target_value,
          variance_percent: (actual_value - target_value) / target_value * 100.0
        }

      name
      when name in [
             :response_time_p95_ms,
             :memory_usage_gb_max,
             :cpu_usage_percent_max,
             :error_rate_percent_max
           ] ->
        # Lower is better
        %{
          passed: actual_value <= target_value,
          actual: actual_value,
          target: target_value,
          variance_percent: (actual_value - target_value) / target_value * 100.0
        }

      _ ->
        %{passed: true, actual: actual_value, target: target_value, variance_percent: 0.0}
    end
  end

  defp calculate_performance_score(validation_results) do
    total_targets = map_size(validation_results)

    passed_targets =
      validation_results
      |> Enum.count(fn {_name, result} -> Map.get(result, :passed, false) end)

    if total_targets > 0 do
      passed_targets / total_targets * 100.0
    else
      0.0
    end
  end

  defp all_targets_met?(validation_results) do
    validation_results
    |> Enum.all?(fn {_name, result} -> Map.get(result, :passed, false) end)
  end
end
