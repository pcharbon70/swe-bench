defmodule SweBench.Distributed.ClusterSupervisor do
  @moduledoc """
  Root supervisor for distributed testing infrastructure.

  Manages cluster formation, node coordination, distributed test execution,
  and network partition simulation with proper fault tolerance.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    cluster_config = build_cluster_config(opts)

    children = [
      # Global process registry for distributed coordination
      {Registry, keys: :unique, name: SweBench.Distributed.Registry},

      # Cluster formation and node management
      {SweBench.Distributed.NodeManager, cluster_config},

      # Multi-node container orchestration
      {SweBench.Distributed.ContainerOrchestrator, []},

      # Distributed test coordination
      {SweBench.Distributed.TestCoordinator, []},

      # Global registry for cluster-wide process registration
      {SweBench.Distributed.GlobalRegistry, []},

      # Network partition detection and simulation
      {SweBench.Distributed.PartitionDetector, []},

      # Distributed system performance monitoring
      {SweBench.Distributed.MetricsCollector, []}
    ]

    Logger.info("Starting distributed testing infrastructure")

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Gets distributed infrastructure health status.
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
      distributed_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end),
      cluster_connectivity: check_cluster_connectivity()
    }
  end

  @doc """
  Gracefully shuts down distributed testing infrastructure.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful distributed infrastructure shutdown")

    # Stop test coordination first
    case GenServer.whereis(SweBench.Distributed.TestCoordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Clean up distributed clusters
    SweBench.Distributed.ContainerOrchestrator.destroy_all_clusters()

    Logger.info("Distributed infrastructure shutdown complete")
    :ok
  end

  # Private implementation functions

  defp build_cluster_config(opts) do
    %{
      default_cluster_size: Keyword.get(opts, :default_cluster_size, 3),
      erlang_distribution: Keyword.get(opts, :erlang_distribution, true),
      cluster_cookie: Keyword.get(opts, :cluster_cookie, generate_cluster_cookie()),
      node_discovery_strategy: Keyword.get(opts, :node_discovery_strategy, :docker_compose),
      network_configuration: build_network_config(opts)
    }
  end

  defp build_network_config(opts) do
    %{
      base_port: Keyword.get(opts, :base_port, 9000),
      network_name: Keyword.get(opts, :network_name, "swe_bench_cluster"),
      subnet: Keyword.get(opts, :subnet, "172.20.0.0/16"),
      enable_epmd: Keyword.get(opts, :enable_epmd, false)
    }
  end

  defp generate_cluster_cookie do
    :crypto.strong_rand_bytes(16) |> Base.encode32(case: :lower)
  end

  defp check_cluster_connectivity do
    connected_nodes = Node.list()

    %{
      local_node: Node.self(),
      connected_nodes: connected_nodes,
      connectivity_health: if(length(connected_nodes) > 0, do: :connected, else: :isolated),
      cluster_size: length(connected_nodes) + 1
    }
  end
end