defmodule SweBench.TaskGeneration.Worker do
  @moduledoc """
  Individual worker process for task instance generation.

  Handles the complete generation workflow from validation results through
  enrichment to final task instance creation with proper error handling.
  """

  use GenServer
  require Logger

  alias SweBench.TaskGeneration.Generator

  defstruct [
    :job,
    :coordinator,
    :start_time,
    :current_operation,
    :instances_generated,
    :instances_failed
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    job = Keyword.fetch!(opts, :job)
    coordinator = Keyword.fetch!(opts, :coordinator)

    state = %__MODULE__{
      job: job,
      coordinator: coordinator,
      start_time: DateTime.utc_now(),
      current_operation: :initializing,
      instances_generated: 0,
      instances_failed: 0
    }

    # Start generation immediately
    send(self(), :start_generation)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_generation, state) do
    Logger.info("Starting generation job #{state.job.id}")

    case execute_generation_pipeline(state) do
      {:ok, results} ->
        complete_generation_job(state, results)

      {:error, reason} ->
        fail_generation_job(state, reason)
    end

    {:stop, :normal, state}
  end

  # Private implementation functions

  defp execute_generation_pipeline(state) do
    state.job.input_data
    |> extract_validation_result_ids()
    |> process_validation_results(state)
    |> compile_generation_results(state)
  rescue
    error ->
      Logger.error("Generation pipeline error for job #{state.job.id}: #{inspect(error)}")
      {:error, {:pipeline_error, error}}
  end

  defp extract_validation_result_ids(%{items: items}) when is_list(items) do
    {:ok, items}
  end

  defp extract_validation_result_ids(_input_data) do
    {:error, :invalid_input_data}
  end

  defp process_validation_results({:ok, validation_result_ids}, state) do
    Logger.debug("Processing #{length(validation_result_ids)} validation results")

    results =
      validation_result_ids
      |> Enum.map(fn validation_id ->
        case Generator.generate_task_instance(validation_id, state.job.generation_options) do
          {:ok, instance} ->
            Logger.debug("Generated instance #{instance.instance_id}")
            {:ok, instance}

          {:error, reason} ->
            Logger.warning(
              "Failed to generate instance for validation #{validation_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    successful_instances = Enum.filter(results, &match?({:ok, _}, &1))
    failed_instances = Enum.filter(results, &match?({:error, _}, &1))

    generation_summary = %{
      total_processed: length(validation_result_ids),
      instances_generated: length(successful_instances),
      instances_failed: length(failed_instances),
      successful_instances: Enum.map(successful_instances, fn {:ok, instance} -> instance end),
      failed_reasons: Enum.map(failed_instances, fn {:error, reason} -> reason end)
    }

    {:ok, generation_summary}
  end

  defp process_validation_results({:error, reason}, _state) do
    {:error, reason}
  end

  defp compile_generation_results({:ok, generation_summary}, state) do
    processing_time = DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)

    # Group instances by quality tier
    quality_distribution = group_instances_by_quality(generation_summary.successful_instances)

    result = %{
      job_id: state.job.id,
      instances_generated: generation_summary.instances_generated,
      instances_failed: generation_summary.instances_failed,
      processing_time_ms: processing_time,
      quality_distribution: quality_distribution,
      gold_count: Map.get(quality_distribution, :gold, 0),
      silver_count: Map.get(quality_distribution, :silver, 0),
      bronze_count: Map.get(quality_distribution, :bronze, 0)
    }

    {:ok, result}
  end

  defp compile_generation_results({:error, reason}, _state) do
    {:error, reason}
  end

  defp group_instances_by_quality(instances) do
    instances
    |> Enum.group_by(& &1.quality_tier)
    |> Enum.map(fn {tier, group} -> {tier, length(group)} end)
    |> Map.new()
  end

  defp complete_generation_job(state, results) do
    Logger.info("Completing generation job #{state.job.id}")

    # Update job with results
    state.job
    |> Ash.Changeset.for_update(:mark_completed, %{
      instances_generated: results.instances_generated,
      instances_failed: results.instances_failed
    })
    |> Ash.update()

    # Notify coordinator
    send(state.coordinator, {:worker_completed, self(), state.job.id, results})
  end

  defp fail_generation_job(state, reason) do
    error_message = inspect(reason)
    Logger.error("Generation job #{state.job.id} failed: #{error_message}")

    # Update job with failure
    state.job
    |> Ash.Changeset.for_update(:mark_failed, %{
      error_message: error_message
    })
    |> Ash.update()

    # Notify coordinator
    send(state.coordinator, {:worker_failed, self(), state.job.id, reason})
  end
end
