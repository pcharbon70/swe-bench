defmodule SweBench.IssuePrLinking.Coordinator do
  @moduledoc """
  Coordinates Issue-PR correlation operations and manages analysis workflow.

  Handles correlation job queue, worker supervision, progress tracking, and
  integration with the broader SWE-bench evaluation pipeline.
  """

  use GenServer
  require Logger

  alias SweBench.Issues.{Issue, IssuePrLink, PullRequest}
  alias SweBench.Repositories.Repository
  alias SweBench.IssuePrLinking.{Worker, WorkerSupervisor}

  defstruct [
    :max_workers,
    :active_workers,
    :pending_repositories,
    :completed_repositories,
    :failed_repositories,
    :start_time,
    :total_correlations_found,
    :quality_stats
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queues a repository for Issue-PR correlation analysis.
  """
  def analyze_repository(repository_id, opts \\ []) do
    GenServer.call(__MODULE__, {:analyze_repository, repository_id, opts})
  end

  @doc """
  Gets current correlation analysis status and statistics.
  """
  def get_analysis_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets relationship quality distribution for a repository.
  """
  def get_relationship_distribution(repository_id) do
    GenServer.call(__MODULE__, {:get_distribution, repository_id})
  end

  @doc """
  Forces processing of pending repositories (useful for testing).
  """
  def process_pending_repositories do
    GenServer.cast(__MODULE__, :process_pending)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online() * 2)

    state = %__MODULE__{
      max_workers: max_workers,
      active_workers: %{},
      pending_repositories: [],
      completed_repositories: [],
      failed_repositories: [],
      start_time: DateTime.utc_now(),
      total_correlations_found: 0,
      quality_stats: %{
        high_confidence: 0,
        medium_confidence: 0,
        low_confidence: 0,
        validated: 0,
        rejected: 0
      }
    }

    # Schedule periodic repository processing
    schedule_repository_processing()

    Logger.info("Issue-PR linking coordinator started with #{max_workers} max workers")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_repository, repository_id, opts}, _from, state) do
    case validate_repository_for_analysis(repository_id) do
      {:ok, repository} ->
        job = create_correlation_job(repository, opts)
        updated_state = %{state | pending_repositories: [job | state.pending_repositories]}
        send(self(), :process_pending)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error(
          "Failed to queue repository #{repository_id} for analysis: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    status = %{
      active_workers: map_size(state.active_workers),
      max_workers: state.max_workers,
      pending_repositories: length(state.pending_repositories),
      completed_repositories: length(state.completed_repositories),
      failed_repositories: length(state.failed_repositories),
      total_correlations_found: state.total_correlations_found,
      quality_stats: state.quality_stats,
      uptime_seconds: uptime_seconds,
      throughput_per_hour: calculate_throughput_per_hour(state, uptime_seconds)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:get_distribution, repository_id}, _from, state) do
    distribution = calculate_relationship_distribution(repository_id)
    {:reply, distribution, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    updated_state = start_available_workers(state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    updated_state = start_available_workers(state)
    schedule_repository_processing()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_completed, worker_pid, repository_id, result}, state) do
    Logger.info(
      "Correlation analysis completed for repository #{repository_id}: #{result.correlations_found} relationships found"
    )

    updated_state =
      state
      |> update_worker_completion(worker_pid, repository_id, result)
      |> update_correlation_totals(result)
      |> update_quality_statistics(result)

    # Trigger next repository processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_failed, worker_pid, repository_id, reason}, state) do
    Logger.error(
      "Correlation analysis failed for repository #{repository_id}: #{inspect(reason)}"
    )

    updated_state = update_worker_failure(state, worker_pid, repository_id, reason)

    # Trigger next repository processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp validate_repository_for_analysis(repository_id) do
    case Ash.get(Repository, repository_id) do
      {:ok, repository} ->
        case repository.mining_status do
          :completed ->
            {:ok, repository}

          status ->
            {:error, {:repository_not_ready, status}}
        end

      {:error, reason} ->
        {:error, {:repository_not_found, reason}}
    end
  end

  defp create_correlation_job(repository, opts) do
    %{
      id: Ash.UUID.generate(),
      repository_id: repository.id,
      repository_name: repository.full_name,
      priority: Keyword.get(opts, :priority, 5),
      correlation_strategies: Keyword.get(opts, :strategies, [:all]),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.6),
      max_correlations: Keyword.get(opts, :max_correlations, 1000),
      created_at: DateTime.utc_now()
    }
  end

  defp start_available_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not Enum.empty?(state.pending_repositories) do
      {jobs_to_start, remaining_jobs} = Enum.split(state.pending_repositories, available_slots)

      new_workers =
        jobs_to_start
        |> Enum.map(&start_correlation_worker/1)
        |> Enum.into(%{})

      %{
        state
        | active_workers: Map.merge(state.active_workers, new_workers),
          pending_repositories: remaining_jobs
      }
    else
      state
    end
  end

  defp start_correlation_worker(job) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        WorkerSupervisor,
        {Worker, [job: job, coordinator: self()]}
      )

    {pid, job.id}
  end

  defp update_worker_completion(state, worker_pid, repository_id, result) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    completed_job = %{
      repository_id: repository_id,
      result: result,
      completed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        completed_repositories: [completed_job | state.completed_repositories]
    }
  end

  defp update_worker_failure(state, worker_pid, repository_id, reason) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    failed_job = %{
      repository_id: repository_id,
      reason: reason,
      failed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        failed_repositories: [failed_job | state.failed_repositories]
    }
  end

  defp update_correlation_totals(state, result) do
    new_total = state.total_correlations_found + result.correlations_found

    %{state | total_correlations_found: new_total}
  end

  defp update_quality_statistics(state, result) do
    quality_updates = %{
      high_confidence: state.quality_stats.high_confidence + result.high_confidence_count,
      medium_confidence: state.quality_stats.medium_confidence + result.medium_confidence_count,
      low_confidence: state.quality_stats.low_confidence + result.low_confidence_count,
      validated: state.quality_stats.validated + result.auto_validated_count,
      rejected: state.quality_stats.rejected + result.rejected_count
    }

    %{state | quality_stats: quality_updates}
  end

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_correlations_found / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp calculate_relationship_distribution(repository_id) do
    # Query relationship distribution using Ash queries
    links =
      IssuePrLink
      |> Ash.Query.for_read(:by_repository, %{repository_id: repository_id})
      |> Ash.read!()

    links
    |> Enum.group_by(& &1.validation_status)
    |> Enum.map(fn {status, group} ->
      {status,
       %{
         count: length(group),
         avg_confidence: calculate_average_confidence(group),
         quality_distribution: group_by_quality_tier(group)
       }}
    end)
    |> Map.new()
  end

  defp calculate_average_confidence([]), do: 0.0

  defp calculate_average_confidence(links) do
    total_confidence = Enum.sum(Enum.map(links, & &1.confidence_score))
    total_confidence / length(links)
  end

  defp group_by_quality_tier(links) do
    links
    |> Enum.group_by(fn link ->
      cond do
        link.confidence_score >= 0.9 -> :excellent
        link.confidence_score >= 0.8 -> :high
        link.confidence_score >= 0.7 -> :good
        link.confidence_score >= 0.6 -> :medium
        true -> :low
      end
    end)
    |> Enum.map(fn {tier, group} -> {tier, length(group)} end)
    |> Map.new()
  end

  defp schedule_repository_processing do
    # 10 seconds between repository processing cycles
    Process.send_after(self(), :process_pending, 10_000)
  end
end
