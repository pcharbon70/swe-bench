defmodule SweBench.QualityValidation do
  @moduledoc """
  Main interface for quality validation and assurance operations.

  Provides comprehensive quality validation including automated validation,
  statistical analysis, deduplication, and human review coordination.
  """

  alias SweBench.QualityValidation.Coordinator
  alias SweBench.QualityAssurance.QualityValidation

  @doc """
  Performs comprehensive quality validation on a task instance.

  ## Parameters
    - task_instance_id: UUID of the task instance to validate
    - opts: Configuration options for validation

  ## Examples
      iex> SweBench.QualityValidation.validate_quality(task_id)
      {:ok, %{quality_score: 0.95, validation_status: :passed}}
  """
  def validate_quality(task_instance_id, opts \\ []) do
    Coordinator.validate_quality(task_instance_id, opts)
  end

  @doc """
  Validates multiple task instances in batch.
  """
  def validate_batch(task_instance_ids, opts \\ []) do
    Coordinator.validate_batch(task_instance_ids, opts)
  end

  @doc """
  Gets current quality validation status and metrics.
  """
  def get_validation_status do
    Coordinator.get_validation_status()
  end

  @doc """
  Lists quality validation results with filtering.
  """
  def list_validation_results(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    QualityValidation
    |> Ash.Query.for_read(:completed_validations)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:task_instance, :review_sessions])
    |> Ash.read()
  end

  @doc """
  Gets quality statistics and distribution metrics.
  """
  def get_quality_statistics do
    Coordinator.get_quality_statistics()
  end

  @doc """
  Triggers quality assurance processing for pending task instances.
  """
  def process_pending_validations do
    Coordinator.process_pending_validations()
  end

  @doc """
  Gets deduplication results for task instances.
  """
  def get_deduplication_results(repository_id \\ nil) do
    Coordinator.get_deduplication_results(repository_id)
  end

  @doc """
  Assigns task instances for human review.
  """
  def assign_for_human_review(task_instance_ids, reviewer_ids \\ nil) do
    Coordinator.assign_for_human_review(task_instance_ids, reviewer_ids)
  end
end