defmodule SweBench.QualityValidation.StatisticalAnalyzer do
  @moduledoc """
  Statistical analysis for quality validation.

  Performs distribution analysis, outlier detection, and quality trend
  analysis for comprehensive benchmark quality assessment.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Analyzes task quality using statistical methods.
  """
  def analyze_task_quality(task_instance) do
    GenServer.call(__MODULE__, {:analyze_task, task_instance})
  end

  @doc """
  Analyzes quality distribution across multiple task instances.
  """
  def analyze_quality_distribution(task_instances) do
    GenServer.call(__MODULE__, {:analyze_distribution, task_instances})
  end

  @doc """
  Gets statistical analysis statistics.
  """
  def get_analysis_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      analyses_performed: 0,
      outliers_detected: 0,
      avg_analysis_time: 0.0,
      quality_distributions: %{}
    }

    Logger.info("Statistical analyzer started")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_task, task_instance}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      task_instance
      |> calculate_quality_percentile()
      |> detect_quality_outliers()
      |> analyze_complexity_distribution()
      |> compile_statistical_result()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_analysis_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call({:analyze_distribution, task_instances}, _from, state) do
    result =
      task_instances
      |> calculate_distribution_metrics()
      |> identify_dataset_outliers()
      |> analyze_quality_trends()

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private analysis functions

  defp calculate_quality_percentile(task_instance) do
    Logger.debug("Calculating quality percentile for task #{task_instance.instance_id}")

    # Placeholder - will calculate percentile based on historical data
    quality_metrics = %{
      quality_percentile: 0.75,
      difficulty_percentile: 0.60,
      complexity_percentile: 0.80,
      relative_quality_score: 0.72
    }

    add_analysis_result(task_instance, :quality_percentile, quality_metrics)
  end

  defp detect_quality_outliers(task_instance) do
    Logger.debug("Detecting quality outliers for task #{task_instance.instance_id}")

    # Placeholder - will implement statistical outlier detection
    outlier_analysis = %{
      is_outlier: false,
      outlier_score: 0.15,
      outlier_factors: [],
      outlier_confidence: 0.85
    }

    add_analysis_result(task_instance, :outlier_detection, outlier_analysis)
  end

  defp analyze_complexity_distribution(task_instance) do
    Logger.debug("Analyzing complexity distribution for task #{task_instance.instance_id}")

    # Placeholder - will analyze complexity relative to distribution
    complexity_analysis = %{
      complexity_z_score: 0.5,
      complexity_category: :moderate,
      relative_difficulty: 0.65,
      complexity_confidence: 0.80
    }

    add_analysis_result(task_instance, :complexity_distribution, complexity_analysis)
  end

  defp compile_statistical_result(task_instance) do
    analysis_results = Map.get(task_instance, :statistical_analysis_results, [])

    # Combine all statistical analyses
    combined_metrics = %{
      quality_percentile: get_metric(analysis_results, :quality_percentile, :quality_percentile),
      is_outlier: get_metric(analysis_results, :outlier_detection, :is_outlier),
      complexity_category: get_metric(analysis_results, :complexity_distribution, :complexity_category),
      statistical_confidence: calculate_statistical_confidence(analysis_results)
    }

    statistical_summary = %{
      quality_score: calculate_statistical_quality_score(combined_metrics),
      statistical_metrics: combined_metrics,
      analysis_stage: :statistical,
      analyzed_at: DateTime.utc_now()
    }

    {:ok, statistical_summary}
  end

  defp calculate_distribution_metrics(task_instances) when is_list(task_instances) do
    # Calculate dataset-wide distribution metrics
    quality_scores = Enum.map(task_instances, & &1.quality_score || 0.5)

    distribution = %{
      mean: Enum.sum(quality_scores) / length(quality_scores),
      median: calculate_median(quality_scores),
      std_dev: calculate_standard_deviation(quality_scores),
      percentiles: calculate_percentiles(quality_scores),
      instance_count: length(task_instances)
    }

    {:ok, distribution}
  end

  defp identify_dataset_outliers({:ok, distribution}) do
    # Implement outlier identification logic
    outlier_threshold = distribution.mean + (2 * distribution.std_dev)

    outliers = %{
      outlier_count: 0,  # Placeholder
      outlier_threshold: outlier_threshold,
      outlier_instances: []
    }

    {:ok, {distribution, outliers}}
  end

  defp analyze_quality_trends({:ok, {distribution, outliers}}) do
    # Analyze quality trends over time
    trends = %{
      quality_trend: :stable,  # Placeholder
      trend_confidence: 0.80,
      improvement_rate: 0.0
    }

    {:ok, {distribution, outliers, trends}}
  end

  defp add_analysis_result(task_instance, analysis_type, metrics) do
    analysis_result = %{
      type: analysis_type,
      metrics: metrics,
      timestamp: DateTime.utc_now()
    }

    existing_results = Map.get(task_instance, :statistical_analysis_results, [])
    Map.put(task_instance, :statistical_analysis_results, [analysis_result | existing_results])
  end

  defp get_metric(analysis_results, analysis_type, metric_key) do
    case Enum.find(analysis_results, &(&1.type == analysis_type)) do
      %{metrics: metrics} -> Map.get(metrics, metric_key)
      nil -> nil
    end
  end

  defp calculate_statistical_confidence(analysis_results) do
    confidences = 
      analysis_results
      |> Enum.map(&Map.get(&1.metrics, :confidence, 0.5))
      |> Enum.filter(&(&1 > 0))

    if Enum.empty?(confidences) do
      0.5
    else
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp calculate_statistical_quality_score(metrics) do
    # Combine statistical metrics into overall quality score
    base_score = metrics.quality_percentile || 0.5

    # Adjust for outliers (reduce score if it's an outlier)
    outlier_penalty = if metrics.is_outlier, do: 0.1, else: 0.0

    # Adjust for complexity appropriateness
    complexity_adjustment = 
      case metrics.complexity_category do
        :very_easy -> 0.0   # May be too simple
        :easy -> 0.05
        :moderate -> 0.1    # Ideal complexity
        :hard -> 0.05
        :very_hard -> 0.0   # May be too complex
        _ -> 0.0
      end

    max(0.0, min(1.0, base_score - outlier_penalty + complexity_adjustment))
  end

  defp calculate_median(values) when is_list(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    if rem(count, 2) == 0 do
      # Even number of values
      mid1 = Enum.at(sorted, div(count, 2) - 1)
      mid2 = Enum.at(sorted, div(count, 2))
      (mid1 + mid2) / 2
    else
      # Odd number of values
      Enum.at(sorted, div(count, 2))
    end
  end

  defp calculate_standard_deviation(values) do
    mean = Enum.sum(values) / length(values)
    
    variance =
      values
      |> Enum.map(&((&1 - mean) * (&1 - mean)))
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp calculate_percentiles(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    %{
      p25: percentile_at(sorted, count, 0.25),
      p50: percentile_at(sorted, count, 0.50),
      p75: percentile_at(sorted, count, 0.75),
      p90: percentile_at(sorted, count, 0.90),
      p95: percentile_at(sorted, count, 0.95)
    }
  end

  defp percentile_at(sorted_values, count, percentile) do
    index = round(count * percentile) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_values, index)
  end

  defp update_analysis_stats(state, result, processing_time) do
    new_total = state.analyses_performed + 1

    new_outliers =
      case result do
        {:ok, %{statistical_metrics: %{is_outlier: true}}} ->
          state.outliers_detected + 1

        _ ->
          state.outliers_detected
      end

    new_avg_time =
      if new_total > 1 do
        ((state.avg_analysis_time * (new_total - 1)) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | analyses_performed: new_total,
        outliers_detected: new_outliers,
        avg_analysis_time: new_avg_time
    }
  end
end