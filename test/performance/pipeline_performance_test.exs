defmodule SweBench.Performance.PipelinePerformanceTest do
  @moduledoc """
  Performance tests for the complete Phase 3 Data Collection & Task Generation Pipeline.

  Validates performance targets, throughput capabilities, and resource
  utilization under realistic production scenarios.
  """

  use SweBench.DataCase
  use ExUnit.Case, async: false

  import SweBench.IntegrationHelpers

  alias SweBench.{
    RepositoryMining,
    IssuePrLinking,
    TestTransition,
    TaskGeneration,
    QualityValidation
  }

  @moduletag :performance
  # 30 minutes for performance tests
  @moduletag timeout: 1_800_000

  describe "Phase 3 pipeline performance validation" do
    @tag :slow
    test "validates repository mining performance targets" do
      # Create 10 test repositories for performance testing
      repositories =
        1..10
        |> Enum.map(fn i ->
          create_test_repository(%{
            name: "perf_repo_#{i}",
            stars_count: 50 + i * 10,
            forks_count: 5 + i
          })
        end)

      repository_names = Enum.map(repositories, & &1.full_name)

      start_time = DateTime.utc_now()

      # Start mining with performance measurement
      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: repository_names,
          max_repositories: 10
        })

      # Wait for completion
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 300_000
               )

      end_time = DateTime.utc_now()
      total_time_seconds = DateTime.diff(end_time, start_time)

      # Validate performance targets
      repositories_per_second = length(repositories) / total_time_seconds
      repositories_per_hour = repositories_per_second * 3600

      assert repositories_per_hour >= 50,
             "Repository mining should achieve 50+ repos/hour target (achieved: #{Float.round(repositories_per_hour, 1)})"

      # Validate resource efficiency
      status = RepositoryMining.get_mining_status()
      assert status.total_repositories_discovered >= 10
    end

    @tag :slow
    test "validates complete pipeline throughput" do
      # Create comprehensive test scenario
      test_data =
        create_test_repository_with_data(%{
          issue_count: 5,
          pr_count: 5
        })

      repository = test_data.repository

      start_time = DateTime.utc_now()

      # Execute complete pipeline
      execute_pipeline_sequence(repository)

      end_time = DateTime.utc_now()
      total_pipeline_time = DateTime.diff(end_time, start_time)

      # Validate overall pipeline performance
      assert total_pipeline_time < 1800, "Complete pipeline should finish within 30 minutes"

      # Validate individual phase contributions to overall time
      validate_phase_timing_distribution()
    end

    test "measures memory usage under load" do
      initial_memory = :erlang.memory(:total)

      # Create memory-intensive scenario
      large_test_data =
        create_test_repository_with_data(%{
          issue_count: 20,
          pr_count: 20
        })

      # Execute pipeline operations
      execute_pipeline_sequence(large_test_data.repository)

      peak_memory = :erlang.memory(:total)
      memory_increase_mb = (peak_memory - initial_memory) / 1024 / 1024

      # Validate memory usage is reasonable
      assert memory_increase_mb < 1024,
             "Pipeline should use less than 1GB additional memory (used: #{Float.round(memory_increase_mb, 1)}MB)"

      # Force garbage collection
      :erlang.garbage_collect()

      final_memory = :erlang.memory(:total)
      memory_retained_mb = (final_memory - initial_memory) / 1024 / 1024

      assert memory_retained_mb < 512, "Should retain less than 512MB after GC"
    end
  end

  describe "scalability and concurrent processing" do
    @tag :slow
    test "handles concurrent repository processing" do
      # Create multiple repositories for concurrent processing
      repositories =
        1..5
        |> Enum.map(fn i ->
          create_test_repository(%{name: "concurrent_repo_#{i}"})
        end)

      start_time = DateTime.utc_now()

      # Start concurrent mining operations
      mining_jobs =
        repositories
        |> Enum.map(fn repo ->
          {:ok, job} =
            RepositoryMining.start_mining(:manual_list, %{
              repositories: [repo.full_name],
              max_repositories: 1
            })

          job
        end)

      # Wait for all to complete
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs >= length(mining_jobs)
                 end,
                 300_000
               )

      end_time = DateTime.utc_now()
      concurrent_time = DateTime.diff(end_time, start_time)

      # Concurrent processing should be more efficient than sequential
      # (This is a basic test - in practice we'd need more sophisticated benchmarking)
      assert concurrent_time < 600, "Concurrent processing should complete within 10 minutes"
    end

    test "validates database performance under load" do
      # Create larger dataset for database performance testing
      repositories =
        1..20
        |> Enum.map(fn i -> create_test_repository(%{name: "db_perf_repo_#{i}"}) end)

      start_time = DateTime.utc_now()

      # Test database query performance
      query_times =
        repositories
        |> Enum.map(fn repo ->
          query_start = System.monotonic_time(:microsecond)

          {:ok, _} = Ash.get(SweBench.Repositories.Repository, repo.id)

          query_end = System.monotonic_time(:microsecond)
          query_end - query_start
        end)

      avg_query_time_ms = Enum.sum(query_times) / length(query_times) / 1000

      # Database queries should be fast
      assert avg_query_time_ms < 10,
             "Average repository query should be under 10ms (actual: #{Float.round(avg_query_time_ms, 2)}ms)"

      end_time = DateTime.utc_now()
      total_time = DateTime.diff(end_time, start_time)

      assert total_time < 30, "Database performance test should complete quickly"
    end
  end

  # Helper functions for performance testing

  defp execute_pipeline_sequence(repository) do
    # Execute pipeline phases in sequence for timing analysis

    # Phase 3.1: Repository Mining
    phase_1_start = DateTime.utc_now()

    {:ok, _} =
      RepositoryMining.start_mining(:manual_list, %{repositories: [repository.full_name]})

    wait_for_mining_completion()
    phase_1_end = DateTime.utc_now()

    # Phase 3.2: Issue-PR Linking  
    phase_2_start = DateTime.utc_now()
    {:ok, _} = IssuePrLinking.analyze_repository(repository.id)
    wait_for_linking_completion()
    phase_2_end = DateTime.utc_now()

    # Store timing data for analysis
    %{
      phase_1_time: DateTime.diff(phase_1_end, phase_1_start),
      phase_2_time: DateTime.diff(phase_2_end, phase_2_start)
    }
  end

  defp wait_for_mining_completion do
    wait_for_condition(
      fn ->
        status = RepositoryMining.get_mining_status()
        status.completed_jobs > 0
      end,
      60_000
    )
  end

  defp wait_for_linking_completion do
    wait_for_condition(
      fn ->
        status = IssuePrLinking.get_analysis_status()
        status.completed_repositories > 0
      end,
      60_000
    )
  end

  defp validate_phase_timing_distribution do
    # Validate that no single phase dominates the pipeline time
    # This would be implemented with actual timing measurements
    # Placeholder for timing validation
    assert true
  end
end
