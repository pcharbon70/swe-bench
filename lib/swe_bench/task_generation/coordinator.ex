defmodule SweBench.TaskGeneration.Coordinator do
  @moduledoc """
  Coordinates task instance generation operations and manages workflow.

  Handles generation job queue, worker supervision, progress tracking, and
  integration with the broader SWE-bench evaluation pipeline.
  """

  use GenServer
  require Logger

  alias SweBench.TaskInstances.{GenerationJob, TaskInstance}
  alias SweBench.ValidationResults.ValidationResult
  alias SweBench.TaskGeneration.{Worker, WorkerSupervisor}

  defstruct [
    :max_workers,
    :active_workers,
    :pending_jobs,
    :completed_jobs,
    :failed_jobs,
    :start_time,
    :total_instances_generated,
    :generation_statistics
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates task instances from validation results.
  """
  def generate_instances(validation_result_ids, opts \\ []) do
    GenServer.call(__MODULE__, {:generate_instances, validation_result_ids, opts})
  end

  @doc """
  Generates task instances for an entire repository.
  """
  def generate_repository_instances(repository_id, opts \\ []) do
    GenServer.call(__MODULE__, {:generate_repository_instances, repository_id, opts})
  end

  @doc """
  Gets current generation status and statistics.
  """
  def get_generation_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets task generation statistics.
  """
  def get_generation_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Creates a dataset release from generated instances.
  """
  def create_dataset_release(opts \\ []) do
    GenServer.call(__MODULE__, {:create_dataset_release, opts})
  end

  @doc """
  Forces processing of pending jobs (useful for testing).
  """
  def process_pending_jobs do
    GenServer.cast(__MODULE__, :process_pending)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online())

    state = %__MODULE__{
      max_workers: max_workers,
      active_workers: %{},
      pending_jobs: [],
      completed_jobs: [],
      failed_jobs: [],
      start_time: DateTime.utc_now(),
      total_instances_generated: 0,
      generation_statistics: %{
        gold_instances: 0,
        silver_instances: 0,
        bronze_instances: 0,
        total_processing_time: 0
      }
    }

    # Schedule periodic job processing
    schedule_job_processing()

    Logger.info("Task generation coordinator started with #{max_workers} max workers")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_instances, validation_result_ids, opts}, _from, state) do
    case create_generation_job(:validation_results, validation_result_ids, opts) do
      {:ok, job} ->
        updated_state = %{state | pending_jobs: [job | state.pending_jobs]}
        send(self(), :process_pending)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error("Failed to create generation job: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:generate_repository_instances, repository_id, opts}, _from, state) do
    case create_generation_job(:repository_batch, [repository_id], opts) do
      {:ok, job} ->
        updated_state = %{state | pending_jobs: [job | state.pending_jobs]}
        send(self(), :process_pending)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error("Failed to create repository generation job: #{inspect(reason)}")
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
      total_instances_generated: state.total_instances_generated,
      generation_statistics: state.generation_statistics,
      uptime_seconds: uptime_seconds,
      throughput_per_hour: calculate_throughput_per_hour(state, uptime_seconds)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, state.generation_statistics, state}
  end

  @impl true
  def handle_call({:create_dataset_release, opts}, _from, state) do
    # Placeholder for dataset release creation
    release_result = create_dataset_from_instances(opts)
    {:reply, release_result, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    updated_state = start_available_workers(state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    updated_state = start_available_workers(state)
    schedule_job_processing()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_completed, worker_pid, job_id, result}, state) do
    Logger.info(
      "Generation job #{job_id} completed: #{result.instances_generated} instances generated"
    )

    updated_state =
      state
      |> update_worker_completion(worker_pid, job_id, result)
      |> update_generation_totals(result)
      |> update_generation_statistics(result)

    # Trigger next job processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_failed, worker_pid, job_id, reason}, state) do
    Logger.error("Generation job #{job_id} failed: #{inspect(reason)}")

    updated_state = update_worker_failure(state, worker_pid, job_id, reason)

    # Trigger next job processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp create_generation_job(job_type, input_data, opts) do
    attrs = %{
      job_type: job_type,
      input_data: %{items: input_data},
      generation_options: Map.new(opts),
      target_count: Keyword.get(opts, :target_count, length(input_data)),
      priority: Keyword.get(opts, :priority, 5)
    }

    GenerationJob
    |> Ash.Changeset.for_create(:create_job, attrs)
    |> Ash.create()
  end

  defp start_available_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not Enum.empty?(state.pending_jobs) do
      {jobs_to_start, remaining_jobs} = Enum.split(state.pending_jobs, available_slots)

      new_workers =
        jobs_to_start
        |> Enum.map(&start_generation_worker/1)
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

  defp start_generation_worker(job) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        WorkerSupervisor,
        {Worker, [job: job, coordinator: self()]}
      )

    {pid, job.id}
  end

  defp update_worker_completion(state, worker_pid, job_id, result) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    completed_job = %{
      job_id: job_id,
      result: result,
      completed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        completed_jobs: [completed_job | state.completed_jobs]
    }
  end

  defp update_worker_failure(state, worker_pid, job_id, reason) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    failed_job = %{
      job_id: job_id,
      reason: reason,
      failed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        failed_jobs: [failed_job | state.failed_jobs]
    }
  end

  defp update_generation_totals(state, result) do
    new_total = state.total_instances_generated + result.instances_generated
    %{state | total_instances_generated: new_total}
  end

  defp update_generation_statistics(state, result) do
    current_stats = state.generation_statistics

    updated_stats = %{
      gold_instances: current_stats.gold_instances + Map.get(result, :gold_count, 0),
      silver_instances: current_stats.silver_instances + Map.get(result, :silver_count, 0),
      bronze_instances: current_stats.bronze_instances + Map.get(result, :bronze_count, 0),
      total_processing_time: current_stats.total_processing_time + result.processing_time_ms
    }

    %{state | generation_statistics: updated_stats}
  end

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_instances_generated / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp create_dataset_from_instances(opts) do
    # Placeholder for dataset creation - will be implemented in Phase 5
    Logger.debug("Creating dataset release with options: #{inspect(opts)}")
    {:ok, %{version: "1.0.0", instances: 0}}
  end

  defp schedule_job_processing do
    # 20 seconds between job processing cycles (longer due to generation complexity)
    Process.send_after(self(), :process_pending, 20_000)
  end
end
