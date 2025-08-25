defmodule SweBench.IssuePrLinking do
  @moduledoc """
  Main interface for Issue-PR linking system.

  Provides automated correlation between GitHub issues and pull requests to
  establish clear problem-solution pairs for benchmark task generation.
  """

  alias SweBench.IssuePrLinking.Coordinator
  alias SweBench.Issues.IssuePrLink

  @doc """
  Starts issue-PR correlation analysis for a repository.

  ## Parameters
    - repository_id: UUID of the repository to analyze
    - opts: Configuration options for correlation analysis

  ## Examples
      iex> SweBench.IssuePrLinking.analyze_repository(repository_id)
      {:ok, %{job_id: job_id, estimated_correlations: 150}}
  """
  def analyze_repository(repository_id, opts \\ []) do
    Coordinator.analyze_repository(repository_id, opts)
  end

  @doc """
  Gets current correlation analysis status and progress.
  """
  def get_analysis_status do
    Coordinator.get_analysis_status()
  end

  @doc """
  Lists discovered issue-PR relationships with confidence scores.
  """
  def list_relationships(repository_id, opts \\ []) do
    confidence_threshold = Keyword.get(opts, :min_confidence, 0.6)
    limit = Keyword.get(opts, :limit, 100)

    IssuePrLink
    |> Ash.Query.for_read(:by_repository, %{repository_id: repository_id})
    |> Ash.Query.for_read(:by_confidence_threshold, %{min_confidence: confidence_threshold})
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:issue, :pull_request])
    |> Ash.read()
  end

  @doc """
  Gets relationship quality distribution for a repository.
  """
  def get_relationship_distribution(repository_id) do
    Coordinator.get_relationship_distribution(repository_id)
  end

  @doc """
  Validates pending relationships based on confidence thresholds.
  """
  def validate_pending_relationships(repository_id, opts \\ []) do
    auto_validate_threshold = Keyword.get(opts, :auto_validate_threshold, 0.85)

    # Get pending relationships
    pending_links =
      IssuePrLink
      |> Ash.Query.for_read(:pending_validation)
      |> Ash.Query.for_read(:by_repository, %{repository_id: repository_id})
      |> Ash.read!()

    # Auto-validate high confidence relationships
    {auto_validated, needs_review} =
      Enum.split_with(pending_links, &(&1.confidence_score >= auto_validate_threshold))

    auto_validation_results =
      auto_validated
      |> Enum.map(fn link ->
        link
        |> Ash.Changeset.for_update(:validate_link, %{
          manual_validation_notes:
            "Auto-validated due to high confidence (#{link.confidence_score})"
        })
        |> Ash.update()
      end)

    {:ok,
     %{
       auto_validated: length(auto_validated),
       needs_review: length(needs_review),
       validation_results: auto_validation_results
     }}
  end
end
