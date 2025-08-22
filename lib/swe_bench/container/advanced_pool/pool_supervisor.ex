defmodule SweBench.Container.AdvancedPool.PoolSupervisor do
  @moduledoc """
  Advanced container pool supervisor with dynamic scaling and health monitoring.

  Manages multiple container pools with predictive scaling, resource optimization,
  and comprehensive health monitoring for high-throughput evaluation processing.
  """

  use DynamicSupervisor
  require Logger

  alias SweBench.Container.AdvancedPool.PoolManager

  @doc """
  Starts the pool supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new container pool with specified configuration.
  """
  def create_pool(pool_id, config) do
    Logger.info("Creating container pool: #{pool_id}")

    child_spec = {PoolManager, [pool_id: pool_id, config: config]}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Successfully created pool #{pool_id} with pid #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to create pool #{pool_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Destroys a container pool and cleans up resources.
  """
  def destroy_pool(pool_id) do
    Logger.info("Destroying container pool: #{pool_id}")

    case find_pool_child(pool_id) do
      {:ok, pid} ->
        case DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            Logger.info("Successfully destroyed pool #{pool_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to destroy pool #{pool_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        Logger.warning("Pool #{pool_id} not found for destruction")
        {:error, :pool_not_found}
    end
  end

  @doc """
  Lists all active container pools.
  """
  def list_pools do
    children = DynamicSupervisor.which_children(__MODULE__)

    pools =
      Enum.map(children, fn {_id, pid, _type, _modules} ->
        try do
          PoolManager.get_pool_info(pid)
        catch
          _, _ -> %{pool_id: "unknown", status: :error}
        end
      end)

    {:ok, pools}
  end

  @doc """
  Gets comprehensive pool supervisor statistics.
  """
  def get_supervisor_stats do
    {:ok, pools} = list_pools()

    stats = %{
      total_pools: length(pools),
      active_pools: Enum.count(pools, &(&1.status == :active)),
      total_containers: Enum.sum(Enum.map(pools, &(&1.container_count || 0))),
      memory_usage: calculate_total_memory_usage(pools),
      cpu_usage: calculate_total_cpu_usage(pools)
    }

    {:ok, stats}
  end

  @doc """
  Triggers pool maintenance across all pools.
  """
  def trigger_maintenance do
    Logger.info("Triggering maintenance across all container pools")

    {:ok, pools} = list_pools()

    maintenance_results =
      Enum.map(pools, fn pool ->
        try do
          PoolManager.perform_maintenance(pool.pool_id)
          {pool.pool_id, :success}
        catch
          _, reason ->
            Logger.warning("Maintenance failed for pool #{pool.pool_id}: #{inspect(reason)}")
            {pool.pool_id, {:error, reason}}
        end
      end)

    {:ok, maintenance_results}
  end

  # DynamicSupervisor callbacks

  @impl DynamicSupervisor
  def init(opts) do
    max_children = Keyword.get(opts, :max_pools, 50)

    Logger.info("Starting PoolSupervisor with max_pools=#{max_children}")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: max_children
    )
  end

  # Private helper functions

  defp find_pool_child(pool_id) do
    children = DynamicSupervisor.which_children(__MODULE__)

    found_child =
      Enum.find(children, fn {_id, pid, _type, _modules} ->
        try do
          pool_info = PoolManager.get_pool_info(pid)
          pool_info.pool_id == pool_id
        catch
          _, _ -> false
        end
      end)

    case found_child do
      {_id, pid, _type, _modules} -> {:ok, pid}
      nil -> {:error, :not_found}
    end
  end

  defp calculate_total_memory_usage(pools) do
    pools
    |> Enum.map(&(&1.memory_usage_mb || 0))
    |> Enum.sum()
  end

  defp calculate_total_cpu_usage(pools) do
    pools
    |> Enum.map(&(&1.cpu_usage_percent || 0))
    |> Enum.sum()
    |> then(fn total -> total / max(1, length(pools)) end)
    |> round()
  end
end
