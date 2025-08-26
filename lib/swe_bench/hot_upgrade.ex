defmodule SweBench.HotUpgrade do
  @moduledoc """
  Main interface for hot code reloading evaluation system.

  Provides controlled state migration evaluation capabilities for testing
  AI models on BEAM VM upgrade scenarios and zero-downtime deployment patterns.
  """

  alias SweBench.HotUpgrade.{ReleaseManager, StateMigrationTester, UpgradeCoordinator}

  @doc """
  Evaluates an upgrade scenario for a task instance.

  ## Parameters
    - task_instance_id: UUID of task instance to evaluate with upgrade scenario
    - upgrade_spec: Configuration for upgrade testing scenario

  ## Examples
      iex> SweBench.HotUpgrade.evaluate_upgrade(task_id, %{type: :state_migration})
      {:ok, %{state_preservation: 0.95, downtime_ms: 0}}
  """
  def evaluate_upgrade(task_instance_id, upgrade_spec) do
    UpgradeCoordinator.evaluate_upgrade(task_instance_id, upgrade_spec)
  end

  @doc """
  Tests state migration for a GenServer implementation.
  """
  def test_state_migration(genserver_code, old_state, new_state_spec) do
    StateMigrationTester.test_migration(genserver_code, old_state, new_state_spec)
  end

  @doc """
  Creates a release package for upgrade testing.
  """
  def create_release_package(project_path, version_spec) do
    ReleaseManager.create_release_package(project_path, version_spec)
  end

  @doc """
  Gets upgrade evaluation statistics and metrics.
  """
  def get_upgrade_statistics do
    UpgradeCoordinator.get_upgrade_statistics()
  end

  @doc """
  Validates zero-downtime capability for an upgrade scenario.
  """
  def validate_zero_downtime(cluster_id, upgrade_spec) do
    SweBench.HotUpgrade.DowntimeValidator.validate_zero_downtime(cluster_id, upgrade_spec)
  end

  @doc """
  Lists available upgrade evaluation scenarios.
  """
  def list_upgrade_scenarios do
    %{
      state_migration: %{
        description: "GenServer state transformation testing",
        complexity: :medium,
        duration_estimate: "2-5 minutes"
      },
      process_upgrade: %{
        description: "Supervisor child spec update testing",
        complexity: :high,
        duration_estimate: "5-10 minutes"
      },
      distributed_upgrade: %{
        description: "Multi-node upgrade coordination testing",
        complexity: :expert,
        duration_estimate: "10-15 minutes"
      }
    }
  end
end
