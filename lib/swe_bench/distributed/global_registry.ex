defmodule SweBench.Distributed.GlobalRegistry do
  @moduledoc """
  Distributed process registry using :global module for cluster-wide coordination.

  Provides cluster-wide process registration and discovery, extending existing
  Registry patterns for distributed testing scenarios.
  """

  require Logger

  @doc """
  Registers a process globally across the cluster.
  """
  def register_global(name, pid \\ self()) do
    case :global.register_name(name, pid) do
      :yes ->
        Logger.debug("Globally registered process: #{inspect(name)}")
        {:ok, name}

      :no ->
        Logger.warning("Failed to register process globally: #{inspect(name)} (already exists)")
        {:error, :already_registered}
    end
  end

  @doc """
  Unregisters a globally registered process.
  """
  def unregister_global(name) do
    case :global.unregister_name(name) do
      :ok ->
        Logger.debug("Globally unregistered process: #{inspect(name)}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to unregister process: #{inspect(name)} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Finds a globally registered process.
  """
  def whereis_global(name) do
    case :global.whereis_name(name) do
      :undefined -> nil
      pid -> pid
    end
  end

  @doc """
  Safe call to globally registered process with cluster-aware error handling.
  """
  def call_global(name, message, timeout \\ 5000) do
    case whereis_global(name) do
      nil ->
        {:error, :not_found}

      pid ->
        try do
          GenServer.call(pid, message, timeout)
        catch
          :exit, {:noproc, _} ->
            Logger.warning("Process #{inspect(name)} died during call")
            {:error, :process_died}

          :exit, {:nodedown, node} ->
            Logger.warning("Node #{node} disconnected during call to #{inspect(name)}")
            {:error, :node_disconnected}

          :exit, {:timeout, _} ->
            Logger.warning("Timeout calling globally registered process: #{inspect(name)}")
            {:error, :timeout}
        end
    end
  end

  @doc """
  Safe cast to globally registered process.
  """
  def cast_global(name, message) do
    case whereis_global(name) do
      nil ->
        {:error, :not_found}

      pid ->
        try do
          GenServer.cast(pid, message)
          :ok
        catch
          :exit, {:noproc, _} ->
            Logger.warning("Process #{inspect(name)} died during cast")
            {:error, :process_died}

          :exit, {:nodedown, node} ->
            Logger.warning("Node #{node} disconnected during cast to #{inspect(name)}")
            {:error, :node_disconnected}
        end
    end
  end

  @doc """
  Lists all globally registered processes in the cluster.
  """
  def list_global_processes do
    :global.registered_names()
    |> Enum.map(fn name ->
      %{
        name: name,
        pid: whereis_global(name),
        node: node_for_global_process(name)
      }
    end)
  end

  @doc """
  Synchronizes global registry state across cluster.
  """
  def sync_global_registry do
    case :global.sync() do
      :ok ->
        Logger.debug("Global registry synchronized")
        :ok

      {:error, reason} ->
        Logger.error("Failed to sync global registry: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets global registry statistics.
  """
  def get_registry_stats do
    global_processes = list_global_processes()

    %{
      total_global_processes: length(global_processes),
      processes_by_node: group_processes_by_node(global_processes),
      registry_sync_status: check_registry_sync_status(),
      cluster_wide_consistency: check_cluster_consistency()
    }
  end

  # Private helper functions

  defp node_for_global_process(name) do
    case whereis_global(name) do
      nil -> nil
      pid -> node(pid)
    end
  end

  defp group_processes_by_node(global_processes) do
    global_processes
    |> Enum.group_by(& &1.node)
    |> Enum.map(fn {node, processes} ->
      {node, length(processes)}
    end)
    |> Map.new()
  end

  defp check_registry_sync_status do
    # Check if registry is synchronized across nodes
    connected_nodes = Node.list()

    if Enum.empty?(connected_nodes) do
      :single_node
    else
      # Placeholder for comprehensive sync status check
      :synchronized
    end
  end

  defp check_cluster_consistency do
    # Placeholder for cluster consistency validation
    connected_nodes = Node.list()

    %{
      nodes_consistent: true,
      consistency_score: 1.0,
      inconsistencies: [],
      last_check: DateTime.utc_now(),
      cluster_size: length(connected_nodes) + 1
    }
  end
end