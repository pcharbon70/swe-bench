defmodule SweBench.RepositoryMining.ResultAggregator do
  @moduledoc """
  Aggregates and processes repository mining results.

  Collects mining results from workers, maintains statistics, and provides
  reporting capabilities for the mining infrastructure.
  """

  use GenServer
  require Logger

  defstruct [
    :total_repositories,
    :repositories_by_source,
    :quality_distribution,
    :processing_stats,
    :start_time
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records mining results from a completed job.
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
      total_repositories: 0,
      repositories_by_source: %{},
      quality_distribution: %{},
      processing_stats: %{},
      start_time: DateTime.utc_now()
    }

    Logger.info("Result aggregator started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_results, job_id, results}, state) do
    Logger.debug("Recording results for job #{job_id}: #{results.repositories_discovered} repositories")

    updated_state =
      state
      |> update_total_repositories(results.repositories_discovered)
      |> update_source_statistics(results.discovery_source, results.repositories_discovered)
      |> update_processing_stats(job_id, results)

    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    stats = %{
      total_repositories: state.total_repositories,
      repositories_by_source: state.repositories_by_source,
      quality_distribution: state.quality_distribution,
      processing_rate: calculate_processing_rate(state.total_repositories, uptime_seconds),
      uptime_seconds: uptime_seconds,
      processing_stats: state.processing_stats
    }

    {:reply, stats, state}
  end

  # Private helper functions

  defp update_total_repositories(state, count) do
    %{state | total_repositories: state.total_repositories + count}
  end

  defp update_source_statistics(state, source, count) do
    updated_by_source =
      Map.update(state.repositories_by_source, source, count, &(&1 + count))

    %{state | repositories_by_source: updated_by_source}
  end

  defp update_processing_stats(state, job_id, results) do
    job_stats = %{
      repositories_discovered: results.repositories_discovered,
      processing_time_ms: results.processing_time_ms,
      completed_at: DateTime.utc_now()
    }

    updated_stats = Map.put(state.processing_stats, job_id, job_stats)

    %{state | processing_stats: updated_stats}
  end

  defp calculate_processing_rate(total_repositories, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    total_repositories / hours
  end

  defp calculate_processing_rate(_, _), do: 0.0
end
