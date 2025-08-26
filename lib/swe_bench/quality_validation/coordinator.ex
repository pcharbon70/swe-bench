defmodule SweBench.QualityValidation.Coordinator do
  @moduledoc """
  Coordinates quality validation operations and manages workflow.

  Handles quality validation job queue, worker supervision, progress tracking,
  and integration with the complete Phase 3 data collection pipeline.
  """

  use GenServer
  require Logger

  alias SweBench.QualityAssurance.{QualityValidation, ReviewSession}
  alias SweBench.TaskInstances.TaskInstance
  alias SweBench.QualityValidation.{Worker, WorkerSupervisor}

  defstruct [
    :max_workers,
    :active_workers,
    :pending_validations,
    :completed_validations,
    :failed_validations,
    :start_time,
    :total_validations_completed,
    :quality_statistics
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validates quality for a task instance.
  """
  def validate_quality(task_instance_id, opts \\ []) do
    GenServer.call(__MODULE__, {:validate_quality, task_instance_id, opts})
  end

  @doc """
  Validates multiple task instances in batch.
  """
  def validate_batch(task_instance_ids, opts \\ []) do
    GenServer.call(__MODULE__, {:validate_batch, task_instance_ids, opts})
  end

  @doc """
  Gets current validation status and statistics.
  """
  def get_validation_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets quality statistics and distribution metrics.
  """
  def get_quality_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Gets deduplication results for task instances.
  """
  def get_deduplication_results(repository_id) do
    GenServer.call(__MODULE__, {:get_deduplication_results, repository_id})
  end

  @doc """
  Assigns task instances for human review.
  """
  def assign_for_human_review(task_instance_ids, reviewer_ids) do
    GenServer.call(__MODULE__, {:assign_for_review, task_instance_ids, reviewer_ids})
  end

  @doc """
  Forces processing of pending validations.
  """
  def process_pending_validations do
    GenServer.cast(__MODULE__, :process_pending)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online())

    state = %__MODULE__{
      max_workers: max_workers,
      active_workers: %{},
      pending_validations: [],
      completed_validations: [],
      failed_validations: [],
      start_time: DateTime.utc_now(),
      total_validations_completed: 0,
      quality_statistics: %{
        automated_validations: 0,
        statistical_analyses: 0,
        deduplication_checks: 0,
        human_reviews: 0,
        avg_quality_score: 0.0
      }
    }

    # Schedule periodic validation processing
    schedule_validation_processing()

    Logger.info("Quality validation coordinator started with #{max_workers} max workers")
    {:ok, state}
  end

  @impl true
  def handle_call({:validate_quality, task_instance_id, opts}, _from, state) do
    case validate_task_instance_for_quality_validation(task_instance_id) do
      {:ok, task_instance} ->
        job = create_validation_job(task_instance, opts)
        updated_state = %{state | pending_validations: [job | state.pending_validations]}
        send(self(), :process_pending)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error(
          "Failed to queue quality validation for task #{task_instance_id}: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:validate_batch, task_instance_ids, opts}, _from, state) do
    jobs =
      task_instance_ids
      |> Enum.map(fn id ->
        case validate_task_instance_for_quality_validation(id) do
          {:ok, task_instance} -> create_validation_job(task_instance, opts)
          {:error, _reason} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    updated_state = %{state | pending_validations: jobs ++ state.pending_validations}
    send(self(), :process_pending)

    {:reply, {:ok, %{queued: length(jobs), failed: length(task_instance_ids) - length(jobs)}},
     updated_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    status = %{
      active_workers: map_size(state.active_workers),
      max_workers: state.max_workers,
      pending_validations: length(state.pending_validations),
      completed_validations: length(state.completed_validations),
      failed_validations: length(state.failed_validations),
      total_validations_completed: state.total_validations_completed,
      quality_statistics: state.quality_statistics,
      uptime_seconds: uptime_seconds,
      throughput_per_hour: calculate_throughput_per_hour(state, uptime_seconds)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, state.quality_statistics, state}
  end

  @impl true
  def handle_call({:get_deduplication_results, repository_id}, _from, state) do
    # Placeholder - will query deduplication results
    results = get_deduplication_data(repository_id)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:assign_for_review, task_instance_ids, reviewer_ids}, _from, state) do
    # Placeholder - will implement review assignment
    assignment_result = assign_review_tasks(task_instance_ids, reviewer_ids)
    {:reply, assignment_result, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    updated_state = start_available_workers(state)
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_pending, state) do
    updated_state = start_available_workers(state)
    schedule_validation_processing()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_completed, worker_pid, validation_id, result}, state) do
    Logger.info(
      "Quality validation #{validation_id} completed: Quality score #{result.quality_score}"
    )

    updated_state =
      state
      |> update_worker_completion(worker_pid, validation_id, result)
      |> update_validation_totals(result)
      |> update_quality_statistics(result)

    # Trigger next validation processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:worker_failed, worker_pid, validation_id, reason}, state) do
    Logger.error("Quality validation #{validation_id} failed: #{inspect(reason)}")

    updated_state = update_worker_failure(state, worker_pid, validation_id, reason)

    # Trigger next validation processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp validate_task_instance_for_quality_validation(task_instance_id) do
    case Ash.get(TaskInstance, task_instance_id) do
      {:ok, task_instance} ->
        case task_instance.packaging_status do
          :ready ->
            {:ok, task_instance}

          status ->
            {:error, {:task_not_ready, status}}
        end

      {:error, reason} ->
        {:error, {:task_not_found, reason}}
    end
  end

  defp create_validation_job(task_instance, opts) do
    %{
      id: Ash.UUID.generate(),
      task_instance_id: task_instance.id,
      validation_stages: Keyword.get(opts, :stages, [:automated, :statistical, :deduplication]),
      quality_threshold: Keyword.get(opts, :quality_threshold, 0.8),
      include_human_review: Keyword.get(opts, :include_human_review, false),
      priority: Keyword.get(opts, :priority, 5),
      created_at: DateTime.utc_now()
    }
  end

  defp start_available_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not Enum.empty?(state.pending_validations) do
      {jobs_to_start, remaining_jobs} = Enum.split(state.pending_validations, available_slots)

      new_workers =
        jobs_to_start
        |> Enum.map(&start_validation_worker/1)
        |> Enum.into(%{})

      %{
        state
        | active_workers: Map.merge(state.active_workers, new_workers),
          pending_validations: remaining_jobs
      }
    else
      state
    end
  end

  defp start_validation_worker(job) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        WorkerSupervisor,
        {Worker, [job: job, coordinator: self()]}
      )

    {pid, job.id}
  end

  defp update_worker_completion(state, worker_pid, validation_id, result) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    completed_job = %{
      validation_id: validation_id,
      result: result,
      completed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        completed_validations: [completed_job | state.completed_validations]
    }
  end

  defp update_worker_failure(state, worker_pid, validation_id, reason) do
    new_active_workers = Map.delete(state.active_workers, worker_pid)

    failed_job = %{
      validation_id: validation_id,
      reason: reason,
      failed_at: DateTime.utc_now()
    }

    %{
      state
      | active_workers: new_active_workers,
        failed_validations: [failed_job | state.failed_validations]
    }
  end

  defp update_validation_totals(state, result) do
    new_total = state.total_validations_completed + 1
    %{state | total_validations_completed: new_total}
  end

  defp update_quality_statistics(state, result) do
    current_stats = state.quality_statistics

    # Update running averages and counts
    updated_stats = %{
      automated_validations: current_stats.automated_validations + 1,
      statistical_analyses:
        current_stats.statistical_analyses + Map.get(result, :statistical_count, 0),
      deduplication_checks:
        current_stats.deduplication_checks + Map.get(result, :deduplication_count, 0),
      human_reviews: current_stats.human_reviews + Map.get(result, :human_review_count, 0),
      avg_quality_score:
        update_running_average(
          current_stats.avg_quality_score,
          result.quality_score,
          current_stats.automated_validations + 1
        )
    }

    %{state | quality_statistics: updated_stats}
  end

  defp update_running_average(current_avg, new_value, count) when count > 1 do
    (current_avg * (count - 1) + new_value) / count
  end

  defp update_running_average(_current_avg, new_value, _count), do: new_value

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_validations_completed / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp get_deduplication_data(_repository_id) do
    # Placeholder - will query actual deduplication results
    %{similar_pairs: [], duplicate_count: 0, recommendation: :no_action}
  end

  defp assign_review_tasks(_task_instance_ids, _reviewer_ids) do
    # Placeholder - will implement review assignment logic
    {:ok, %{assigned: 0, failed: 0}}
  end

  defp schedule_validation_processing do
    # 30 seconds between validation processing cycles (longer due to complexity)
    Process.send_after(self(), :process_pending, 30_000)
  end
end

