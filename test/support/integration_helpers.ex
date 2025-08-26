defmodule SweBench.IntegrationHelpers do
  @moduledoc """
  Helper functions for Phase 3 integration testing.

  Provides utilities for test data creation, pipeline execution,
  and validation of integration test scenarios.
  """

  alias SweBench.Repositories.Repository
  alias SweBench.Issues.{Issue, PullRequest, IssuePrLink}
  alias SweBench.TaskInstances.TaskInstance

  @doc """
  Creates a comprehensive test repository with associated data.
  """
  def create_test_repository_with_data(opts \\ []) do
    repository = create_test_repository(opts)
    issues = create_test_issues(repository, Keyword.get(opts, :issue_count, 3))
    prs = create_test_pull_requests(repository, Keyword.get(opts, :pr_count, 3))
    
    %{
      repository: repository,
      issues: issues,
      pull_requests: prs
    }
  end

  @doc """
  Creates a test repository with realistic characteristics.
  """
  def create_test_repository(opts \\ []) do
    attrs = %{
      github_id: Keyword.get(opts, :github_id, :rand.uniform(999_999_999)),
      name: Keyword.get(opts, :name, "test_repo_#{:rand.uniform(9999)}"),
      full_name: Keyword.get(opts, :full_name, "test_org/test_repo_#{:rand.uniform(9999)}"),
      owner: Keyword.get(opts, :owner, "test_org"),
      description: Keyword.get(opts, :description, "A test repository for integration testing"),
      language: Keyword.get(opts, :language, "Elixir"),
      stars_count: Keyword.get(opts, :stars_count, 100),
      forks_count: Keyword.get(opts, :forks_count, 20),
      has_issues: Keyword.get(opts, :has_issues, true),
      is_umbrella_project: Keyword.get(opts, :is_umbrella_project, false),
      default_branch: Keyword.get(opts, :default_branch, "main"),
      topics: Keyword.get(opts, :topics, ["elixir", "testing"]),
      license: Keyword.get(opts, :license, "MIT"),
      mining_status: :completed,
      mining_completed_at: DateTime.utc_now()
    }

    {:ok, repository} = Repository
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()

    repository
  end

  @doc """
  Creates test issues for a repository.
  """
  def create_test_issues(repository, count \\ 3) do
    1..count
    |> Enum.map(fn i ->
      attrs = %{
        repository_id: repository.id,
        github_id: :rand.uniform(999_999),
        number: i,
        title: "Test issue #{i}",
        body: "This is a test issue for integration testing. It describes a problem that needs to be solved with code changes.",
        state: "closed",
        labels: ["bug", "enhancement"],
        closed_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
      }

      {:ok, issue} = Issue
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

      issue
    end)
  end

  @doc """
  Creates test pull requests for a repository.
  """
  def create_test_pull_requests(repository, count \\ 3) do
    1..count
    |> Enum.map(fn i ->
      attrs = %{
        repository_id: repository.id,
        github_id: :rand.uniform(999_999),
        number: i,
        title: "Fix test issue #{i}",
        body: "This PR fixes test issue #{i} with comprehensive code changes.",
        state: "closed",
        diff_content: generate_test_diff_content(i),
        test_files_modified: ["test/example_test.exs"],
        additions: 10 + i,
        deletions: 5,
        changed_files: 2,
        merged_at: DateTime.add(DateTime.utc_now(), -i * 1800, :second),
        closed_at: DateTime.add(DateTime.utc_now(), -i * 1800, :second)
      }

      {:ok, pr} = PullRequest
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create()

      pr
    end)
  end

  @doc """
  Creates test issue-PR relationships.
  """
  def create_test_issue_pr_links(issues, pull_requests, repository) do
    issues
    |> Enum.zip(pull_requests)
    |> Enum.map(fn {issue, pr} ->
      attrs = %{
        repository_id: repository.id,
        issue_id: issue.id,
        pull_request_id: pr.id,
        relationship_type: :fixes,
        confidence_score: 0.9,
        detection_method: :commit_message,
        validation_status: :validated,
        matching_evidence: %{
          commit_messages: ["Fix issue ##{issue.number}"],
          reference_strength: :strong
        }
      }

      {:ok, link} = IssuePrLink
      |> Ash.Changeset.for_create(:create_link, attrs)
      |> Ash.create()

      link
    end)
  end

  @doc """
  Waits for a condition to be met with timeout.
  """
  def wait_for_condition(condition_fn, timeout_ms \\ 30_000) do
    end_time = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      if System.monotonic_time(:millisecond) < end_time do
        case condition_fn.() do
          true -> :success
          false -> 
            Process.sleep(1000)
            :continue
        end
      else
        :timeout
      end
    end)
    |> Stream.drop_while(&(&1 == :continue))
    |> Enum.take(1)
    |> case do
      [:success] -> :ok
      [:timeout] -> {:error, :timeout}
    end
  end

  @doc """
  Validates pipeline statistics and metrics.
  """
  def validate_pipeline_statistics do
    # Repository mining statistics
    mining_stats = RepositoryMining.get_mining_status()
    assert mining_stats.total_repositories_discovered >= 0

    # Issue-PR linking statistics  
    linking_stats = IssuePrLinking.get_analysis_status()
    assert linking_stats.total_correlations_found >= 0

    # Test transition validation statistics
    validation_stats = TestTransition.get_validation_status()
    assert validation_stats.total_validations_completed >= 0

    # Task generation statistics
    generation_stats = TaskGeneration.get_generation_status()
    assert generation_stats.total_instances_generated >= 0

    # Quality validation statistics
    quality_stats = QualityValidation.get_validation_status()
    assert quality_stats.total_validations_completed >= 0
  end

  @doc """
  Validates data quality across the pipeline.
  """
  def validate_pipeline_data_quality do
    # Validate that generated task instances meet quality standards
    {:ok, task_instances} = TaskGeneration.list_task_instances()
    
    if length(task_instances) > 0 do
      # Check quality tier distribution
      quality_distribution = Enum.frequencies_by(task_instances, & &1.quality_tier)
      
      total_instances = length(task_instances)
      high_quality_count = Map.get(quality_distribution, :gold, 0) + Map.get(quality_distribution, :silver, 0)
      
      quality_percentage = if total_instances > 0, do: high_quality_count / total_instances, else: 0
      
      assert quality_percentage >= 0.3, "At least 30% of instances should be high quality"
      
      # Validate instance completeness
      Enum.each(task_instances, fn instance ->
        assert String.length(instance.problem_statement) > 20
        assert String.length(instance.patch_content) > 0
        assert not is_nil(instance.quality_tier)
        assert not is_nil(instance.difficulty_level)
      end)
    end
  end

  # Test data generation helpers

  defp generate_test_diff_content(issue_number) do
    """
    diff --git a/lib/example.ex b/lib/example.ex
    index 1234567..abcdefg 100644
    --- a/lib/example.ex
    +++ b/lib/example.ex
    @@ -10,7 +10,7 @@ defmodule Example do
       def process_data(data) when is_list(data) do
    -    # TODO: Fix issue #{issue_number}
    +    # Fixed: Process data correctly for issue #{issue_number}
         data
         |> Enum.filter(&valid_item?/1)
         |> Enum.map(&transform_item/1)
    @@ -20,6 +20,10 @@ defmodule Example do
       defp valid_item?(item) do
         not is_nil(item) and item != ""
       end
    +
    +  defp transform_item(item) do
    +    String.trim(item)
    +  end
     end
    """
  end
end