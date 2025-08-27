defmodule SweBench.Distributed.TestCoordinator do
  @moduledoc """
  Coordinates test execution across distributed nodes.

  Extends existing TestRunner orchestration patterns for multi-node
  test coordination with synchronization barriers and result aggregation.
  """

  use GenServer
  require Logger

  alias SweBench.Distributed.NodeManager
  alias SweBench.TestRunner.Orchestrator

  defstruct [
    :active_distributed_tests,
    :node_assignments,
    :synchronization_barriers,
    :test_results
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a distributed test across multiple nodes.
  """
  def execute_distributed_test(test_spec, cluster_id) do
    GenServer.call(__MODULE__, {:execute_distributed_test, test_spec, cluster_id}, 300_000)
  end

  @doc """
  Handles node events from cluster changes.
  """
  def handle_node_event(event) do
    GenServer.cast(__MODULE__, {:node_event, event})
  end

  @doc """
  Gets distributed test statistics.
  """
  def get_test_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_distributed_tests: %{},
      node_assignments: %{},
      synchronization_barriers: %{},
      test_results: %{}
    }

    Logger.info("Distributed test coordinator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute_distributed_test, test_spec, cluster_id}, _from, state) do
    test_id = generate_test_id()
    Logger.info("Starting distributed test #{test_id} on cluster #{cluster_id}")

    result =
      test_spec
      |> validate_test_specification()
      |> assign_test_phases_to_nodes(cluster_id)
      |> create_synchronization_barriers()
      |> execute_coordinated_test()
      |> collect_distributed_results()

    case result do
      {:ok, test_results} ->
        test_info = %{
          test_id: test_id,
          cluster_id: cluster_id,
          test_spec: test_spec,
          results: test_results,
          status: :completed,
          started_at: DateTime.utc_now()
        }

        updated_state = %{
          state
          | test_results: Map.put(state.test_results, test_id, test_info)
        }

        {:reply, {:ok, test_results}, updated_state}

      {:error, reason} ->
        Logger.error("Distributed test #{test_id} failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    stats = %{
      total_distributed_tests: map_size(state.test_results),
      active_tests: map_size(state.active_distributed_tests),
      successful_tests: count_successful_tests(state.test_results),
      failed_tests: count_failed_tests(state.test_results)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:node_event, {:nodeup, node}}, state) do
    Logger.debug("Distributed test coordinator: Node #{node} connected")
    # Handle node connection for active tests
    {:noreply, state}
  end

  @impl true
  def handle_cast({:node_event, {:nodedown, node}}, state) do
    Logger.warning("Distributed test coordinator: Node #{node} disconnected")
    # Handle node disconnection for active tests
    {:noreply, state}
  end

  # Private implementation functions

  defp validate_test_specification(test_spec) do
    required_fields = [:test_type, :coordination_strategy]

    case validate_required_fields(test_spec, required_fields) do
      :ok -> {:ok, test_spec}
      {:error, missing} -> {:error, {:invalid_test_spec, missing}}
    end
  end

  defp assign_test_phases_to_nodes({:ok, test_spec}, cluster_id) do
    Logger.debug("Assigning test phases to cluster nodes")

    # Get available nodes from cluster
    case NodeManager.get_cluster_status(cluster_id) do
      cluster_status when is_map(cluster_status) ->
        available_nodes = cluster_status.connected_nodes

        if length(available_nodes) >= 2 do
          # Create node assignments based on test specification
          node_assignments = create_node_assignments(test_spec, available_nodes)
          {:ok, {test_spec, cluster_id, node_assignments}}
        else
          {:error, {:insufficient_nodes, length(available_nodes)}}
        end

      {:error, reason} ->
        {:error, {:cluster_status_failed, reason}}
    end
  end

  defp assign_test_phases_to_nodes({:error, reason}, _cluster_id) do
    {:error, reason}
  end

  defp create_synchronization_barriers({:ok, {test_spec, cluster_id, node_assignments}}) do
    Logger.debug("Creating synchronization barriers for coordinated execution")

    # Create barriers based on test coordination strategy
    coordination_strategy = Map.get(test_spec, :coordination_strategy, :sequential)

    barriers =
      case coordination_strategy do
        :sequential -> create_sequential_barriers(node_assignments)
        :parallel -> create_parallel_barriers(node_assignments)
        :coordinated -> create_coordinated_barriers(node_assignments)
      end

    {:ok, {test_spec, cluster_id, node_assignments, barriers}}
  end

  defp create_synchronization_barriers({:error, reason}) do
    {:error, reason}
  end

  defp execute_coordinated_test({:ok, {test_spec, cluster_id, node_assignments, barriers}}) do
    Logger.debug("Executing coordinated distributed test")

    # Use existing orchestrator pattern but with distributed coordination
    execution_tasks =
      node_assignments
      |> Enum.map(fn {node, test_phase} ->
        Task.async(fn ->
          execute_node_test_phase(node, test_phase, barriers)
        end)
      end)

    # Collect results with timeout
    case Task.await_many(execution_tasks, 180_000) do
      results when is_list(results) ->
        {:ok, {test_spec, cluster_id, results}}

      {:error, reason} ->
        {:error, {:execution_failed, reason}}
    end
  rescue
    error ->
      Logger.error("Distributed test execution failed: #{inspect(error)}")
      {:error, {:execution_exception, error}}
  end

  defp execute_coordinated_test({:error, reason}) do
    {:error, reason}
  end

  defp collect_distributed_results({:ok, {test_spec, cluster_id, execution_results}}) do
    Logger.debug("Collecting distributed test results")

    # Aggregate results from all nodes
    aggregated_results = %{
      test_spec: test_spec,
      cluster_id: cluster_id,
      node_results: execution_results,
      aggregation_timestamp: DateTime.utc_now(),
      result_summary: compile_result_summary(execution_results)
    }

    {:ok, aggregated_results}
  end

  defp collect_distributed_results({:error, reason}) do
    {:error, reason}
  end

  defp create_node_assignments(test_spec, available_nodes) do
    # Simple round-robin assignment for now
    test_phases =
      Map.get(test_spec, :phases, [%{type: :default, node_count: length(available_nodes)}])

    test_phases
    |> Enum.zip(available_nodes)
    |> Enum.map(fn {phase, node} ->
      {node, Map.put(phase, :assigned_node, node)}
    end)
    |> Map.new()
  end

  defp create_sequential_barriers(_node_assignments) do
    # Placeholder for sequential barrier creation
    %{barrier_1: :ready, barrier_2: :ready}
  end

  defp create_parallel_barriers(_node_assignments) do
    # Placeholder for parallel barrier creation
    %{start_barrier: :ready, completion_barrier: :ready}
  end

  defp create_coordinated_barriers(_node_assignments) do
    # Placeholder for coordinated barrier creation
    %{coordination_barrier: :ready}
  end

  defp execute_node_test_phase(node, test_phase, _barriers) do
    # Placeholder for node-specific test execution
    Logger.debug("Executing test phase on node #{node}")

    # Would integrate with existing Orchestrator here
    %{
      node: node,
      test_phase: test_phase,
      execution_result: :success,
      # Placeholder timing
      execution_time: :rand.uniform(5000),
      executed_at: DateTime.utc_now()
    }
  end

  defp compile_result_summary(execution_results) do
    successful_results = Enum.count(execution_results, &(&1.execution_result == :success))
    total_results = length(execution_results)

    %{
      total_nodes: total_results,
      successful_nodes: successful_results,
      failed_nodes: total_results - successful_results,
      success_rate: if(total_results > 0, do: successful_results / total_results, else: 0.0)
    }
  end

  defp validate_required_fields(spec, required_fields) do
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(spec, &1)))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, missing_fields}
    end
  end

  defp count_successful_tests(test_results) do
    test_results
    |> Map.values()
    |> Enum.count(&(&1.status == :completed))
  end

  defp count_failed_tests(test_results) do
    test_results
    |> Map.values()
    |> Enum.count(&(&1.status == :failed))
  end

  defp generate_test_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
