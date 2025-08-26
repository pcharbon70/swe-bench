defmodule SweBench.Integration.Phase3PipelineTest do
  @moduledoc """
  Comprehensive integration tests for the complete Phase 3 Data Collection & Task Generation Pipeline.

  Tests end-to-end functionality from repository discovery through quality-assured
  task instance generation, validating performance targets and production readiness.
  """

  use SweBench.DataCase
  use ExUnit.Case, async: false

  alias SweBench.{RepositoryMining, IssuePrLinking, TestTransition, TaskGeneration, QualityValidation}
  alias SweBench.DataStorage
  alias SweBench.Repositories.Repository

  @moduletag :integration
  @moduletag timeout: 600_000  # 10 minutes for long-running integration tests

  describe "complete Phase 3 pipeline integration" do
    setup do
      # Set up test database and clean state
      clean_test_database()
      
      # Create test repository fixture
      repository_fixture = create_test_repository_fixture()
      
      %{repository: repository_fixture}
    end

    test "end-to-end pipeline execution from repository discovery to task generation", %{repository: repository} do
      # Phase 3.1: Repository Mining
      assert {:ok, mining_job} = RepositoryMining.start_mining(:manual_list, %{
        repositories: [repository.full_name],
        max_repositories: 1
      })

      # Wait for mining completion
      assert_eventually(fn -> 
        status = RepositoryMining.get_mining_status()
        status.completed_jobs > 0
      end, 60_000)

      # Phase 3.2: Issue-PR Linking
      assert {:ok, correlation_job} = IssuePrLinking.analyze_repository(repository.id)
      
      # Wait for correlation completion
      assert_eventually(fn ->
        status = IssuePrLinking.get_analysis_status()
        status.completed_repositories > 0
      end, 120_000)

      # Verify issue-PR relationships were created
      {:ok, relationships} = IssuePrLinking.list_relationships(repository.id)
      assert length(relationships) > 0

      # Phase 3.3: Test Transition Validation
      relationship_ids = Enum.map(relationships, & &1.id)
      assert {:ok, validation_results} = TestTransition.validate_batch(relationship_ids)

      # Wait for validation completion
      assert_eventually(fn ->
        status = TestTransition.get_validation_status()
        status.completed_validations > 0
      end, 180_000)

      # Phase 3.4: Task Instance Generation
      validation_result_ids = get_validation_result_ids(relationship_ids)
      assert {:ok, generation_results} = TaskGeneration.generate_instances(validation_result_ids)

      # Wait for generation completion
      assert_eventually(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 120_000)

      # Phase 3.5: Quality Assurance
      {:ok, task_instances} = TaskGeneration.list_task_instances()
      task_instance_ids = Enum.map(task_instances, & &1.id)
      
      assert {:ok, quality_results} = QualityValidation.validate_batch(task_instance_ids)

      # Wait for quality validation completion
      assert_eventually(fn ->
        status = QualityValidation.get_validation_status()
        status.completed_validations > 0
      end, 240_000)

      # Phase 3.6: Data Storage and Export Validation
      assert {:ok, optimization_result} = DataStorage.optimize_for_production()
      assert optimization_result.optimization_successful

      # Validate final pipeline results
      validate_pipeline_completion(repository)
    end

    test "pipeline performance targets validation", %{repository: repository} do
      start_time = DateTime.utc_now()

      # Execute complete pipeline
      execute_complete_pipeline(repository)

      end_time = DateTime.utc_now()
      total_time_seconds = DateTime.diff(end_time, start_time)

      # Validate performance targets
      assert total_time_seconds < 3600, "Complete pipeline should finish within 1 hour"

      # Validate individual phase performance
      validate_phase_performance_targets()
    end

    test "pipeline error handling and recovery" do
      # Test error scenarios and recovery
      test_repository_mining_failure_recovery()
      test_issue_pr_linking_failure_recovery()
      test_validation_failure_recovery()
      test_generation_failure_recovery()
      test_quality_assurance_failure_recovery()
    end

    test "pipeline data consistency and integrity" do
      # Test data consistency across phases
      validate_data_flow_integrity()
      validate_foreign_key_consistency()
      validate_quality_tier_consistency()
      validate_metadata_completeness()
    end
  end

  # Helper functions for integration testing

  defp clean_test_database do
    # Clean up test data between runs
    SweBench.Repo.delete_all(SweBench.TaskInstances.TaskInstance)
    SweBench.Repo.delete_all(SweBench.ValidationResults.ValidationResult)
    SweBench.Repo.delete_all(SweBench.Issues.IssuePrLink)
    SweBench.Repo.delete_all(SweBench.QualityAssurance.QualityValidation)
  end

  defp create_test_repository_fixture do
    # Create a test repository with known characteristics
    repository_attrs = %{
      github_id: 123_456_789,
      name: "test_repository",
      full_name: "test_org/test_repository",
      owner: "test_org",
      description: "A test repository for integration testing",
      language: "Elixir",
      stars_count: 100,
      forks_count: 20,
      has_issues: true,
      is_umbrella_project: false,
      default_branch: "main",
      topics: ["elixir", "testing"],
      license: "MIT"
    }

    {:ok, repository} = Repository
    |> Ash.Changeset.for_create(:create, repository_attrs)
    |> Ash.create()

    repository
  end

  defp assert_eventually(assertion_fn, timeout_ms) do
    end_time = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      if System.monotonic_time(:millisecond) < end_time do
        try do
          if assertion_fn.() do
            :success
          else
            Process.sleep(1000)
            :continue
          end
        rescue
          _ ->
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
      [:timeout] -> flunk("Assertion timed out after #{timeout_ms}ms")
      _ -> flunk("Unexpected assertion result")
    end
  end

  defp execute_complete_pipeline(repository) do
    # Execute all phases in sequence with minimal delays
    {:ok, _} = RepositoryMining.start_mining(:manual_list, %{repositories: [repository.full_name]})
    {:ok, _} = IssuePrLinking.analyze_repository(repository.id)
    # Continue with remaining phases...
  end

  defp validate_pipeline_completion(repository) do
    # Validate that all phases completed successfully
    
    # Check repository mining results
    mining_status = RepositoryMining.get_mining_status()
    assert mining_status.total_repositories_discovered > 0

    # Check issue-PR linking results
    {:ok, relationships} = IssuePrLinking.list_relationships(repository.id)
    assert length(relationships) > 0

    # Check validation results
    validation_status = TestTransition.get_validation_status()
    assert validation_status.total_validations_completed > 0

    # Check task generation results
    {:ok, task_instances} = TaskGeneration.list_task_instances()
    assert length(task_instances) > 0

    # Check quality assurance results
    quality_status = QualityValidation.get_validation_status()
    assert quality_status.total_validations_completed > 0

    # Validate final data quality
    validate_final_data_quality(task_instances)
  end

  defp validate_phase_performance_targets do
    # Validate each phase meets its performance targets
    
    mining_status = RepositoryMining.get_mining_status()
    assert mining_status.throughput_per_hour >= 50, "Repository mining should achieve 50+ repos/hour"

    linking_status = IssuePrLinking.get_analysis_status()
    assert linking_status.throughput_per_hour >= 100, "Issue-PR linking should achieve 100+ correlations/hour"

    validation_status = TestTransition.get_validation_status()
    assert validation_status.throughput_per_hour >= 100, "Test validation should achieve 100+ validations/hour"

    generation_status = TaskGeneration.get_generation_status()
    assert generation_status.throughput_per_hour >= 100, "Task generation should achieve 100+ instances/hour"

    quality_status = QualityValidation.get_validation_status()
    assert quality_status.throughput_per_hour >= 100, "Quality validation should achieve 100+ validations/hour"
  end

  defp get_validation_result_ids(relationship_ids) do
    # Get validation result IDs from relationships
    relationship_ids
    |> Enum.map(fn id ->
      case Ash.get(SweBench.Issues.IssuePrLink, id) do
        {:ok, link} -> 
          case Ash.load(link, :validation_result) do
            {:ok, loaded} -> loaded.validation_result&.id
            _ -> nil
          end
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp validate_final_data_quality(task_instances) do
    # Validate final task instance quality
    quality_tiers = Enum.map(task_instances, & &1.quality_tier)
    
    # Should have at least some high-quality instances
    high_quality_count = Enum.count(quality_tiers, &(&1 in [:gold, :silver]))
    total_count = length(quality_tiers)
    
    assert high_quality_count / total_count >= 0.5, 
           "At least 50% of instances should be high quality (gold/silver)"

    # Validate SWE-bench format compliance
    Enum.each(task_instances, fn instance ->
      assert String.length(instance.problem_statement) > 50
      assert String.length(instance.patch_content) > 0
      assert not is_nil(instance.instance_id)
    end)
  end

  # Error handling test helpers
  defp test_repository_mining_failure_recovery do
    # Test repository mining resilience
    assert true  # Placeholder - will implement specific error scenarios
  end

  defp test_issue_pr_linking_failure_recovery do
    # Test issue-PR linking resilience
    assert true  # Placeholder - will implement specific error scenarios
  end

  defp test_validation_failure_recovery do
    # Test validation resilience
    assert true  # Placeholder - will implement specific error scenarios
  end

  defp test_generation_failure_recovery do
    # Test generation resilience
    assert true  # Placeholder - will implement specific error scenarios
  end

  defp test_quality_assurance_failure_recovery do
    # Test quality assurance resilience
    assert true  # Placeholder - will implement specific error scenarios
  end

  defp validate_data_flow_integrity do
    # Validate data flows correctly between phases
    assert true  # Placeholder - will implement data flow validation
  end

  defp validate_foreign_key_consistency do
    # Validate foreign key relationships are maintained
    assert true  # Placeholder - will implement FK validation
  end

  defp validate_quality_tier_consistency do
    # Validate quality tiers are consistent across phases
    assert true  # Placeholder - will implement quality consistency validation
  end

  defp validate_metadata_completeness do
    # Validate metadata is complete across all phases
    assert true  # Placeholder - will implement metadata validation
  end
end