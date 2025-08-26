defmodule SweBench.Distributed.NodeManager do
  @moduledoc """
  Manages Erlang distribution, node discovery, and cluster membership.

  Handles node connectivity, cluster formation, and integration with
  existing container infrastructure for distributed testing scenarios.
  """

  use GenServer
  require Logger

  defstruct [
    :cluster_config,
    :connected_nodes,
    :node_roles,
    :cluster_topology,
    :last_connectivity_check
  ]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Connects to a cluster of nodes.
  """
  def connect_to_cluster(node_names) when is_list(node_names) do
    GenServer.call(__MODULE__, {:connect_cluster, node_names})
  end

  @doc """
  Gets current cluster status and topology.
  """
  def get_cluster_status(cluster_id \\ nil) do
    GenServer.call(__MODULE__, {:get_cluster_status, cluster_id})
  end

  @doc """
  Gets cluster connectivity health.
  """
  def get_connectivity_health do
    GenServer.call(__MODULE__, :get_connectivity_health)
  end

  @doc """
  Handles node events from cluster changes.
  """
  def handle_node_event(event) do
    GenServer.cast(__MODULE__, {:node_event, event})
  end

  @impl true
  def init(config) do
    # Configure Erlang distribution monitoring
    :net_kernel.monitor_nodes(true, [{:node_type, :all}])

    state = %__MODULE__{
      cluster_config: config,
      connected_nodes: %{},
      node_roles: %{},
      cluster_topology: :single_node,
      last_connectivity_check: DateTime.utc_now()
    }

    # Start periodic connectivity monitoring
    schedule_connectivity_check()

    Logger.info("Node manager started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:connect_cluster, node_names}, _from, state) do
    Logger.info("Attempting to connect to cluster nodes: #{inspect(node_names)}")

    connection_results =
      node_names
      |> Enum.map(&attempt_node_connection/1)

    successful_connections =
      connection_results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, node} -> node end)

    failed_connections =
      connection_results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, {node, reason}} -> {node, reason} end)

    # Update connected nodes state
    new_connected_nodes =
      successful_connections
      |> Enum.map(&{&1, %{status: :connected, connected_at: DateTime.utc_now()}})
      |> Map.new()
      |> Map.merge(state.connected_nodes)

    updated_topology = determine_cluster_topology(Map.keys(new_connected_nodes))

    updated_state = %{
      state
      | connected_nodes: new_connected_nodes,
        cluster_topology: updated_topology
    }

    result = %{
      successful_connections: successful_connections,
      failed_connections: failed_connections,
      cluster_topology: updated_topology,
      # +1 for local node
      total_nodes: length(successful_connections) + 1
    }

    {:reply, {:ok, result}, updated_state}
  end

  @impl true
  def handle_call({:get_cluster_status, cluster_id}, _from, state) do
    cluster_status = %{
      cluster_id: cluster_id,
      local_node: Node.self(),
      connected_nodes: Map.keys(state.connected_nodes),
      cluster_size: map_size(state.connected_nodes) + 1,
      cluster_topology: state.cluster_topology,
      connectivity_health: calculate_connectivity_health(state),
      last_check: state.last_connectivity_check
    }

    {:reply, cluster_status, state}
  end

  @impl true
  def handle_call(:get_connectivity_health, _from, state) do
    health = %{
      total_expected_nodes: map_size(state.connected_nodes) + 1,
      connected_nodes: count_healthy_connections(state.connected_nodes),
      disconnected_nodes: count_failed_connections(state.connected_nodes),
      cluster_health_score: calculate_cluster_health_score(state),
      partition_detected: detect_network_partition(state)
    }

    {:reply, health, state}
  end

  @impl true
  def handle_cast({:node_event, {:nodeup, node}}, state) do
    Logger.info("Node connected: #{node}")

    updated_nodes =
      Map.put(state.connected_nodes, node, %{
        status: :connected,
        connected_at: DateTime.utc_now(),
        last_seen: DateTime.utc_now()
      })

    # Notify distributed test coordinator
    SweBench.Distributed.TestCoordinator.handle_node_event({:nodeup, node})

    updated_topology = determine_cluster_topology(Map.keys(updated_nodes))

    {:noreply, %{state | connected_nodes: updated_nodes, cluster_topology: updated_topology}}
  end

  @impl true
  def handle_cast({:node_event, {:nodedown, node}}, state) do
    Logger.warning("Node disconnected: #{node}")

    updated_nodes =
      case Map.get(state.connected_nodes, node) do
        nil ->
          state.connected_nodes

        node_info ->
          Map.put(state.connected_nodes, node, %{
            node_info
            | status: :disconnected,
              disconnected_at: DateTime.utc_now()
          })
      end

    # Notify distributed test coordinator
    SweBench.Distributed.TestCoordinator.handle_node_event({:nodedown, node})

    updated_topology = determine_cluster_topology(Map.keys(updated_nodes))

    {:noreply, %{state | connected_nodes: updated_nodes, cluster_topology: updated_topology}}
  end

  @impl true
  def handle_info(:connectivity_check, state) do
    Logger.debug("Performing cluster connectivity check")

    # Ping all expected nodes to verify connectivity
    connectivity_results = ping_cluster_nodes(state.connected_nodes)

    updated_state = %{
      state
      | last_connectivity_check: DateTime.utc_now(),
        connected_nodes: update_node_connectivity(state.connected_nodes, connectivity_results)
    }

    schedule_connectivity_check()
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp attempt_node_connection(node_name) when is_atom(node_name) do
    case Node.connect(node_name) do
      true ->
        Logger.debug("Successfully connected to node: #{node_name}")
        {:ok, node_name}

      false ->
        Logger.warning("Failed to connect to node: #{node_name}")
        {:error, {node_name, :connection_failed}}
    end
  end

  defp attempt_node_connection(node_name) when is_binary(node_name) do
    attempt_node_connection(String.to_atom(node_name))
  end

  defp determine_cluster_topology(connected_node_names) do
    # +1 for local node
    total_nodes = length(connected_node_names) + 1

    case total_nodes do
      1 -> :single_node
      2 -> :pair
      n when n <= 5 -> :small_cluster
      n when n <= 10 -> :medium_cluster
      _ -> :large_cluster
    end
  end

  defp calculate_connectivity_health(state) do
    total_nodes = map_size(state.connected_nodes) + 1
    # +1 for local
    healthy_nodes = count_healthy_connections(state.connected_nodes) + 1

    health_percentage = healthy_nodes / total_nodes

    cond do
      health_percentage >= 0.9 -> :excellent
      health_percentage >= 0.7 -> :good
      health_percentage >= 0.5 -> :degraded
      true -> :poor
    end
  end

  defp count_healthy_connections(connected_nodes) do
    connected_nodes
    |> Map.values()
    |> Enum.count(&(&1.status == :connected))
  end

  defp count_failed_connections(connected_nodes) do
    connected_nodes
    |> Map.values()
    |> Enum.count(&(&1.status == :disconnected))
  end

  defp calculate_cluster_health_score(state) do
    healthy_connections = count_healthy_connections(state.connected_nodes)
    total_expected = map_size(state.connected_nodes)

    if total_expected > 0 do
      healthy_connections / total_expected
    else
      # Single node is always healthy
      1.0
    end
  end

  defp detect_network_partition(state) do
    # Simple partition detection: if we have expected nodes but they're disconnected
    disconnected_nodes = count_failed_connections(state.connected_nodes)
    total_nodes = map_size(state.connected_nodes)

    # Consider it a partition if more than 30% of nodes are disconnected
    if total_nodes > 0 and disconnected_nodes / total_nodes > 0.3 do
      true
    else
      false
    end
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
      update_single_node_status(acc, node, ping_result)
    end)
  end

  defp update_single_node_status(nodes_map, node, ping_result) do
    case Map.get(nodes_map, node) do
      nil ->
        nodes_map

      node_info ->
        updated_info =
          case ping_result do
            :pong -> %{node_info | status: :connected, last_seen: DateTime.utc_now()}
            :pang -> %{node_info | status: :disconnected}
          end

        Map.put(nodes_map, node, updated_info)
    end
  end

  defp schedule_connectivity_check do
    # Check connectivity every 30 seconds
    Process.send_after(self(), :connectivity_check, 30_000)
  end
end
