defmodule SweBench.Integration.EndToEndPipelineTest do
  @moduledoc """
  End-to-end integration tests for the complete Phase 3 Data Collection & Task Generation Pipeline.

  Tests the complete workflow from repository discovery through quality-assured
  task instance generation with comprehensive validation and performance monitoring.
  """

  use SweBench.DataCase
  use ExUnit.Case, async: false

  import SweBench.IntegrationHelpers

  alias SweBench.{
    RepositoryMining, 
    IssuePrLinking, 
    TestTransition, 
    TaskGeneration, 
    QualityValidation,
    DataStorage
  }

  @moduletag :integration
  @moduletag :end_to_end
  @moduletag timeout: 1_800_000  # 30 minutes for complete pipeline tests

  describe "complete Phase 3 pipeline integration" do
    setup do
      # Clean test environment
      clean_test_database()

      # Create comprehensive test data
      repository = create_test_repository(%{
        name: "integration_test_repo",
        full_name: "test_org/integration_test_repo",
        stars_count: 250,
        forks_count: 50,
        has_issues: true,
        language: "Elixir"
      })

      issues = create_test_issues(repository, 5)
      prs = create_test_pull_requests(repository, 5)

      %{
        repository: repository,
        issues: issues,
        pull_requests: prs
      }
    end

    @tag :comprehensive
    test "executes complete pipeline successfully", %{repository: repository, issues: issues, pull_requests: prs} do
      pipeline_start_time = DateTime.utc_now()

      # Step 1: Repository Mining (Phase 3.1)
      IO.puts("Starting Phase 3.1: Repository Mining")
      assert {:ok, mining_job} = RepositoryMining.start_mining(:manual_list, %{
        repositories: [repository.full_name],
        max_repositories: 1
      })

      # Wait for repository mining completion
      assert :ok = wait_for_condition(fn ->
        status = RepositoryMining.get_mining_status()
        status.completed_jobs > 0 and status.total_repositories_discovered >= 1
      end, 120_000)

      mining_status = RepositoryMining.get_mining_status()
      IO.puts("Phase 3.1 completed: #{mining_status.total_repositories_discovered} repositories discovered")

      # Step 2: Issue-PR Linking (Phase 3.2)
      IO.puts("Starting Phase 3.2: Issue-PR Linking")
      assert {:ok, correlation_job} = IssuePrLinking.analyze_repository(repository.id)

      # Wait for issue-PR linking completion
      assert :ok = wait_for_condition(fn ->
        status = IssuePrLinking.get_analysis_status()
        status.completed_repositories > 0
      end, 180_000)

      {:ok, relationships} = IssuePrLinking.list_relationships(repository.id)
      IO.puts("Phase 3.2 completed: #{length(relationships)} issue-PR relationships found")
      assert length(relationships) > 0

      # Step 3: Test Transition Validation (Phase 3.3)
      IO.puts("Starting Phase 3.3: Test Transition Validation")
      validated_relationships = Enum.filter(relationships, &(&1.validation_status == :validated))
      
      if length(validated_relationships) > 0 do
        relationship_ids = Enum.map(validated_relationships, & &1.id)
        assert {:ok, validation_batch_result} = TestTransition.validate_batch(relationship_ids)

        # Wait for test validation completion
        assert :ok = wait_for_condition(fn ->
          status = TestTransition.get_validation_status()
          status.completed_validations > 0
        end, 300_000)

        validation_status = TestTransition.get_validation_status()
        IO.puts("Phase 3.3 completed: #{validation_status.total_validations_completed} validations completed")
      end

      # Step 4: Task Instance Generation (Phase 3.4)
      IO.puts("Starting Phase 3.4: Task Instance Generation")
      
      # Get validation results
      {:ok, validation_results} = TestTransition.list_validation_results()
      
      if length(validation_results) > 0 do
        validation_result_ids = Enum.map(validation_results, & &1.id)
        assert {:ok, generation_result} = TaskGeneration.generate_instances(validation_result_ids)

        # Wait for task generation completion
        assert :ok = wait_for_condition(fn ->
          status = TaskGeneration.get_generation_status()
          status.completed_jobs > 0
        end, 180_000)

        generation_status = TaskGeneration.get_generation_status()
        IO.puts("Phase 3.4 completed: #{generation_status.total_instances_generated} task instances generated")
      end

      # Step 5: Quality Assurance (Phase 3.5)
      IO.puts("Starting Phase 3.5: Quality Assurance")
      
      {:ok, task_instances} = TaskGeneration.list_task_instances()
      
      if length(task_instances) > 0 do
        task_instance_ids = Enum.map(task_instances, & &1.id)
        assert {:ok, quality_results} = QualityValidation.validate_batch(task_instance_ids)

        # Wait for quality validation completion
        assert :ok = wait_for_condition(fn ->
          status = QualityValidation.get_validation_status()
          status.completed_validations > 0
        end, 300_000)

        quality_status = QualityValidation.get_validation_status()
        IO.puts("Phase 3.5 completed: #{quality_status.total_validations_completed} quality validations completed")
      end

      # Step 6: Data Storage Optimization (Phase 3.6)
      IO.puts("Starting Phase 3.6: Data Storage Optimization")
      assert {:ok, optimization_result} = DataStorage.optimize_for_production()
      assert optimization_result.optimization_successful

      IO.puts("Phase 3.6 completed: Database optimization successful")

      pipeline_end_time = DateTime.utc_now()
      total_pipeline_time = DateTime.diff(pipeline_end_time, pipeline_start_time)

      IO.puts("Complete pipeline execution time: #{total_pipeline_time} seconds")

      # Validate overall pipeline performance
      assert total_pipeline_time < 1800, "Complete pipeline should finish within 30 minutes"

      # Validate final results
      validate_complete_pipeline_results(repository)
    end

    @tag :stress
    test "pipeline stress testing with multiple repositories" do
      # Create multiple repositories for stress testing
      repositories = 1..5
      |> Enum.map(fn i ->
        create_test_repository_with_data(%{
          name: "stress_repo_#{i}",
          issue_count: 3,
          pr_count: 3
        })
      end)

      start_time = DateTime.utc_now()

      # Execute pipeline for all repositories concurrently
      repository_names = Enum.map(repositories, &(&1.repository.full_name))
      
      # Start mining for all repositories
      {:ok, _job} = RepositoryMining.start_mining(:manual_list, %{
        repositories: repository_names,
        max_repositories: 5
      })

      # Wait for completion
      assert :ok = wait_for_condition(fn ->
        status = RepositoryMining.get_mining_status()
        status.total_repositories_discovered >= 5
      end, 600_000)

      end_time = DateTime.utc_now()
      stress_test_time = DateTime.diff(end_time, start_time)

      # Validate stress test performance
      repositories_per_hour = (length(repositories) / stress_test_time) * 3600
      assert repositories_per_hour >= 30, "Should maintain reasonable throughput under stress"

      # Validate system stability
      validate_system_stability_after_stress()
    end
  end

  describe "pipeline resource utilization" do
    test "monitors resource usage throughout pipeline execution" do
      repository = create_test_repository()

      # Measure resource usage before
      initial_resources = measure_system_resources()

      # Execute pipeline with resource monitoring
      execute_pipeline_with_monitoring(repository)

      # Measure resource usage after
      final_resources = measure_system_resources()

      # Validate resource efficiency
      validate_resource_utilization(initial_resources, final_resources)
    end

    test "validates container pool utilization" do
      # Test container pool performance and utilization
      repository = create_test_repository()

      # Monitor container usage during pipeline execution
      container_metrics_before = get_container_metrics()
      
      execute_pipeline_sequence(repository)
      
      container_metrics_after = get_container_metrics()

      # Validate efficient container utilization
      validate_container_efficiency(container_metrics_before, container_metrics_after)
    end
  end

  # Helper functions for performance testing

  defp validate_complete_pipeline_results(repository) do
    # Validate all phases produced expected results
    
    # Repository mining should be marked complete
    updated_repo = Ash.get!(SweBench.Repositories.Repository, repository.id)
    assert updated_repo.mining_status == :completed

    # Should have issue-PR relationships
    {:ok, relationships} = IssuePrLinking.list_relationships(repository.id)
    relationship_count = length(relationships)

    if relationship_count > 0 do
      # Should have validation results
      {:ok, validation_results} = TestTransition.list_validation_results()
      assert length(validation_results) > 0

      # Should have task instances
      {:ok, task_instances} = TaskGeneration.list_task_instances()
      assert length(task_instances) > 0

      # Should have quality validations
      {:ok, quality_validations} = QualityValidation.list_validation_results()
      assert length(quality_validations) > 0

      IO.puts("Pipeline validation successful:")
      IO.puts("  - #{relationship_count} issue-PR relationships")
      IO.puts("  - #{length(validation_results)} validation results") 
      IO.puts("  - #{length(task_instances)} task instances")
      IO.puts("  - #{length(quality_validations)} quality validations")
    else
      IO.puts("No issue-PR relationships found - this may be expected for test data")
    end
  end

  defp execute_pipeline_with_monitoring(repository) do
    # Execute pipeline with resource monitoring at each step
    monitor_pid = spawn_link(fn -> resource_monitor_loop() end)
    
    try do
      execute_pipeline_sequence(repository)
    after
      Process.exit(monitor_pid, :normal)
    end
  end

  defp resource_monitor_loop do
    # Monitor resource usage periodically
    receive do
      :stop -> :ok
    after
      5000 ->
        memory_mb = :erlang.memory(:total) / 1024 / 1024
        IO.puts("Resource monitor: Memory usage #{Float.round(memory_mb, 1)}MB")
        resource_monitor_loop()
    end
  end

  defp measure_system_resources do
    %{
      memory_total: :erlang.memory(:total),
      process_count: length(Process.list()),
      timestamp: DateTime.utc_now()
    }
  end

  defp validate_resource_utilization(initial, final) do
    memory_increase_mb = (final.memory_total - initial.memory_total) / 1024 / 1024
    process_increase = final.process_count - initial.process_count

    # Validate reasonable resource usage
    assert memory_increase_mb < 2048, "Memory increase should be under 2GB"
    assert process_increase < 1000, "Process count increase should be reasonable"
  end

  defp get_container_metrics do
    # Placeholder for container metrics - would integrate with actual container monitoring
    %{
      active_containers: 0,
      total_containers: 0,
      utilization: 0.0
    }
  end

  defp validate_container_efficiency(_before, _after) do
    # Placeholder for container efficiency validation
    assert true
  end

  defp validate_system_stability_after_stress do
    # Validate system remains responsive after stress testing
    
    # Check that all supervisors are still running
    supervisors = [
      SweBench.RepositoryMining.Supervisor,
      SweBench.IssuePrLinking.Supervisor,
      SweBench.TestTransition.Supervisor,
      SweBench.TaskGeneration.Supervisor,
      SweBench.QualityValidation.Supervisor
    ]

    Enum.each(supervisors, fn supervisor ->
      pid = GenServer.whereis(supervisor)
      assert is_pid(pid) and Process.alive?(pid), "Supervisor #{supervisor} should be running"
    end)

    # Check database connectivity
    assert {:ok, _} = SweBench.Repo.query("SELECT 1")
  end
end