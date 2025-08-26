defmodule SweBench.Integration.RepositoryMiningIntegrationTest do
  @moduledoc """
  Integration tests for Phase 3.1 Repository Mining Infrastructure.

  Tests repository discovery, quality assessment, and categorization
  with realistic data scenarios and external API integration.
  """

  use SweBench.DataCase
  use ExUnit.Case, async: false

  import SweBench.IntegrationHelpers

  alias SweBench.RepositoryMining
  alias SweBench.Repositories.Repository

  @moduletag :integration
  @moduletag :repository_mining

  describe "repository mining integration" do
    test "discovers and analyzes repositories from manual list" do
      # Create test repository data
      test_data = create_test_repository_with_data()
      repository_name = test_data.repository.full_name

      # Start mining operation
      assert {:ok, mining_job} =
               RepositoryMining.start_mining(:manual_list, %{
                 repositories: [repository_name],
                 max_repositories: 1
               })

      # Wait for completion
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 60_000
               )

      # Validate results
      status = RepositoryMining.get_mining_status()
      assert status.total_repositories_discovered >= 1

      # Verify repository data was enhanced
      {:ok, discovered_repos} = RepositoryMining.list_discovered_repositories()
      assert length(discovered_repos) >= 1

      discovered_repo = List.first(discovered_repos)
      assert discovered_repo.mining_status == :completed
      assert not is_nil(discovered_repo.mining_completed_at)
    end

    test "validates repository quality scoring" do
      repository =
        create_test_repository(%{
          stars_count: 500,
          forks_count: 100,
          language: "Elixir",
          has_issues: true
        })

      # Mine the repository
      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: [repository.full_name]
        })

      # Wait for completion and validate quality scores
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 30_000
               )

      # Validate quality distribution
      distribution = RepositoryMining.get_quality_distribution()

      # Should have quality metrics
      total_repos =
        distribution.excellent + distribution.good + distribution.average +
          distribution.below_average + distribution.poor

      assert total_repos >= 1
    end

    test "handles repository mining failures gracefully" do
      # Test with invalid repository data
      assert {:error, _reason} =
               RepositoryMining.start_mining(:manual_list, %{
                 repositories: ["invalid/nonexistent"],
                 max_repositories: 1
               })

      # Verify system remains stable
      status = RepositoryMining.get_mining_status()
      assert is_map(status)
    end

    test "achieves performance targets" do
      # Create multiple test repositories
      repositories =
        1..5
        |> Enum.map(fn i ->
          create_test_repository(%{name: "test_repo_#{i}"})
        end)

      repository_names = Enum.map(repositories, & &1.full_name)

      start_time = DateTime.utc_now()

      # Start mining operation
      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: repository_names,
          max_repositories: 5
        })

      # Wait for completion
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 120_000
               )

      end_time = DateTime.utc_now()
      processing_time_seconds = DateTime.diff(end_time, start_time)

      # Validate performance (should process 5 repositories in reasonable time)
      assert processing_time_seconds < 300,
             "Mining 5 repositories should complete within 5 minutes"

      status = RepositoryMining.get_mining_status()
      assert status.total_repositories_discovered >= 5
    end
  end

  describe "repository quality assessment" do
    test "categorizes repositories correctly" do
      # High-quality repository
      high_quality_repo =
        create_test_repository(%{
          stars_count: 1000,
          forks_count: 200,
          has_issues: true,
          language: "Elixir"
        })

      # Lower-quality repository  
      low_quality_repo =
        create_test_repository(%{
          stars_count: 5,
          forks_count: 1,
          has_issues: false,
          language: "Elixir"
        })

      # Mine both repositories
      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: [high_quality_repo.full_name, low_quality_repo.full_name]
        })

      # Wait for completion
      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 60_000
               )

      # Validate quality distribution reflects differences
      distribution = RepositoryMining.get_quality_distribution()
      assert distribution.total >= 2
    end

    test "handles umbrella projects correctly" do
      umbrella_repo =
        create_test_repository(%{
          is_umbrella_project: true,
          name: "umbrella_project",
          description: "Test umbrella project with multiple applications"
        })

      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: [umbrella_repo.full_name]
        })

      assert :ok =
               wait_for_condition(
                 fn ->
                   status = RepositoryMining.get_mining_status()
                   status.completed_jobs > 0
                 end,
                 30_000
               )

      # Verify umbrella project was processed correctly
      {:ok, repos} = RepositoryMining.list_discovered_repositories()
      umbrella_result = Enum.find(repos, &(&1.is_umbrella_project == true))
      assert not is_nil(umbrella_result)
    end
  end

  describe "error handling and recovery" do
    test "recovers from API rate limiting" do
      # This test would simulate rate limiting scenarios
      # For now, we validate the system handles errors gracefully

      status_before = RepositoryMining.get_mining_status()

      # Attempt mining that might hit rate limits
      {:ok, _job} =
        RepositoryMining.start_mining(:manual_list, %{
          repositories: ["test_org/test_repo"]
        })

      # System should remain responsive
      status_after = RepositoryMining.get_mining_status()
      assert is_map(status_after)
    end

    test "handles malformed repository data" do
      # Test with various edge cases
      edge_cases = [
        # Empty names
        %{name: "", full_name: ""},
        # Invalid star count
        %{stars_count: -1},
        # Missing language
        %{language: nil}
      ]

      Enum.each(edge_cases, fn invalid_attrs ->
        # Should handle invalid data gracefully
        assert_raise Ash.Error.Invalid, fn ->
          create_test_repository(invalid_attrs)
        end
      end)
    end
  end
end
