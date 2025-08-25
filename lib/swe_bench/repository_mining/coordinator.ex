defmodule SweBench.RepositoryMining.Coordinator do
  @moduledoc """
  Coordinates repository mining operations and manages worker lifecycle.

  Handles mining job queue, worker supervision, progress tracking, and
  integration with the broader SWE-bench evaluation pipeline.
  """

  use GenServer
  require Logger

  alias SweBench.Repositories.{MiningJob, Repository}
  alias SweBench.RepositoryMining.{Worker, WorkerSupervisor}

  defstruct [
    :max_workers,
    :active_workers,
    :pending_jobs,
    :completed_jobs,
    :failed_jobs,
    :start_time,
    :total_repositories_discovered
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queues a new repository mining job.
  """
  def queue_mining_job(source, params) do
    GenServer.call(__MODULE__, {:queue_job, source, params})
  end

  @doc """
  Gets current mining status and statistics.
  """
  def get_mining_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets repository quality distribution statistics.
  """
  def get_quality_distribution do
    GenServer.call(__MODULE__, :get_quality_distribution)
  end

  @doc """
  Forces processing of pending jobs (useful for testing).
  """
  def process_pending_jobs do
    GenServer.cast(__MODULE__, :process_pending_jobs)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online() * 2)

    state = %__MODULE__{
      max_workers: max_workers,
      active_workers: %{},
      pending_jobs: [],
      completed_jobs: [],
      failed_jobs: [],
      start_time: DateTime.utc_now(),
      total_repositories_discovered: 0
    }

    # Schedule periodic job processing
    schedule_job_processing()

    Logger.info("Mining coordinator started with #{max_workers} max workers")
    {:ok, state}
  end

  @impl true
  def handle_call({:queue_job, source, params}, _from, state) do
    case create_mining_job(source, params) do
      {:ok, job} ->
        updated_state = %{state | pending_jobs: [job | state.pending_jobs]}
        send(self(), :process_pending_jobs)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error("Failed to create mining job: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    status = %{
      active_workers: map_size(state.active_workers),
      max_workers: state.max_workers,
      pending_jobs: length(state.pending_jobs),
      completed_jobs: length(state.completed_jobs),
      failed_jobs: length(state.failed_jobs),
      total_repositories_discovered: state.total_repositories_discovered,
      uptime_seconds: uptime_seconds,
      throughput_per_hour: calculate_throughput_per_hour(state, uptime_seconds)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_quality_distribution, _from, state) do
    distribution = calculate_quality_distribution()
    {:reply, distribution, state}
  end

  @impl true
  def handle_cast(:process_pending_jobs, state) do
    updated_state = start_available_workers(state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_pending_jobs, state) do
    updated_state = start_available_workers(state)
    schedule_job_processing()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_completed, worker_pid, job_id, result}, state) do
    Logger.info("Mining job #{job_id} completed: #{result.repositories_discovered} repositories discovered")

    updated_state =
      state
      |> update_worker_completion(worker_pid, job_id, result)
      |> update_repository_totals(result)

    # Trigger next job processing
    send(self(), :process_pending_jobs)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_failed, worker_pid, job_id, reason}, state) do
    Logger.error("Mining job #{job_id} failed: #{inspect(reason)}")

    updated_state = update_worker_failure(state, worker_pid, job_id, reason)

    # Trigger next job processing
    send(self(), :process_pending_jobs)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp create_mining_job(source, params) do
    attrs = %{
      source: source,
      query_params: params,
      max_repositories: Map.get(params, :max_repositories, 100),
      priority: Map.get(params, :priority, 5)
    }

    MiningJob
    |> Ash.Changeset.for_create(:queue_mining, attrs)
    |> Ash.create()
  end

  defp start_available_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not Enum.empty?(state.pending_jobs) do
      {jobs_to_start, remaining_jobs} = Enum.split(state.pending_jobs, available_slots)

      new_workers =
        jobs_to_start
        |> Enum.map(&start_mining_worker/1)
        |> Enum.into(%{})

      %{
        state
        | active_workers: Map.merge(state.active_workers, new_workers),
          pending_jobs: remaining_jobs
      }
    else
      state
    end
  end

  defp start_mining_worker(job) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        WorkerSupervisor,
        {Worker, [job: job, coordinator: self()]}
      )

    {pid, job.id}
  end

  defp update_worker_completion(state, worker_pid, job_id, result) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)
    completed_job = %{id: job_id, result: result, completed_at: DateTime.utc_now()}

    %{
      state
      | active_workers: new_active_workers,
        completed_jobs: [completed_job | state.completed_jobs]
    }
  end

  defp update_worker_failure(state, worker_pid, job_id, reason) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)
    failed_job = %{id: job_id, reason: reason, failed_at: DateTime.utc_now()}

    %{
      state
      | active_workers: new_active_workers,
        failed_jobs: [failed_job | state.failed_jobs]
    }
  end

  defp update_repository_totals(state, result) do
    new_total = state.total_repositories_discovered + result.repositories_discovered

    %{state | total_repositories_discovered: new_total}
  end

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_repositories_discovered / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp calculate_quality_distribution do
    # Query existing repositories for quality distribution
    # This will be implemented once quality metrics are available
    %{
      excellent: 0,
      good: 0,
      average: 0,
      below_average: 0,
      poor: 0,
      total: 0
    }
  end

  defp schedule_job_processing do
    # 5 seconds between job processing cycles
    Process.send_after(self(), :process_pending_jobs, 5_000)
  end
end
