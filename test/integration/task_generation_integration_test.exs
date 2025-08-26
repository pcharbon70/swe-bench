defmodule SweBench.Integration.TaskGenerationIntegrationTest do
  @moduledoc """
  Integration tests for Phase 3.4 Task Instance Generator.

  Tests task instance generation, metadata enrichment, and SWE-bench
  format compliance with realistic validation data scenarios.
  """

  use SweBench.DataCase
  use ExUnit.Case, async: false

  import SweBench.IntegrationHelpers

  alias SweBench.TaskGeneration
  alias SweBench.ValidationResults.ValidationResult
  alias SweBench.TaskInstances.TaskInstance

  @moduletag :integration
  @moduletag :task_generation

  describe "task instance generation integration" do
    setup do
      # Create test data with complete pipeline setup
      test_data = create_test_repository_with_data()
      
      # Create test validation results
      validation_results = create_test_validation_results(test_data)
      
      %{
        test_data: test_data,
        validation_results: validation_results
      }
    end

    test "generates task instances from validation results", %{validation_results: validation_results} do
      validation_ids = Enum.map(validation_results, & &1.id)

      # Start task generation
      assert {:ok, generation_job} = TaskGeneration.generate_instances(validation_ids)

      # Wait for completion
      assert :ok = wait_for_condition(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 120_000)

      # Validate results
      {:ok, task_instances} = TaskGeneration.list_task_instances()
      assert length(task_instances) >= length(validation_results)

      # Validate task instance quality
      Enum.each(task_instances, fn instance ->
        assert String.length(instance.problem_statement) > 50
        assert String.length(instance.patch_content) > 0
        assert instance.quality_tier in [:gold, :silver, :bronze]
        assert instance.difficulty_level in [:easy, :medium, :hard, :expert]
        assert not is_nil(instance.content_checksum)
      end)
    end

    test "validates SWE-bench format compliance", %{validation_results: validation_results} do
      validation_ids = Enum.map(validation_results, & &1.id)

      {:ok, _job} = TaskGeneration.generate_instances(validation_ids)

      assert :ok = wait_for_condition(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 60_000)

      # Get generated instances
      {:ok, task_instances} = TaskGeneration.list_task_instances()
      
      # Validate SWE-bench format compliance
      Enum.each(task_instances, fn instance ->
        # Required SWE-bench fields
        assert not is_nil(instance.instance_id)
        assert String.match?(instance.instance_id, ~r/^[a-zA-Z0-9_-]+$/)
        assert not is_nil(instance.base_commit_sha)
        assert String.length(instance.base_commit_sha) == 40 or String.length(instance.base_commit_sha) <= 8
        
        # Content requirements
        assert is_binary(instance.problem_statement)
        assert is_binary(instance.patch_content)
        
        # Metadata validation
        assert is_map(instance.task_metadata)
        assert is_map(instance.evaluation_metadata)
      end)
    end

    test "handles generation failures gracefully", %{test_data: test_data} do
      # Create invalid validation result
      invalid_attrs = %{
        issue_pr_link_id: Ash.UUID.generate(),  # Non-existent link
        repository_id: test_data.repository.id,
        base_commit_sha: "invalid_commit",
        confidence_level: 0.95,
        consistency_score: 0.90,
        benchmark_quality: :gold
      }

      {:ok, invalid_validation} = ValidationResult
      |> Ash.Changeset.for_create(:create_validation, invalid_attrs)
      |> Ash.create()

      # Attempt generation with invalid data
      result = TaskGeneration.generate_instances([invalid_validation.id])
      
      # Should handle gracefully
      case result do
        {:ok, _} -> :ok  # If it succeeds, that's fine
        {:error, _} -> :ok  # If it fails gracefully, that's also fine
      end

      # System should remain stable
      status = TaskGeneration.get_generation_status()
      assert is_map(status)
    end

    test "achieves generation performance targets", %{validation_results: validation_results} do
      validation_ids = Enum.map(validation_results, & &1.id)

      start_time = DateTime.utc_now()

      # Generate instances
      {:ok, _job} = TaskGeneration.generate_instances(validation_ids)

      assert :ok = wait_for_condition(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 60_000)

      end_time = DateTime.utc_now()
      processing_time_seconds = DateTime.diff(end_time, start_time)

      # Should generate instances efficiently
      assert processing_time_seconds < 120, "Generation should complete within 2 minutes"

      # Validate throughput target
      status = TaskGeneration.get_generation_status()
      
      if status.uptime_seconds > 0 do
        assert status.throughput_per_hour >= 50, "Should achieve reasonable throughput"
      end
    end
  end

  describe "metadata enrichment and complexity analysis" do
    test "enriches task instances with comprehensive metadata", %{validation_results: validation_results} do
      validation_ids = Enum.take(Enum.map(validation_results, & &1.id), 1)

      {:ok, _job} = TaskGeneration.generate_instances(validation_ids)

      assert :ok = wait_for_condition(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 30_000)

      {:ok, [task_instance | _]} = TaskGeneration.list_task_instances()

      # Validate enrichment metadata presence
      assert is_map(task_instance.task_metadata)
      assert map_size(task_instance.task_metadata) > 0

      # Validate evaluation metadata
      assert is_map(task_instance.evaluation_metadata)
      assert map_size(task_instance.evaluation_metadata) > 0

      # Validate complexity analysis
      complexity_data = get_in(task_instance.task_metadata, [:complexity_analysis])
      if complexity_data do
        assert is_map(complexity_data)
      end
    end

    test "calculates difficulty levels appropriately", %{validation_results: validation_results} do
      validation_ids = Enum.map(validation_results, & &1.id)

      {:ok, _job} = TaskGeneration.generate_instances(validation_ids)

      assert :ok = wait_for_condition(fn ->
        status = TaskGeneration.get_generation_status()
        status.completed_jobs > 0
      end, 60_000)

      {:ok, task_instances} = TaskGeneration.list_task_instances()

      # Validate difficulty level assignments
      difficulty_levels = Enum.map(task_instances, & &1.difficulty_level)
      unique_levels = Enum.uniq(difficulty_levels)

      # Should assign reasonable difficulty levels
      assert Enum.all?(unique_levels, &(&1 in [:easy, :medium, :hard, :expert]))

      # Should have diversity in difficulty if multiple instances
      if length(task_instances) > 2 do
        assert length(unique_levels) > 1, "Should have diversity in difficulty levels"
      end
    end
  end

  # Helper functions for task generation testing

  defp create_test_validation_results(test_data) do
    # Create test issue-PR links
    issue_pr_links = create_test_issue_pr_links(
      test_data.issues,
      test_data.pull_requests,
      test_data.repository
    )

    # Create validation results for each link
    issue_pr_links
    |> Enum.map(fn link ->
      attrs = %{
        issue_pr_link_id: link.id,
        repository_id: test_data.repository.id,
        base_commit_sha: "abc1234567890def",
        patch_sha256: :crypto.hash(:sha256, "test_patch") |> Base.encode16(case: :lower),
        validation_runs: 3,
        consistency_score: 0.95,
        confidence_level: 0.90,
        benchmark_quality: :silver,
        fail_to_pass_count: 2,
        pass_to_pass_count: 8,
        pass_to_fail_count: 0,
        flaky_tests: [],
        validation_metadata: %{
          test_framework: "ExUnit",
          validation_version: "1.0.0"
        }
      }

      {:ok, validation_result} = ValidationResult
      |> Ash.Changeset.for_create(:create_validation, attrs)
      |> Ash.create()

      validation_result
    end)
  end
end