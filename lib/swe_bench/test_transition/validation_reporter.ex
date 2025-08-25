defmodule SweBench.TestTransition.ValidationReporter do
  @moduledoc """
  Comprehensive validation reporting and metrics generation.

  Provides detailed reports on validation results, quality distribution,
  and performance metrics for monitoring and analysis.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates a comprehensive validation report.
  """
  def generate_report(repository_id, opts \\ []) do
    GenServer.call(__MODULE__, {:generate_report, repository_id, opts})
  end

  @doc """
  Gets validation summary statistics.
  """
  def get_summary_stats do
    GenServer.call(__MODULE__, :get_summary_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      reports_generated: 0,
      last_report_generated: nil
    }

    Logger.info("Validation reporter started")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_report, repository_id, opts}, _from, state) do
    time_window = Keyword.get(opts, :time_window_hours, 24)

    report =
      repository_id
      |> fetch_validation_data(time_window)
      |> analyze_validation_patterns()
      |> generate_comprehensive_report()

    updated_state = %{
      state
      | reports_generated: state.reports_generated + 1,
        last_report_generated: DateTime.utc_now()
    }

    {:reply, report, updated_state}
  end

  @impl true
  def handle_call(:get_summary_stats, _from, state) do
    summary = generate_overall_summary()
    {:reply, summary, state}
  end

  # Private implementation functions

  defp fetch_validation_data(repository_id, _time_window_hours) do
    SweBench.ValidationResults.ValidationResult
    |> Ash.Query.for_read(:by_repository, %{repository_id: repository_id})
    |> Ash.Query.for_read(:recent_validations)
    |> Ash.Query.load([:issue_pr_link, :repository])
    |> Ash.read!()
  end

  defp analyze_validation_patterns(validation_results) do
    patterns = %{
      total_validations: length(validation_results),
      quality_distribution: calculate_quality_distribution(validation_results),
      consistency_trends: calculate_consistency_trends(validation_results),
      transition_patterns: analyze_transition_patterns(validation_results),
      performance_metrics: calculate_performance_metrics(validation_results)
    }

    {validation_results, patterns}
  end

  defp calculate_quality_distribution(validation_results) do
    validation_results
    |> Enum.group_by(& &1.benchmark_quality)
    |> Enum.map(fn {quality, group} ->
      {quality,
       %{
         count: length(group),
         percentage: length(group) / length(validation_results) * 100,
         avg_confidence: calculate_avg_confidence(group)
       }}
    end)
    |> Map.new()
  end

  defp calculate_consistency_trends(validation_results) do
    if Enum.empty?(validation_results) do
      %{trend: :insufficient_data}
    else
      consistencies = Enum.map(validation_results, & &1.consistency_score)

      %{
        avg_consistency: Enum.sum(consistencies) / length(consistencies),
        min_consistency: Enum.min(consistencies),
        max_consistency: Enum.max(consistencies),
        trend: determine_consistency_trend(consistencies)
      }
    end
  end

  defp analyze_transition_patterns(validation_results) do
    %{
      total_fail_to_pass: Enum.sum(Enum.map(validation_results, & &1.fail_to_pass_count)),
      total_pass_to_fail: Enum.sum(Enum.map(validation_results, & &1.pass_to_fail_count)),
      avg_transitions_per_validation: calculate_avg_transitions(validation_results),
      flaky_test_frequency: calculate_flaky_frequency(validation_results)
    }
  end

  defp calculate_performance_metrics(validation_results) do
    if Enum.empty?(validation_results) do
      %{avg_processing_time: 0, total_processing_time: 0}
    else
      processing_times =
        validation_results
        |> Enum.map(&Map.get(&1, :execution_time_ms, 0))
        |> Enum.filter(&(&1 > 0))

      if Enum.empty?(processing_times) do
        %{avg_processing_time: 0, total_processing_time: 0}
      else
        %{
          avg_processing_time: Enum.sum(processing_times) / length(processing_times),
          total_processing_time: Enum.sum(processing_times),
          min_processing_time: Enum.min(processing_times),
          max_processing_time: Enum.max(processing_times)
        }
      end
    end
  end

  defp generate_comprehensive_report({validation_results, patterns}) do
    report = %{
      repository_id: get_repository_id(validation_results),
      generated_at: DateTime.utc_now(),
      validation_summary: patterns,
      recommendations: generate_recommendations(patterns),
      quality_insights: generate_quality_insights(patterns),
      performance_analysis: patterns.performance_metrics
    }

    {:ok, report}
  end

  defp generate_recommendations(patterns) do
    recommendations = []

    recommendations =
      if patterns.quality_distribution[:unsuitable][:percentage] > 20 do
        ["Consider stricter issue-PR filtering criteria" | recommendations]
      else
        recommendations
      end

    recommendations =
      if patterns.consistency_trends.avg_consistency < 0.80 do
        ["Review test isolation and determinism procedures" | recommendations]
      else
        recommendations
      end

    recommendations =
      if patterns.transition_patterns.flaky_test_frequency > 0.1 do
        ["Investigate flaky test patterns and improve test stability" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp generate_quality_insights(patterns) do
    %{
      benchmark_readiness: assess_benchmark_readiness(patterns),
      improvement_areas: identify_improvement_areas(patterns),
      success_rate: calculate_success_rate(patterns)
    }
  end

  defp assess_benchmark_readiness(patterns) do
    high_quality_percentage =
      (get_in(patterns, [:quality_distribution, :gold, :percentage]) || 0) +
        (get_in(patterns, [:quality_distribution, :silver, :percentage]) || 0)

    cond do
      high_quality_percentage >= 70 -> :excellent
      high_quality_percentage >= 50 -> :good
      high_quality_percentage >= 30 -> :moderate
      true -> :needs_improvement
    end
  end

  defp identify_improvement_areas(patterns) do
    areas = []

    areas =
      if patterns.consistency_trends.avg_consistency < 0.85 do
        [:test_determinism | areas]
      else
        areas
      end

    areas =
      if patterns.transition_patterns.flaky_test_frequency > 0.05 do
        [:flaky_test_reduction | areas]
      else
        areas
      end

    areas =
      if patterns.performance_metrics.avg_processing_time > 300_000 do
        [:performance_optimization | areas]
      else
        areas
      end

    areas
  end

  defp calculate_success_rate(patterns) do
    total = patterns.total_validations

    if total > 0 do
      successful =
        (get_in(patterns, [:quality_distribution, :gold, :count]) || 0) +
          (get_in(patterns, [:quality_distribution, :silver, :count]) || 0) +
          (get_in(patterns, [:quality_distribution, :bronze, :count]) || 0)

      successful / total
    else
      0.0
    end
  end

  defp generate_overall_summary do
    # Generate summary across all repositories
    %{
      total_repositories_validated: count_validated_repositories(),
      overall_quality_distribution: calculate_overall_quality_distribution(),
      system_performance: calculate_system_performance(),
      recommendations: generate_system_recommendations()
    }
  end

  defp count_validated_repositories do
    # Placeholder - will query actual data
    0
  end

  defp calculate_overall_quality_distribution do
    # Placeholder - will aggregate across all repositories
    %{gold: 0, silver: 0, bronze: 0, unsuitable: 0}
  end

  defp calculate_system_performance do
    # Placeholder - will calculate system-wide performance metrics
    %{avg_validation_time: 0, throughput_per_hour: 0}
  end

  defp generate_system_recommendations do
    # Placeholder - will generate system-wide recommendations
    []
  end

  defp calculate_avg_confidence(validation_results) do
    if Enum.empty?(validation_results) do
      0.0
    else
      total_confidence = Enum.sum(Enum.map(validation_results, & &1.confidence_level))
      total_confidence / length(validation_results)
    end
  end

  defp determine_consistency_trend(consistencies) do
    # Simple trend analysis - will be enhanced with statistical analysis
    if length(consistencies) < 2 do
      :insufficient_data
    else
      first_half = Enum.take(consistencies, div(length(consistencies), 2))
      second_half = Enum.drop(consistencies, div(length(consistencies), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      cond do
        second_avg > first_avg + 0.05 -> :improving
        second_avg < first_avg - 0.05 -> :declining
        true -> :stable
      end
    end
  end

  defp calculate_avg_transitions(validation_results) do
    if Enum.empty?(validation_results) do
      0.0
    else
      total_transitions =
        validation_results
        |> Enum.map(fn result ->
          (result.fail_to_pass_count || 0) + (result.pass_to_fail_count || 0)
        end)
        |> Enum.sum()

      total_transitions / length(validation_results)
    end
  end

  defp calculate_flaky_frequency(validation_results) do
    if Enum.empty?(validation_results) do
      0.0
    else
      total_flaky =
        validation_results
        |> Enum.map(&length(&1.flaky_tests || []))
        |> Enum.sum()

      total_tests =
        validation_results
        |> Enum.map(fn result ->
          (result.fail_to_pass_count || 0) + (result.pass_to_pass_count || 0) +
            (result.pass_to_fail_count || 0)
        end)
        |> Enum.sum()

      if total_tests > 0 do
        total_flaky / total_tests
      else
        0.0
      end
    end
  end

  defp get_repository_id([]), do: nil
  defp get_repository_id([first | _]), do: first.repository_id
end
