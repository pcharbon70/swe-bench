defmodule SweBench.QualityValidation.Worker do
  @moduledoc """
  Individual worker process for quality validation operations.

  Handles the complete quality validation workflow from automated validation
  through statistical analysis to deduplication and review coordination.
  """

  use GenServer
  require Logger

  alias SweBench.QualityAssurance.QualityValidation
  alias SweBench.QualityValidation.{AutomatedValidator, StatisticalAnalyzer, DeduplicationSystem}

  defstruct [
    :job,
    :coordinator,
    :start_time,
    :current_operation,
    :validation_results
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
      validation_results: %{}
    }

    # Start validation immediately
    send(self(), :start_validation)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_validation, state) do
    Logger.info("Starting quality validation job #{state.job.id}")

    case execute_validation_pipeline(state) do
      {:ok, results} ->
        complete_validation_job(state, results)

      {:error, reason} ->
        fail_validation_job(state, reason)
    end

    {:stop, :normal, state}
  end

  # Private implementation functions

  defp execute_validation_pipeline(state) do
    state.job.task_instance_id
    |> load_task_instance()
    |> execute_validation_stages(state.job)
    |> persist_validation_results(state.job)
    |> compile_worker_results(state)
  rescue
    error ->
      Logger.error("Quality validation pipeline error for job #{state.job.id}: #{inspect(error)}")
      {:error, {:pipeline_error, error}}
  end

  defp load_task_instance(task_instance_id) do
    Logger.debug("Loading task instance for quality validation: #{task_instance_id}")

    case Ash.get(SweBench.TaskInstances.TaskInstance, task_instance_id) do
      {:ok, task_instance} ->
        case Ash.load(task_instance, [:repository, :issue_pr_link, :validation_result]) do
          {:ok, loaded_instance} ->
            {:ok, loaded_instance}

          {:error, reason} ->
            {:error, {:load_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:task_instance_not_found, reason}}
    end
  end

  defp execute_validation_stages({:ok, task_instance}, job) do
    Logger.debug("Executing validation stages for task #{task_instance.instance_id}")

    validation_results = %{
      automated: nil,
      statistical: nil,
      deduplication: nil
    }

    # Execute requested validation stages
    updated_results =
      job.validation_stages
      |> Enum.reduce(validation_results, fn stage, acc ->
        case execute_single_validation_stage(stage, task_instance, job) do
          {:ok, stage_result} ->
            Map.put(acc, stage, stage_result)

          {:error, reason} ->
            Logger.warning("Validation stage #{stage} failed: #{inspect(reason)}")
            Map.put(acc, stage, {:error, reason})
        end
      end)

    {:ok, {task_instance, updated_results}}
  end

  defp execute_validation_stages({:error, reason}, _job) do
    {:error, reason}
  end

  defp execute_single_validation_stage(:automated, task_instance, job) do
    AutomatedValidator.validate_task(task_instance, job)
  end

  defp execute_single_validation_stage(:statistical, task_instance, _job) do
    StatisticalAnalyzer.analyze_task_quality(task_instance)
  end

  defp execute_single_validation_stage(:deduplication, task_instance, _job) do
    DeduplicationSystem.check_for_duplicates(task_instance)
  end

  defp execute_single_validation_stage(unknown_stage, _task_instance, _job) do
    Logger.warning("Unknown validation stage: #{unknown_stage}")
    {:error, {:unknown_stage, unknown_stage}}
  end

  defp persist_validation_results({:ok, {task_instance, validation_results}}, job) do
    Logger.debug("Persisting quality validation results")

    # Calculate overall quality score
    overall_score = calculate_overall_quality_score(validation_results)
    confidence = calculate_overall_confidence(validation_results)

    attrs = %{
      task_instance_id: task_instance.id,
      validation_stage: :comprehensive,
      quality_score: overall_score,
      automated_confidence: get_automated_confidence(validation_results),
      statistical_analysis: get_statistical_data(validation_results),
      deduplication_score: get_deduplication_score(validation_results),
      validation_metadata: %{
        job_id: job.id,
        validation_stages: job.validation_stages,
        validation_version: "1.0.0",
        created_by: "automated_quality_validation"
      }
    }

    case QualityValidation
         |> Ash.Changeset.for_create(:create_validation, attrs)
         |> Ash.create() do
      {:ok, quality_validation} ->
        {:ok, {task_instance, validation_results, quality_validation}}

      {:error, reason} ->
        Logger.error("Failed to persist quality validation: #{inspect(reason)}")
        {:error, {:persistence_failed, reason}}
    end
  end

  defp persist_validation_results({:error, reason}, _job) do
    {:error, reason}
  end

  defp compile_worker_results({:ok, {task_instance, validation_results, quality_validation}}, state) do
    processing_time = DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)

    worker_result = %{
      validation_id: state.job.id,
      task_instance_id: task_instance.id,
      quality_score: quality_validation.quality_score,
      automated_confidence: quality_validation.automated_confidence,
      validation_stages_completed: length(state.job.validation_stages),
      processing_time_ms: processing_time,
      quality_validation_id: quality_validation.id
    }

    {:ok, worker_result}
  end

  defp compile_worker_results({:error, reason}, _state) do
    {:error, reason}
  end

  defp calculate_overall_quality_score(validation_results) do
    # Combine results from different validation stages
    scores = []

    scores =
      case Map.get(validation_results, :automated) do
        {:ok, %{overall_score: score}} -> [score | scores]
        _ -> scores
      end

    scores =
      case Map.get(validation_results, :statistical) do
        {:ok, %{quality_score: score}} -> [score | scores]
        _ -> scores
      end

    scores =
      case Map.get(validation_results, :deduplication) do
        {:ok, %{uniqueness_score: score}} -> [score | scores]
        _ -> scores
      end

    if Enum.empty?(scores) do
      0.5  # Default neutral score
    else
      Enum.sum(scores) / length(scores)
    end
  end

  defp calculate_overall_confidence(validation_results) do
    # Calculate confidence based on successful validation stages
    stage_confidences = []

    stage_confidences =
      case Map.get(validation_results, :automated) do
        {:ok, %{confidence: conf}} -> [conf | stage_confidences]
        _ -> stage_confidences
      end

    if Enum.empty?(stage_confidences) do
      0.5
    else
      Enum.sum(stage_confidences) / length(stage_confidences)
    end
  end

  defp get_automated_confidence(validation_results) do
    case Map.get(validation_results, :automated) do
      {:ok, %{confidence: conf}} -> conf
      _ -> nil
    end
  end

  defp get_statistical_data(validation_results) do
    case Map.get(validation_results, :statistical) do
      {:ok, statistical_data} -> statistical_data
      _ -> %{}
    end
  end

  defp get_deduplication_score(validation_results) do
    case Map.get(validation_results, :deduplication) do
      {:ok, %{uniqueness_score: score}} -> score
      _ -> nil
    end
  end

  defp complete_validation_job(state, results) do
    Logger.info("Completing quality validation job #{state.job.id}")

    # Notify coordinator
    send(state.coordinator, {:worker_completed, self(), state.job.id, results})
  end

  defp fail_validation_job(state, reason) do
    Logger.error("Quality validation job #{state.job.id} failed: #{inspect(reason)}")

    # Notify coordinator
    send(state.coordinator, {:worker_failed, self(), state.job.id, reason})
  end
end