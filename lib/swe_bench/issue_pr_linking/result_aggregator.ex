defmodule SweBench.IssuePrLinking.ResultAggregator do
  @moduledoc """
  Aggregates and processes Issue-PR correlation results.

  Collects correlation results from workers, maintains statistics, and provides
  comprehensive reporting for the Issue-PR linking infrastructure.
  """

  use GenServer
  require Logger

  defstruct [
    :total_repositories_processed,
    :total_correlations_found,
    :correlations_by_type,
    :quality_distribution,
    :processing_stats,
    :start_time
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records correlation results from a completed analysis.
  """
  def record_results(repository_id, results) do
    GenServer.cast(__MODULE__, {:record_results, repository_id, results})
  end

  @doc """
  Gets current aggregation statistics.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Gets quality distribution for all processed repositories.
  """
  def get_quality_distribution do
    GenServer.call(__MODULE__, :get_quality_distribution)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      total_repositories_processed: 0,
      total_correlations_found: 0,
      correlations_by_type: %{},
      quality_distribution: %{},
      processing_stats: %{},
      start_time: DateTime.utc_now()
    }

    Logger.info("Result aggregator started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_results, repository_id, results}, state) do
    Logger.debug("Recording results for repository #{repository_id}: #{results.correlations_found} correlations")

    updated_state =
      state
      |> update_repository_count()
      |> update_correlation_totals(results)
      |> update_type_statistics(results)
      |> update_quality_distribution(results)
      |> update_processing_statistics(repository_id, results)

    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    stats = %{
      total_repositories_processed: state.total_repositories_processed,
      total_correlations_found: state.total_correlations_found,
      correlations_by_type: state.correlations_by_type,
      quality_distribution: state.quality_distribution,
      processing_rate: calculate_processing_rate(state, uptime_seconds),
      uptime_seconds: uptime_seconds,
      avg_correlations_per_repository: calculate_avg_correlations_per_repo(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_quality_distribution, _from, state) do
    {:reply, state.quality_distribution, state}
  end

  # Private helper functions

  defp update_repository_count(state) do
    %{state | total_repositories_processed: state.total_repositories_processed + 1}
  end

  defp update_correlation_totals(state, results) do
    new_total = state.total_correlations_found + results.correlations_found
    %{state | total_correlations_found: new_total}
  end

  defp update_type_statistics(state, results) do
    # This would be enhanced when we have detailed correlation type data
    # For now, just maintain the existing structure
    state
  end

  defp update_quality_distribution(state, results) do
    current_dist = state.quality_distribution

    updated_dist = %{
      high_confidence: Map.get(current_dist, :high_confidence, 0) + results.high_confidence_count,
      medium_confidence: Map.get(current_dist, :medium_confidence, 0) + results.medium_confidence_count,
      low_confidence: Map.get(current_dist, :low_confidence, 0) + results.low_confidence_count,
      validated: Map.get(current_dist, :validated, 0) + results.auto_validated_count,
      rejected: Map.get(current_dist, :rejected, 0) + results.rejected_count
    }

    %{state | quality_distribution: updated_dist}
  end

  defp update_processing_statistics(state, repository_id, results) do
    repo_stats = %{
      repository_id: repository_id,
      correlations_found: results.correlations_found,
      processing_time_ms: results.processing_time_ms,
      issues_fetched: results.issues_fetched,
      prs_fetched: results.prs_fetched,
      completed_at: DateTime.utc_now()
    }

    updated_stats = Map.put(state.processing_stats, repository_id, repo_stats)
    %{state | processing_stats: updated_stats}
  end

  defp calculate_processing_rate(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_correlations_found / hours
  end

  defp calculate_processing_rate(_state, _uptime_seconds), do: 0.0

  defp calculate_avg_correlations_per_repo(state) do
    if state.total_repositories_processed > 0 do
      state.total_correlations_found / state.total_repositories_processed
    else
      0.0
    end
  end
end