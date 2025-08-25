defmodule SweBench.TestTransition do
  @moduledoc """
  Main interface for test transition validation system.

  Provides automated validation of test state transitions to ensure issue-PR pairs
  produce deterministic FAIL_TO_PASS behavior suitable for benchmark tasks.
  """

  alias SweBench.TestTransition.Coordinator
  alias SweBench.ValidationResults.ValidationResult

  @doc """
  Validates test transitions for an issue-PR pair.

  ## Parameters
    - issue_pr_link_id: UUID of the issue-PR relationship to validate
    - opts: Configuration options for validation

  ## Examples
      iex> SweBench.TestTransition.validate_transitions(link_id)
      {:ok, %{quality_tier: :gold, confidence: 0.95}}
  """
  def validate_transitions(issue_pr_link_id, opts \\ []) do
    Coordinator.validate_transitions(issue_pr_link_id, opts)
  end

  @doc """
  Validates multiple issue-PR pairs in batch.
  """
  def validate_batch(issue_pr_link_ids, opts \\ []) do
    Coordinator.validate_batch(issue_pr_link_ids, opts)
  end

  @doc """
  Gets current validation status and progress.
  """
  def get_validation_status do
    Coordinator.get_validation_status()
  end

  @doc """
  Lists validation results with quality filtering.
  """
  def list_validation_results(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ValidationResult
    |> Ash.Query.for_read(:suitable_for_benchmark)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:issue_pr_link, :repository])
    |> Ash.read()
  end

  @doc """
  Gets validation quality distribution statistics.
  """
  def get_quality_distribution do
    Coordinator.get_quality_distribution()
  end

  @doc """
  Forces processing of pending validations (useful for testing).
  """
  def process_pending_validations do
    Coordinator.process_pending_validations()
  end
end