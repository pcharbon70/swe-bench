defmodule SweBench.TestTransition.Coordinator do
  @moduledoc """
  Coordinates test transition validation operations and manages workflow.

  Handles validation job queue, worker supervision, progress tracking, and
  integration with container pool and existing pipeline infrastructure.
  """

  use GenServer
  require Logger

  alias SweBench.Issues.IssuePrLink
  alias SweBench.ValidationResults.ValidationResult
  alias SweBench.TestTransition.{Worker, WorkerSupervisor}

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
  Validates test transitions for an issue-PR pair.
  """
  def validate_transitions(issue_pr_link_id, opts \\ []) do
    GenServer.call(__MODULE__, {:validate_transitions, issue_pr_link_id, opts})
  end

  @doc """
  Validates multiple issue-PR pairs in batch.
  """
  def validate_batch(issue_pr_link_ids, opts \\ []) do
    GenServer.call(__MODULE__, {:validate_batch, issue_pr_link_ids, opts})
  end

  @doc """
  Gets current validation status and statistics.
  """
  def get_validation_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets validation quality distribution.
  """
  def get_quality_distribution do
    GenServer.call(__MODULE__, :get_quality_distribution)
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
        gold: 0,
        silver: 0,
        bronze: 0,
        unsuitable: 0
      }
    }

    # Schedule periodic validation processing
    schedule_validation_processing()

    Logger.info("Test transition validation coordinator started with #{max_workers} max workers")
    {:ok, state}
  end

  @impl true
  def handle_call({:validate_transitions, issue_pr_link_id, opts}, _from, state) do
    case validate_issue_pr_link_for_validation(issue_pr_link_id) do
      {:ok, issue_pr_link} ->
        job = create_validation_job(issue_pr_link, opts)
        updated_state = %{state | pending_validations: [job | state.pending_validations]}
        send(self(), :process_pending)
        {:reply, {:ok, job}, updated_state}

      {:error, reason} ->
        Logger.error(
          "Failed to queue validation for issue-PR link #{issue_pr_link_id}: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:validate_batch, issue_pr_link_ids, opts}, _from, state) do
    jobs =
      issue_pr_link_ids
      |> Enum.map(fn id ->
        case validate_issue_pr_link_for_validation(id) do
          {:ok, issue_pr_link} -> create_validation_job(issue_pr_link, opts)
          {:error, _reason} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    updated_state = %{state | pending_validations: jobs ++ state.pending_validations}
    send(self(), :process_pending)

    {:reply, {:ok, %{queued: length(jobs), failed: length(issue_pr_link_ids) - length(jobs)}},
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
  def handle_call(:get_quality_distribution, _from, state) do
    {:reply, state.quality_statistics, state}
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
      "Validation completed for #{validation_id}: Quality tier #{result.benchmark_quality}"
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
    Logger.error("Validation failed for #{validation_id}: #{inspect(reason)}")

    updated_state = update_worker_failure(state, worker_pid, validation_id, reason)

    # Trigger next validation processing
    send(self(), :process_pending)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp validate_issue_pr_link_for_validation(issue_pr_link_id) do
    case Ash.get(IssuePrLink, issue_pr_link_id) do
      {:ok, issue_pr_link} ->
        case issue_pr_link.validation_status do
          :validated ->
            {:ok, issue_pr_link}

          status ->
            {:error, {:link_not_validated, status}}
        end

      {:error, reason} ->
        {:error, {:link_not_found, reason}}
    end
  end

  defp create_validation_job(issue_pr_link, opts) do
    %{
      id: Ash.UUID.generate(),
      issue_pr_link_id: issue_pr_link.id,
      repository_id: issue_pr_link.repository_id,
      priority: Keyword.get(opts, :priority, 5),
      validation_runs: Keyword.get(opts, :validation_runs, 3),
      timeout: Keyword.get(opts, :timeout, 600_000),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.8),
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

  defp update_validation_totals(state, _result) do
    new_total = state.total_validations_completed + 1
    %{state | total_validations_completed: new_total}
  end

  defp update_quality_statistics(state, result) do
    quality_tier = result.benchmark_quality
    current_count = Map.get(state.quality_statistics, quality_tier, 0)
    updated_stats = Map.put(state.quality_statistics, quality_tier, current_count + 1)

    %{state | quality_statistics: updated_stats}
  end

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    state.total_validations_completed / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp schedule_validation_processing do
    # 15 seconds between validation processing cycles (longer than mining due to complexity)
    Process.send_after(self(), :process_pending, 15_000)
  end
end
