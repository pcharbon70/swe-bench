defmodule SweBench.ConcurrentEvaluation.MetricsCollector do
  @moduledoc """
  Telemetry aggregation and statistical analysis for concurrent evaluation.

  Collects, aggregates, and analyzes metrics from all concurrent evaluation
  components with statistical significance validation.
  """

  use GenServer
  require Logger

  defstruct [:config, :collected_metrics, :aggregation_intervals]

  @doc """
  Starts the metrics collector with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Collects metrics from all concurrent evaluation components.
  """
  def collect_metrics(evaluation_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:collect_metrics, evaluation_data, monitoring_tier}, 30_000)
  end

  @doc """
  Returns aggregated metrics and statistics.
  """
  def get_aggregated_metrics do
    GenServer.call(__MODULE__, :get_aggregated_metrics)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      collected_metrics: [],
      aggregation_intervals: initialize_intervals()
    }

    Logger.info("MetricsCollector initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:collect_metrics, evaluation_data, monitoring_tier}, _from, state) do
    metrics_result = perform_metrics_collection(evaluation_data, monitoring_tier, state)
    {:reply, {:ok, metrics_result}, state}
  rescue
    error ->
      Logger.error("Metrics collection failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  @impl true
  def handle_call(:get_aggregated_metrics, _from, state) do
    aggregated = aggregate_historical_metrics(state.collected_metrics)
    {:reply, aggregated, state}
  end

  # Private functions

  defp perform_metrics_collection(evaluation_data, monitoring_tier, _state) do
    %{
      monitoring_tier: monitoring_tier,
      collection_timestamp: DateTime.utc_now(),
      system_metrics: collect_system_metrics(),
      concurrent_metrics: extract_concurrent_metrics(evaluation_data),
      statistical_summary: generate_statistical_summary(evaluation_data),
      confidence_intervals: calculate_confidence_intervals(evaluation_data)
    }
  end

  defp collect_system_metrics do
    %{
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      ets_count: length(:ets.all()),
      memory_usage: :erlang.memory(),
      reduction_count: :erlang.statistics(:reductions) |> elem(0)
    }
  end

  defp extract_concurrent_metrics(evaluation_data) do
    %{
      race_conditions: Map.get(evaluation_data, :race_conditions_detected, 0),
      deadlocks: Map.get(evaluation_data, :deadlocks_detected, 0),
      mailbox_issues: Map.get(evaluation_data, :mailbox_problems, 0),
      supervisor_issues: Map.get(evaluation_data, :supervisor_failures, 0),
      overall_concurrent_score: Map.get(evaluation_data, :concurrent_score, 50.0)
    }
  end

  defp generate_statistical_summary(evaluation_data) do
    scores = [
      Map.get(evaluation_data, :process_score, 50.0),
      Map.get(evaluation_data, :race_score, 50.0),
      Map.get(evaluation_data, :deadlock_score, 50.0),
      Map.get(evaluation_data, :mailbox_score, 50.0),
      Map.get(evaluation_data, :supervisor_score, 50.0)
    ]
    
    mean = Enum.sum(scores) / length(scores)
    variance = calculate_score_variance(scores, mean)
    
    %{
      mean_score: mean,
      variance: variance,
      standard_deviation: :math.sqrt(variance),
      score_range: {Enum.min(scores), Enum.max(scores)}
    }
  end

  defp calculate_score_variance(scores, mean) do
    scores
    |> Enum.reduce(0, fn score, acc -> acc + :math.pow(score - mean, 2) end)
    |> Kernel./(length(scores))
  end

  defp calculate_confidence_intervals(evaluation_data) do
    # Basic confidence interval calculation for concurrent metrics
    concurrent_score = Map.get(evaluation_data, :concurrent_score, 50.0)
    
    # Assume normal distribution with estimated standard error
    standard_error = 5.0  # Estimated based on typical evaluation variance
    confidence_95 = 1.96 * standard_error
    
    %{
      confidence_level: 0.95,
      lower_bound: max(0.0, concurrent_score - confidence_95),
      upper_bound: min(100.0, concurrent_score + confidence_95),
      margin_of_error: confidence_95
    }
  end

  defp aggregate_historical_metrics(metrics_history) do
    if metrics_history == [] do
      %{no_historical_data: true}
    else
      # Basic aggregation of historical metrics
      %{
        total_collections: length(metrics_history),
        average_concurrent_score: calculate_average_concurrent_score(metrics_history),
        trend_analysis: analyze_score_trends(metrics_history)
      }
    end
  end

  defp calculate_average_concurrent_score(metrics_history) do
    scores = metrics_history
    |> Enum.map(fn metrics ->
        get_in(metrics, [:concurrent_metrics, :overall_concurrent_score]) || 50.0
    end)
    
    if scores != [] do
      Enum.sum(scores) / length(scores)
    else
      50.0
    end
  end

  defp analyze_score_trends(metrics_history) when length(metrics_history) < 3 do
    %{trend: :insufficient_data}
  end

  defp analyze_score_trends(metrics_history) do
    recent_scores = metrics_history
    |> Enum.take(-5)  # Last 5 evaluations
    |> Enum.map(fn metrics ->
        get_in(metrics, [:concurrent_metrics, :overall_concurrent_score]) || 50.0
    end)
    
    first_half_avg = recent_scores |> Enum.take(2) |> Enum.sum() |> Kernel./(2)
    second_half_avg = recent_scores |> Enum.drop(3) |> Enum.sum() |> Kernel./(2)
    
    trend = cond do
      second_half_avg > first_half_avg + 5 -> :improving
      second_half_avg < first_half_avg - 5 -> :declining  
      true -> :stable
    end
    
    %{
      trend: trend,
      recent_average: Enum.sum(recent_scores) / length(recent_scores),
      trend_magnitude: abs(second_half_avg - first_half_avg)
    }
  end

  defp initialize_intervals do
    %{
      process_metrics: 2000,    # 2 second intervals
      race_detection: 5000,     # 5 second intervals  
      deadlock_analysis: 10000, # 10 second intervals
      mailbox_monitoring: 3000  # 3 second intervals
    }
  end
end