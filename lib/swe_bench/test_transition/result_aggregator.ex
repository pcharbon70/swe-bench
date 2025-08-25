defmodule SweBench.TestTransition.ResultAggregator do
  @moduledoc """
  Aggregates and processes test transition validation results.

  Collects validation results from workers, maintains quality statistics,
  and provides comprehensive reporting for validation operations.
  """

  use GenServer
  require Logger

  defstruct [
    :total_validations,
    :validations_by_quality,
    :consistency_distribution,
    :processing_stats,
    :start_time
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records validation results from a completed validation.
  """
  def record_results(validation_id, results) do
    GenServer.cast(__MODULE__, {:record_results, validation_id, results})
  end

  @doc """
  Gets current aggregation statistics.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      total_validations: 0,
      validations_by_quality: %{gold: 0, silver: 0, bronze: 0, unsuitable: 0},
      consistency_distribution: %{high: 0, medium: 0, low: 0},
      processing_stats: %{},
      start_time: DateTime.utc_now()
    }

    Logger.info("Validation result aggregator started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_results, validation_id, results}, state) do
    Logger.debug("Recording results for validation #{validation_id}")

    updated_state =
      state
      |> update_total_validations()
      |> update_quality_statistics(results)
      |> update_consistency_distribution(results)
      |> update_processing_statistics(validation_id, results)

    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    stats = %{
      total_validations: state.total_validations,
      validations_by_quality: state.validations_by_quality,
      consistency_distribution: state.consistency_distribution,
      processing_rate: calculate_processing_rate(state, uptime_seconds),
      uptime_seconds: uptime_seconds,
      avg_processing_time: calculate_avg_processing_time(state)
    }

    {:reply, stats, state}
  end

  # Private helper functions

  defp update_total_validations(state) do
    %{state | total_validations: state.total_validations + 1}
  end

  defp update_quality_statistics(state, results) do
    quality_tier = results.benchmark_quality
    current_count = Map.get(state.validations_by_quality, quality_tier, 0)
    updated_quality = Map.put(state.validations_by_quality, quality_tier, current_count + 1)

    %{state | validations_by_quality: updated_quality}
  end

  defp update_consistency_distribution(state, results) do
    consistency_level = classify_consistency_level(results.consistency_score)
    current_count = Map.get(state.consistency_distribution, consistency_level, 0)
    updated_distribution = Map.put(state.consistency_distribution, consistency_level, current_count + 1)

    %{state | consistency_distribution: updated_distribution}
  end

  defp classify_consistency_level(consistency_score) do
    cond do
      consistency_score >= 0.90 -> :high
      consistency_score >= 0.70 -> :medium
      true -> :low
    end
  end

  defp update_processing_statistics(state, validation_id, results) do
    processing_stats = %{
      validation_id: validation_id,
      benchmark_quality: results.benchmark_quality,
      processing_time_ms: results.processing_time_ms,
      fail_to_pass_count: Map.get(results, :fail_to_pass_count, 0),
      consistency_score: results.consistency_score,
      completed_at: DateTime.utc_now()
    }

    updated_stats = Map.put(state.processing_stats, validation_id, processing_stats)
    %{state | processing_stats: updated_stats}
  end

  defp calculate_processing_rate(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_validations / hours
  end

  defp calculate_processing_rate(_state, _uptime_seconds), do: 0.0

  defp calculate_avg_processing_time(state) do
    if map_size(state.processing_stats) > 0 do
      total_time =
        state.processing_stats
        |> Map.values()
        |> Enum.map(&Map.get(&1, :processing_time_ms, 0))
        |> Enum.sum()

      total_time / map_size(state.processing_stats)
    else
      0.0
    end
  end
end