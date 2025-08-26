defmodule SweBench.TaskGeneration.ResultAggregator do
  @moduledoc """
  Aggregates and processes task generation results.

  Collects generation results from workers, maintains statistics, and provides
  comprehensive reporting for task generation operations.
  """

  use GenServer
  require Logger

  defstruct [
    :total_instances,
    :instances_by_quality,
    :instances_by_difficulty,
    :processing_stats,
    :start_time
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records generation results from a completed job.
  """
  def record_results(job_id, results) do
    GenServer.cast(__MODULE__, {:record_results, job_id, results})
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
      total_instances: 0,
      instances_by_quality: %{gold: 0, silver: 0, bronze: 0},
      instances_by_difficulty: %{easy: 0, medium: 0, hard: 0, expert: 0},
      processing_stats: %{},
      start_time: DateTime.utc_now()
    }

    Logger.info("Task generation result aggregator started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_results, job_id, results}, state) do
    Logger.debug("Recording results for job #{job_id}: #{results.instances_generated} instances")

    updated_state =
      state
      |> update_total_instances(results.instances_generated)
      |> update_quality_statistics(results)
      |> update_processing_statistics(job_id, results)

    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    stats = %{
      total_instances: state.total_instances,
      instances_by_quality: state.instances_by_quality,
      instances_by_difficulty: state.instances_by_difficulty,
      processing_rate: calculate_processing_rate(state, uptime_seconds),
      uptime_seconds: uptime_seconds,
      avg_processing_time: calculate_avg_processing_time(state)
    }

    {:reply, stats, state}
  end

  # Private helper functions

  defp update_total_instances(state, count) do
    %{state | total_instances: state.total_instances + count}
  end

  defp update_quality_statistics(state, results) do
    updated_quality = %{
      gold: state.instances_by_quality.gold + Map.get(results, :gold_count, 0),
      silver: state.instances_by_quality.silver + Map.get(results, :silver_count, 0),
      bronze: state.instances_by_quality.bronze + Map.get(results, :bronze_count, 0)
    }

    %{state | instances_by_quality: updated_quality}
  end

  defp update_processing_statistics(state, job_id, results) do
    job_stats = %{
      job_id: job_id,
      instances_generated: results.instances_generated,
      processing_time_ms: results.processing_time_ms,
      quality_distribution: results.quality_distribution,
      completed_at: DateTime.utc_now()
    }

    updated_stats = Map.put(state.processing_stats, job_id, job_stats)
    %{state | processing_stats: updated_stats}
  end

  defp calculate_processing_rate(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_instances / hours
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
