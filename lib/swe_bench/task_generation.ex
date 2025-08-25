defmodule SweBench.TaskGeneration do
  @moduledoc """
  Main interface for task instance generation system.

  Provides automated generation of SWE-bench task instances from validated
  issue-PR pairs with comprehensive Elixir-specific metadata enrichment.
  """

  alias SweBench.TaskGeneration.Coordinator
  alias SweBench.TaskInstances.TaskInstance

  @doc """
  Generates task instances from validation results.

  ## Parameters
    - validation_result_ids: List of validation result UUIDs to process
    - opts: Configuration options for generation

  ## Examples
      iex> SweBench.TaskGeneration.generate_instances([id1, id2])
      {:ok, %{generated: 2, failed: 0}}
  """
  def generate_instances(validation_result_ids, opts \\ []) do
    Coordinator.generate_instances(validation_result_ids, opts)
  end

  @doc """
  Generates task instances for an entire repository.
  """
  def generate_repository_instances(repository_id, opts \\ []) do
    Coordinator.generate_repository_instances(repository_id, opts)
  end

  @doc """
  Gets current generation status and progress.
  """
  def get_generation_status do
    Coordinator.get_generation_status()
  end

  @doc """
  Lists generated task instances with quality filtering.
  """
  def list_task_instances(opts \\ []) do
    quality_tier = Keyword.get(opts, :quality_tier, :bronze)
    limit = Keyword.get(opts, :limit, 100)

    TaskInstance
    |> Ash.Query.for_read(:by_quality_tier, %{tier: quality_tier})
    |> Ash.Query.sort(created_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:repository, :issue_pr_link, :validation_result])
    |> Ash.read()
  end

  @doc """
  Gets task instance generation statistics.
  """
  def get_generation_statistics do
    Coordinator.get_generation_statistics()
  end

  @doc """
  Creates a dataset release from generated instances.
  """
  def create_dataset_release(opts \\ []) do
    Coordinator.create_dataset_release(opts)
  end
end
