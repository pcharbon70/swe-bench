defmodule SweBench.PartialCreditScoring.ScoreAggregator do
  @moduledoc """
  Aggregates scores from multiple dimensions with configurable weighting.

  Provides weighted combination, detailed breakdowns, consistency tracking,
  and generates comprehensive scoring reports with improvement suggestions.
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :aggregation_history,
    :consistency_tracker
  ]

  @doc """
  Starts the score aggregator with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Aggregates scores from multiple dimensions.

  Returns a comprehensive result with weighted score, individual breakdowns,
  and consistency metadata.
  """
  def aggregate_scores(dimension_results) do
    GenServer.call(__MODULE__, {:aggregate_scores, dimension_results}, 30_000)
  end

  @doc """
  Returns aggregation statistics and consistency metrics.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: config,
      aggregation_history: [],
      consistency_tracker: initialize_consistency_tracker()
    }

    Logger.info("ScoreAggregator initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:aggregate_scores, dimension_results}, _from, state) do
    try do
      aggregated_result = perform_aggregation(dimension_results, state.config)
      
      # Update consistency tracking
      new_consistency_tracker = update_consistency_tracking(
        state.consistency_tracker,
        aggregated_result
      )

      # Update history (keep last 100 entries)
      new_history = [aggregated_result | state.aggregation_history]
      |> Enum.take(100)

      new_state = %{state |
        aggregation_history: new_history,
        consistency_tracker: new_consistency_tracker
      }

      {:reply, {:ok, aggregated_result}, new_state}
    rescue
      error ->
        Logger.error("Score aggregation failed: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    statistics = generate_statistics(state)
    {:reply, statistics, state}
  end

  # Private functions

  defp perform_aggregation(dimension_results, config) do
    dimension_config = config.dimensions
    minimum_score_diff = config[:minimum_score_difference] || 0.10

    # Process individual dimension results
    processed_results = process_dimension_results(dimension_results, dimension_config)

    # Calculate weighted aggregate score
    weighted_score = calculate_weighted_score(processed_results, dimension_config)

    # Generate detailed breakdown
    breakdown = generate_score_breakdown(processed_results, dimension_config)

    # Determine score category
    score_category = determine_score_category(weighted_score)

    # Generate improvement suggestions
    improvements = generate_improvement_suggestions(processed_results, config)

    %{
      overall_score: weighted_score,
      score_category: score_category,
      dimension_scores: processed_results,
      detailed_breakdown: breakdown,
      improvement_suggestions: improvements,
      minimum_meaningful_difference: minimum_score_diff,
      timestamp: DateTime.utc_now(),
      aggregation_strategy: config[:aggregation_strategy] || :weighted_average
    }
  end

  defp process_dimension_results(dimension_results, dimension_config) do
    Enum.reduce(dimension_results, %{}, fn {dimension, result}, acc ->
      case result do
        {:ok, score_data} ->
          processed = process_dimension_score(score_data, dimension_config[dimension])
          Map.put(acc, dimension, processed)

        {:error, reason} ->
          Map.put(acc, dimension, %{
            score: 0.0,
            threshold_met: false,
            error: reason,
            status: :failed
          })
      end
    end)
  end

  defp process_dimension_score(score_data, dimension_config) when is_map(score_data) do
    raw_score = Map.get(score_data, :score, 0.0)
    threshold = Map.get(dimension_config || %{}, :threshold, 0)
    
    %{
      score: normalize_score(raw_score),
      raw_score: raw_score,
      threshold: threshold,
      threshold_met: raw_score >= threshold,
      details: Map.get(score_data, :details, %{}),
      status: :success
    }
  end

  defp process_dimension_score(score_data, dimension_config) when is_number(score_data) do
    threshold = Map.get(dimension_config || %{}, :threshold, 0)
    
    %{
      score: normalize_score(score_data),
      raw_score: score_data,
      threshold: threshold,
      threshold_met: score_data >= threshold,
      details: %{},
      status: :success
    }
  end

  defp normalize_score(score) when score < 0, do: 0.0
  defp normalize_score(score) when score > 100, do: 100.0
  defp normalize_score(score), do: score / 1.0

  defp calculate_weighted_score(processed_results, dimension_config) do
    total_weight = dimension_config
    |> Enum.reduce(0.0, fn {_dim, config}, acc -> 
        acc + (Map.get(config, :weight, 0.0))
    end)

    if total_weight > 0 do
      weighted_sum = Enum.reduce(processed_results, 0.0, fn {dimension, result}, acc ->
        weight = get_in(dimension_config, [dimension, :weight]) || 0.0
        score = Map.get(result, :score, 0.0)
        acc + (score * weight)
      end)

      weighted_sum / total_weight * 100
    else
      0.0
    end
  end

  defp generate_score_breakdown(processed_results, dimension_config) do
    Enum.reduce(processed_results, %{}, fn {dimension, result}, acc ->
      weight = get_in(dimension_config, [dimension, :weight]) || 0.0
      score = Map.get(result, :score, 0.0)
      contribution = score * weight

      Map.put(acc, dimension, %{
        weight: weight,
        score: score,
        weighted_contribution: contribution,
        threshold_met: Map.get(result, :threshold_met, false),
        status: Map.get(result, :status, :unknown)
      })
    end)
  end

  defp determine_score_category(score) when score >= 90, do: :excellent
  defp determine_score_category(score) when score >= 75, do: :good
  defp determine_score_category(score) when score >= 50, do: :partial
  defp determine_score_category(score) when score >= 25, do: :minimal
  defp determine_score_category(_score), do: :insufficient

  defp generate_improvement_suggestions(processed_results, config) do
    if config[:improvement_suggestions] do
      processed_results
      |> Enum.reduce([], fn {dimension, result}, acc ->
          case Map.get(result, :status) do
            :failed ->
              ["Fix #{dimension} errors: #{inspect(Map.get(result, :error))}" | acc]

            :success ->
              if not Map.get(result, :threshold_met, false) do
                threshold = Map.get(result, :threshold, 0)
                score = Map.get(result, :score, 0)
                improvement = threshold - score
                ["Improve #{dimension} by #{improvement}% to meet threshold" | acc]
              else
                acc
              end

            _ ->
              acc
          end
      end)
      |> Enum.reverse()
    else
      []
    end
  end

  defp initialize_consistency_tracker do
    %{
      total_aggregations: 0,
      score_variance_history: [],
      consistency_metrics: %{
        variance: 0.0,
        standard_deviation: 0.0,
        consistency_rating: :unknown
      }
    }
  end

  defp update_consistency_tracking(tracker, aggregated_result) do
    overall_score = Map.get(aggregated_result, :overall_score, 0.0)
    new_history = [overall_score | tracker.score_variance_history] |> Enum.take(20)
    total = tracker.total_aggregations + 1

    new_metrics = if length(new_history) >= 2 do
      variance = calculate_variance(new_history)
      std_dev = :math.sqrt(variance)
      consistency_rating = determine_consistency_rating(std_dev)

      %{
        variance: variance,
        standard_deviation: std_dev,
        consistency_rating: consistency_rating
      }
    else
      tracker.consistency_metrics
    end

    %{tracker |
      total_aggregations: total,
      score_variance_history: new_history,
      consistency_metrics: new_metrics
    }
  end

  defp calculate_variance(scores) when length(scores) < 2, do: 0.0
  defp calculate_variance(scores) do
    mean = Enum.sum(scores) / length(scores)
    variance_sum = scores
    |> Enum.reduce(0, fn score, acc -> acc + :math.pow(score - mean, 2) end)
    
    variance_sum / (length(scores) - 1)
  end

  defp determine_consistency_rating(std_dev) when std_dev <= 2.0, do: :excellent
  defp determine_consistency_rating(std_dev) when std_dev <= 5.0, do: :good
  defp determine_consistency_rating(std_dev) when std_dev <= 10.0, do: :fair
  defp determine_consistency_rating(_std_dev), do: :poor

  defp generate_statistics(state) do
    %{
      total_aggregations: state.consistency_tracker.total_aggregations,
      consistency_metrics: state.consistency_tracker.consistency_metrics,
      recent_scores: state.consistency_tracker.score_variance_history,
      history_size: length(state.aggregation_history)
    }
  end
end