defmodule SweBench.HotUpgrade.UpgradeCoordinator do
  @moduledoc """
  Coordinates hot upgrade evaluation operations and manages workflow.

  Handles upgrade scenario evaluation, state migration testing, and integration
  with distributed infrastructure for comprehensive upgrade assessment.
  """

  use GenServer
  require Logger

  defstruct [
    :max_concurrent,
    :active_evaluations,
    :completed_evaluations,
    :failed_evaluations,
    :start_time,
    :upgrade_statistics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Evaluates an upgrade scenario for a task instance.
  """
  def evaluate_upgrade(task_instance_id, upgrade_spec) do
    GenServer.call(__MODULE__, {:evaluate_upgrade, task_instance_id, upgrade_spec}, 300_000)
  end

  @doc """
  Gets upgrade evaluation statistics.
  """
  def get_upgrade_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Forces processing of pending evaluations.
  """
  def process_pending_evaluations do
    GenServer.cast(__MODULE__, :process_pending)
  end

  @impl true
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 3)

    state = %__MODULE__{
      max_concurrent: max_concurrent,
      active_evaluations: %{},
      completed_evaluations: [],
      failed_evaluations: [],
      start_time: DateTime.utc_now(),
      upgrade_statistics: %{
        total_evaluations: 0,
        successful_evaluations: 0,
        state_preservation_avg: 0.0,
        zero_downtime_rate: 0.0
      }
    }

    Logger.info("Hot upgrade coordinator started with #{max_concurrent} max concurrent evaluations")
    {:ok, state}
  end

  @impl true
  def handle_call({:evaluate_upgrade, task_instance_id, upgrade_spec}, _from, state) do
    evaluation_id = generate_evaluation_id()
    Logger.info("Starting upgrade evaluation #{evaluation_id} for task #{task_instance_id}")

    case start_upgrade_evaluation(evaluation_id, task_instance_id, upgrade_spec) do
      {:ok, worker_pid} ->
        evaluation_info = %{
          id: evaluation_id,
          task_instance_id: task_instance_id,
          upgrade_spec: upgrade_spec,
          worker_pid: worker_pid,
          started_at: DateTime.utc_now()
        }

        updated_state = %{
          state
          | active_evaluations: Map.put(state.active_evaluations, evaluation_id, evaluation_info)
        }

        {:reply, {:ok, evaluation_id}, updated_state}

      {:error, reason} ->
        Logger.error("Failed to start upgrade evaluation: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)

    statistics = %{
      uptime_seconds: uptime_seconds,
      max_concurrent: state.max_concurrent,
      active_evaluations: map_size(state.active_evaluations),
      completed_evaluations: length(state.completed_evaluations),
      failed_evaluations: length(state.failed_evaluations),
      upgrade_statistics: state.upgrade_statistics,
      throughput_per_hour: calculate_throughput_per_hour(state, uptime_seconds)
    }

    {:reply, statistics, state}
  end

  @impl true
  def handle_cast(:process_pending, state) do
    # Placeholder for processing pending evaluations
    {:noreply, state}
  end

  @impl true
  def handle_info({:evaluation_completed, evaluation_id, result}, state) do
    Logger.info("Upgrade evaluation #{evaluation_id} completed")

    case Map.pop(state.active_evaluations, evaluation_id) do
      {nil, _} ->
        {:noreply, state}

      {evaluation_info, remaining_evaluations} ->
        completed_evaluation = Map.merge(evaluation_info, %{
          result: result,
          completed_at: DateTime.utc_now()
        })

        updated_statistics = update_upgrade_statistics(state.upgrade_statistics, result)

        updated_state = %{
          state
          | active_evaluations: remaining_evaluations,
            completed_evaluations: [completed_evaluation | state.completed_evaluations],
            upgrade_statistics: updated_statistics
        }

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:evaluation_failed, evaluation_id, reason}, state) do
    Logger.error("Upgrade evaluation #{evaluation_id} failed: #{inspect(reason)}")

    case Map.pop(state.active_evaluations, evaluation_id) do
      {nil, _} ->
        {:noreply, state}

      {evaluation_info, remaining_evaluations} ->
        failed_evaluation = Map.merge(evaluation_info, %{
          error: reason,
          failed_at: DateTime.utc_now()
        })

        updated_state = %{
          state
          | active_evaluations: remaining_evaluations,
            failed_evaluations: [failed_evaluation | state.failed_evaluations]
        }

        {:noreply, updated_state}
    end
  end

  # Private implementation functions

  defp start_upgrade_evaluation(evaluation_id, task_instance_id, upgrade_spec) do
    worker_spec = {
      SweBench.HotUpgrade.EvaluationWorker,
      [
        evaluation_id: evaluation_id,
        task_instance_id: task_instance_id,
        upgrade_spec: upgrade_spec,
        coordinator: self()
      ]
    }

    case DynamicSupervisor.start_child(SweBench.HotUpgrade.WorkerSupervisor, worker_spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_upgrade_statistics(current_stats, evaluation_result) do
    new_total = current_stats.total_evaluations + 1

    new_successful =
      if evaluation_result.success do
        current_stats.successful_evaluations + 1
      else
        current_stats.successful_evaluations
      end

    # Update state preservation average
    new_state_preservation_avg =
      if new_total > 1 do
        ((current_stats.state_preservation_avg * (new_total - 1)) + 
         evaluation_result.state_preservation) / new_total
      else
        evaluation_result.state_preservation
      end

    # Update zero-downtime rate
    new_zero_downtime_rate =
      if evaluation_result.downtime_ms == 0 do
        new_successful / new_total
      else
        current_stats.zero_downtime_rate
      end

    %{
      current_stats
      | total_evaluations: new_total,
        successful_evaluations: new_successful,
        state_preservation_avg: new_state_preservation_avg,
        zero_downtime_rate: new_zero_downtime_rate
    }
  end

  defp calculate_throughput_per_hour(state, uptime_seconds) when uptime_seconds > 0 do
    hours = uptime_seconds / 3600
    total_completed = length(state.completed_evaluations) + length(state.failed_evaluations)
    total_completed / hours
  end

  defp calculate_throughput_per_hour(_state, _uptime_seconds), do: 0.0

  defp generate_evaluation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end