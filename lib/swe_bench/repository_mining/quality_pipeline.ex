defmodule SweBench.RepositoryMining.QualityPipeline do
  @moduledoc """
  Quality assessment pipeline for discovered repositories.

  Coordinates quality analysis operations and manages the quality scoring
  workflow with proper error handling and result persistence.
  """

  use GenServer
  require Logger

  defstruct [
    :pending_quality_assessments,
    :completed_assessments,
    :failed_assessments,
    :processing_stats
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queues a repository for quality assessment.
  """
  def queue_quality_assessment(repository_id) do
    GenServer.cast(__MODULE__, {:queue_assessment, repository_id})
  end

  @doc """
  Gets quality processing statistics.
  """
  def get_processing_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      pending_quality_assessments: [],
      completed_assessments: [],
      failed_assessments: [],
      processing_stats: %{
        total_processed: 0,
        total_failed: 0,
        average_processing_time: 0.0
      }
    }

    # Schedule periodic quality processing
    schedule_quality_processing()

    Logger.info("Quality pipeline started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_assessment, repository_id}, state) do
    updated_pending = [repository_id | state.pending_quality_assessments]
    updated_state = %{state | pending_quality_assessments: updated_pending}

    Logger.debug("Queued quality assessment for repository #{repository_id}")
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_quality_queue, state) do
    updated_state = process_pending_assessments(state)
    schedule_quality_processing()
    {:noreply, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.processing_stats, state}
  end

  # Private implementation functions

  defp process_pending_assessments(state) do
    if Enum.empty?(state.pending_quality_assessments) do
      state
    else
      {current_batch, remaining} = Enum.split(state.pending_quality_assessments, 5)

      batch_results =
        current_batch
        |> Enum.map(&process_single_assessment/1)

      {completed, failed} =
        batch_results
        |> Enum.split_with(&match?({:ok, _}, &1))

      updated_stats = update_processing_stats(state.processing_stats, batch_results)

      %{
        state
        | pending_quality_assessments: remaining,
          completed_assessments: completed ++ state.completed_assessments,
          failed_assessments: failed ++ state.failed_assessments,
          processing_stats: updated_stats
      }
    end
  end

  defp process_single_assessment(repository_id) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case fetch_and_analyze_repository(repository_id) do
        {:ok, _quality_metrics} ->
          processing_time = System.monotonic_time(:millisecond) - start_time

          Logger.debug("Quality assessment completed for repository #{repository_id}")
          {:ok, %{repository_id: repository_id, processing_time: processing_time}}

        {:error, reason} ->
          Logger.warning("Quality assessment failed for repository #{repository_id}: #{inspect(reason)}")
          {:error, %{repository_id: repository_id, reason: reason}}
      end
    rescue
      error ->
        Logger.error("Quality assessment error for repository #{repository_id}: #{inspect(error)}")
        {:error, %{repository_id: repository_id, reason: {:exception, error}}}
    end
  end

  defp fetch_and_analyze_repository(_repository_id) do
    # Placeholder implementation - will be enhanced in Phase 3
    {:ok, %{overall_score: 75.0}}
  end

  defp update_processing_stats(current_stats, batch_results) do
    successful_results = Enum.filter(batch_results, &match?({:ok, _}, &1))
    failed_results = Enum.filter(batch_results, &match?({:error, _}, &1))

    new_total = current_stats.total_processed + length(successful_results)
    new_failed = current_stats.total_failed + length(failed_results)

    processing_times =
      successful_results
      |> Enum.map(fn {:ok, result} -> result.processing_time end)

    new_average =
      if new_total > 0 do
        ((current_stats.average_processing_time * (new_total - length(successful_results))) +
         Enum.sum(processing_times)) / new_total
      else
        0.0
      end

    %{
      total_processed: new_total,
      total_failed: new_failed,
      average_processing_time: new_average
    }
  end

  defp schedule_quality_processing do
    # Process quality queue every 10 seconds
    Process.send_after(self(), :process_quality_queue, 10_000)
  end
end
