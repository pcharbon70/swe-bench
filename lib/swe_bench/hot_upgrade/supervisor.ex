defmodule SweBench.HotUpgrade.Supervisor do
  @moduledoc """
  OTP supervision tree for hot code reloading evaluation infrastructure.

  Manages upgrade coordinators, state migration testers, release managers,
  and quality assessors with proper fault tolerance and resource management.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    max_concurrent_upgrades = Keyword.get(opts, :max_concurrent_upgrades, 3)
    enable_monitoring = Keyword.get(opts, :monitoring, true)

    children = [
      # Upgrade evaluation coordination
      {SweBench.HotUpgrade.UpgradeCoordinator, [max_concurrent: max_concurrent_upgrades]},

      # Dynamic supervisor for upgrade evaluation workers
      {DynamicSupervisor,
       name: SweBench.HotUpgrade.WorkerSupervisor, strategy: :one_for_one},

      # Core upgrade evaluation components
      {SweBench.HotUpgrade.ReleaseManager, []},
      {SweBench.HotUpgrade.StateMigrationTester, []},
      {SweBench.HotUpgrade.UpgradeOrchestrator, []},

      # Zero-downtime validation
      {SweBench.HotUpgrade.DowntimeValidator, []},

      # Upgrade quality assessment
      {SweBench.HotUpgrade.QualityAssessor, []},

      # Result aggregation and monitoring
      {SweBench.HotUpgrade.ResultAggregator, []},

      # Upgrade-specific metrics collection
      {SweBench.HotUpgrade.UpgradeMetrics, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.HotUpgrade.Monitor, []} | children]
      else
        children
      end

    Logger.info("Starting hot upgrade evaluation infrastructure with #{max_concurrent_upgrades} max concurrent upgrades")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets hot upgrade evaluation infrastructure health status.
  """
  def health_check do
    children = Supervisor.which_children(__MODULE__)

    health_status =
      Enum.map(children, fn {id, pid, _type, _modules} ->
        case Process.alive?(pid) do
          true -> {id, :healthy}
          false -> {id, :unhealthy}
        end
      end)

    %{
      upgrade_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end),
      distributed_integration: check_distributed_integration()
    }
  end

  @doc """
  Gracefully shuts down hot upgrade evaluation operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful hot upgrade evaluation infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.HotUpgrade.UpgradeCoordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active upgrade evaluation workers
    DynamicSupervisor.which_children(SweBench.HotUpgrade.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.HotUpgrade.WorkerSupervisor, pid)
    end)

    Logger.info("Hot upgrade evaluation infrastructure shutdown complete")
    :ok
  end

  # Private implementation functions

  defp check_distributed_integration do
    # Check integration with Phase 4.1 distributed infrastructure
    distributed_supervisor_pid = GenServer.whereis(SweBench.Distributed.ClusterSupervisor)

    %{
      distributed_available: not is_nil(distributed_supervisor_pid) and Process.alive?(distributed_supervisor_pid),
      cluster_coordination: check_cluster_coordination_health(),
      container_orchestration: check_container_orchestration_health()
    }
  end

  defp check_cluster_coordination_health do
    case SweBench.Distributed.get_cluster_status() do
      cluster_status when is_map(cluster_status) ->
        %{
          status: :available,
          cluster_size: cluster_status.cluster_size,
          connectivity_health: cluster_status.connectivity_health
        }

      _ ->
        %{status: :unavailable, reason: :no_cluster}
    end
  end

  defp check_container_orchestration_health do
    case SweBench.Distributed.list_active_clusters() do
      {:ok, clusters} ->
        %{
          status: :available,
          active_clusters: length(clusters),
          orchestration_health: :healthy
        }

      {:error, reason} ->
        %{status: :unavailable, reason: reason}
    end
  end
end