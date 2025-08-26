defmodule SweBench.Distributed.ContainerOrchestrator do
  @moduledoc """
  Orchestrates containers for distributed testing scenarios.

  Manages multi-node container deployment, networking, and lifecycle
  building on existing AdvancedPool container management patterns.
  """

  use GenServer
  require Logger

  alias SweBench.Container.AdvancedPool.PoolManager

  defstruct [
    :active_clusters,
    :cluster_networks,
    :container_mappings,
    :cluster_templates
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a distributed cluster with multiple nodes.
  """
  def create_distributed_cluster(cluster_spec, opts \\ []) do
    GenServer.call(__MODULE__, {:create_cluster, cluster_spec, opts}, 120_000)
  end

  @doc """
  Lists all active distributed clusters.
  """
  def list_active_clusters do
    GenServer.call(__MODULE__, :list_clusters)
  end

  @doc """
  Destroys a specific cluster and cleans up resources.
  """
  def destroy_cluster(cluster_id) do
    GenServer.call(__MODULE__, {:destroy_cluster, cluster_id})
  end

  @doc """
  Destroys all clusters (used for cleanup).
  """
  def destroy_all_clusters do
    GenServer.call(__MODULE__, :destroy_all_clusters)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_clusters: %{},
      cluster_networks: %{},
      container_mappings: %{},
      cluster_templates: load_cluster_templates()
    }

    Logger.info("Container orchestrator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_cluster, cluster_spec, opts}, _from, state) do
    cluster_id = generate_cluster_id()
    Logger.info("Creating distributed cluster: #{cluster_id}")

    result =
      cluster_spec
      |> validate_cluster_specification()
      |> create_cluster_network(cluster_id)
      |> deploy_cluster_containers(cluster_id, opts)
      |> configure_erlang_distribution()
      |> compile_cluster_result(cluster_id)

    case result do
      {:ok, cluster_info} ->
        updated_state = %{
          state
          | active_clusters: Map.put(state.active_clusters, cluster_id, cluster_info),
            cluster_networks: Map.put(state.cluster_networks, cluster_id, cluster_info.network_info)
        }

        {:reply, {:ok, cluster_info}, updated_state}

      {:error, reason} ->
        Logger.error("Failed to create cluster #{cluster_id}: #{inspect(reason)}")
        cleanup_failed_cluster(cluster_id, state)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_clusters, _from, state) do
    cluster_list =
      state.active_clusters
      |> Enum.map(fn {cluster_id, cluster_info} ->
        %{
          cluster_id: cluster_id,
          node_count: length(cluster_info.nodes),
          status: cluster_info.status,
          created_at: cluster_info.created_at,
          network: cluster_info.network_info.network_name
        }
      end)

    {:reply, {:ok, cluster_list}, state}
  end

  @impl true
  def handle_call({:destroy_cluster, cluster_id}, _from, state) do
    Logger.info("Destroying cluster: #{cluster_id}")

    case Map.get(state.active_clusters, cluster_id) do
      nil ->
        {:reply, {:error, :cluster_not_found}, state}

      cluster_info ->
        cleanup_result = cleanup_cluster(cluster_info)

        updated_state = %{
          state
          | active_clusters: Map.delete(state.active_clusters, cluster_id),
            cluster_networks: Map.delete(state.cluster_networks, cluster_id)
        }

        {:reply, cleanup_result, updated_state}
    end
  end

  @impl true
  def handle_call(:destroy_all_clusters, _from, state) do
    Logger.info("Destroying all clusters")

    cleanup_results =
      state.active_clusters
      |> Enum.map(fn {cluster_id, cluster_info} ->
        {cluster_id, cleanup_cluster(cluster_info)}
      end)

    cleaned_state = %{
      state
      | active_clusters: %{},
        cluster_networks: %{}
    }

    {:reply, {:ok, cleanup_results}, cleaned_state}
  end

  # Private implementation functions

  defp validate_cluster_specification(cluster_spec) do
    required_fields = [:nodes, :network_config]
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(cluster_spec, &1)))

    if Enum.empty?(missing_fields) do
      {:ok, cluster_spec}
    else
      {:error, {:invalid_cluster_spec, missing_fields}}
    end
  end

  defp create_cluster_network({:ok, cluster_spec}, cluster_id) do
    network_name = "swe_bench_cluster_#{cluster_id}"

    # Placeholder for Docker network creation
    network_info = %{
      network_name: network_name,
      network_id: cluster_id,
      subnet: "172.20.0.0/16",
      created_at: DateTime.utc_now()
    }

    Logger.debug("Created cluster network: #{network_name}")
    {:ok, {cluster_spec, network_info}}
  end

  defp create_cluster_network({:error, reason}, _cluster_id) do
    {:error, reason}
  end

  defp deploy_cluster_containers({:ok, {cluster_spec, network_info}}, cluster_id, opts) do
    Logger.debug("Deploying containers for cluster #{cluster_id}")

    node_count = Map.get(cluster_spec, :nodes, 3)
    base_port = Map.get(opts, :base_port, 9000)

    containers =
      1..node_count
      |> Enum.map(fn i ->
        deploy_cluster_node(i, cluster_id, network_info, base_port + i - 1)
      end)

    successful_containers = Enum.filter(containers, &match?({:ok, _}, &1))
    failed_containers = Enum.filter(containers, &match?({:error, _}, &1))

    if length(successful_containers) >= 2 do
      container_info = Enum.map(successful_containers, fn {:ok, info} -> info end)
      {:ok, {cluster_spec, network_info, container_info}}
    else
      {:error, {:insufficient_containers, length(successful_containers), failed_containers}}
    end
  end

  defp deploy_cluster_containers({:error, reason}, _cluster_id, _opts) do
    {:error, reason}
  end

  defp deploy_cluster_node(node_index, cluster_id, network_info, port) do
    node_name = "node#{node_index}"
    container_name = "#{cluster_id}_#{node_name}"

    try do
      # Placeholder container deployment - will integrate with existing PoolManager
      _container_config = %{
        name: container_name,
        node_name: "#{node_name}@#{container_name}",
        port: port,
        network: network_info.network_name,
        cluster_id: cluster_id,
        erlang_distribution: true
      }

      # Simulate container creation for now
      Logger.debug("Deploying container: #{container_name} on port #{port}")

      {:ok, %{
        container_id: generate_container_id(),
        node_name: node_name,
        container_name: container_name,
        port: port,
        status: :running,
        deployed_at: DateTime.utc_now()
      }}
    rescue
      error ->
        Logger.error("Failed to deploy container #{container_name}: #{inspect(error)}")
        {:error, {container_name, error}}
    end
  end

  defp configure_erlang_distribution({:ok, {cluster_spec, network_info, container_info}}) do
    Logger.debug("Configuring Erlang distribution for cluster")

    # Placeholder for Erlang distribution configuration
    distribution_config = %{
      cookie: generate_erlang_cookie(),
      discovery_strategy: :docker_compose,
      epmd_enabled: false,
      static_ports: true
    }

    {:ok, {cluster_spec, network_info, container_info, distribution_config}}
  end

  defp configure_erlang_distribution({:error, reason}) do
    {:error, reason}
  end

  defp compile_cluster_result({:ok, {_cluster_spec, network_info, container_info, distribution_config}}, cluster_id) do
    cluster_result = %{
      cluster_id: cluster_id,
      nodes: extract_node_names(container_info),
      containers: container_info,
      network_info: network_info,
      distribution_config: distribution_config,
      status: :ready,
      created_at: DateTime.utc_now()
    }

    {:ok, cluster_result}
  end

  defp compile_cluster_result({:error, reason}, _cluster_id) do
    {:error, reason}
  end

  defp extract_node_names(container_info) do
    Enum.map(container_info, & &1.node_name)
  end

  defp cleanup_cluster(cluster_info) do
    Logger.debug("Cleaning up cluster: #{cluster_info.cluster_id}")

    # Cleanup containers
    container_cleanup_results =
      cluster_info.containers
      |> Enum.map(&cleanup_container/1)

    # Cleanup network (placeholder)
    network_cleanup = cleanup_network(cluster_info.network_info)

    cleanup_summary = %{
      containers_cleaned: length(Enum.filter(container_cleanup_results, &match?(:ok, &1))),
      containers_failed: length(Enum.filter(container_cleanup_results, &match?({:error, _}, &1))),
      network_cleanup: network_cleanup
    }

    {:ok, cleanup_summary}
  end

  defp cleanup_container(container_info) do
    # Placeholder for container cleanup
    Logger.debug("Cleaning up container: #{container_info.container_name}")
    :ok
  end

  defp cleanup_network(network_info) do
    # Placeholder for network cleanup
    Logger.debug("Cleaning up network: #{network_info.network_name}")
    :ok
  end

  defp cleanup_failed_cluster(cluster_id, _state) do
    Logger.warning("Cleaning up failed cluster: #{cluster_id}")
    # Cleanup any partially created resources
    :ok
  end

  defp load_cluster_templates do
    # Placeholder for loading cluster templates
    %{
      small_cluster: %{nodes: 3, network_config: %{subnet: "172.20.0.0/16"}},
      medium_cluster: %{nodes: 5, network_config: %{subnet: "172.21.0.0/16"}}
    }
  end

  defp generate_cluster_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_container_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  defp generate_erlang_cookie do
    :crypto.strong_rand_bytes(16) |> Base.encode32(case: :lower)
  end

  defp ping_cluster_nodes(connected_nodes) do
    connected_nodes
    |> Map.keys()
    |> Enum.map(fn node ->
      ping_result = Node.ping(node)
      {node, ping_result}
    end)
  end

  defp update_node_connectivity(current_nodes, ping_results) do
    ping_results
    |> Enum.reduce(current_nodes, fn {node, ping_result}, acc ->
      case Map.get(acc, node) do
        nil -> acc
        node_info ->
          case ping_result do
            :pong -> %{node_info | status: :connected, last_seen: DateTime.utc_now()}
            :pang -> %{node_info | status: :disconnected}
          end
          |> then(&Map.put(acc, node, &1))
      end
    end)
  end
end