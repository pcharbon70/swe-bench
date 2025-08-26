defmodule SweBench.Distributed do
  @moduledoc """
  Main interface for distributed Elixir testing framework.

  Provides multi-node evaluation capabilities for testing AI models on
  distributed system scenarios including cluster formation, network partitions,
  and distributed process communication.
  """

  alias SweBench.Distributed.{NodeManager, TestCoordinator}

  @doc """
  Creates a multi-node cluster for distributed testing.

  ## Parameters
    - cluster_spec: Configuration for cluster nodes and networking
    - opts: Additional options for cluster creation

  ## Examples
      iex> SweBench.Distributed.create_cluster(%{nodes: 3, network: "test"})
      {:ok, %{cluster_id: "abc123", nodes: ["node1", "node2", "node3"]}}
  """
  def create_cluster(cluster_spec, opts \\ []) do
    SweBench.Distributed.ContainerOrchestrator.create_distributed_cluster(cluster_spec, opts)
  end

  @doc """
  Executes distributed tests across multiple nodes.
  """
  def execute_distributed_test(test_spec, cluster_id) do
    TestCoordinator.execute_distributed_test(test_spec, cluster_id)
  end

  @doc """
  Gets cluster status and node connectivity.
  """
  def get_cluster_status(cluster_id \\ nil) do
    NodeManager.get_cluster_status(cluster_id)
  end

  @doc """
  Simulates network partition for testing.
  """
  def simulate_network_partition(cluster_id, partition_spec) do
    SweBench.Distributed.PartitionDetector.simulate_partition(cluster_id, partition_spec)
  end

  @doc """
  Gets distributed performance metrics.
  """
  def get_distributed_metrics(cluster_id \\ nil) do
    SweBench.Distributed.MetricsCollector.get_cluster_metrics(cluster_id)
  end

  @doc """
  Lists active distributed clusters.
  """
  def list_active_clusters do
    SweBench.Distributed.ContainerOrchestrator.list_active_clusters()
  end

  @doc """
  Destroys a distributed cluster and cleans up resources.
  """
  def destroy_cluster(cluster_id) do
    SweBench.Distributed.ContainerOrchestrator.destroy_cluster(cluster_id)
  end
end
