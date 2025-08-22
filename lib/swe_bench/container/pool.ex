defmodule SweBench.Container.Pool do
  @moduledoc """
  Container pool management for improved performance and resource utilization.

  Provides:
  - Pre-warmed container pools
  - Container checkout/checkin system
  - Health monitoring and auto-scaling
  - Resource management and cleanup
  """

  use GenServer
  require Logger

  alias SweBench.Container.Builder

  defstruct [
    :id,
    :config,
    :containers,
    :available,
    :checked_out,
    :stats
  ]

  @doc """
  Creates a new container pool.
  """
  def create(pool_id, config) do
    GenServer.start_link(__MODULE__, {pool_id, config}, name: via_tuple(pool_id))
  end

  @doc """
  Destroys a container pool and cleans up all containers.
  """
  def destroy(pool_id) do
    case GenServer.whereis(via_tuple(pool_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @doc """
  Checks out a container from any available pool.
  """
  def checkout_container(pools) do
    pools
    |> Enum.find_value(fn {pool_id, _pool} ->
      case checkout(pool_id) do
        {:ok, container_id} -> {:ok, container_id}
        {:error, :no_containers} -> nil
      end
    end) || {:error, :no_available_containers}
  end

  @doc """
  Returns a container to its appropriate pool.
  """
  def checkin_container(pools, container_id) do
    # Find which pool this container belongs to and return it
    pools
    |> Enum.find_value(fn {pool_id, _pool} ->
      case checkin(pool_id, container_id) do
        :ok -> :ok
        {:error, :not_found} -> nil
      end
    end) || {:error, :container_not_found}
  end

  @doc """
  Checks out a container from a specific pool.
  """
  def checkout(pool_id) do
    GenServer.call(via_tuple(pool_id), :checkout)
  end

  @doc """
  Checks in a container to a specific pool.
  """
  def checkin(pool_id, container_id) do
    GenServer.call(via_tuple(pool_id), {:checkin, container_id})
  end

  @doc """
  Gets the status of a specific pool.
  """
  def status(pool_id) do
    GenServer.call(via_tuple(pool_id), :status)
  end

  @doc """
  Performs health check on a pool.
  """
  def health_check(pool_id) do
    GenServer.cast(via_tuple(pool_id), :health_check)
  end

  @doc """
  Scales a pool to a new size.
  """
  def scale(pool_id, new_size) do
    GenServer.call(via_tuple(pool_id), {:scale, new_size})
  end

  # GenServer Implementation

  @impl GenServer
  def init({pool_id, config}) do
    Logger.info("Starting container pool: #{pool_id}")

    state = %__MODULE__{
      id: pool_id,
      config: config,
      containers: %{},
      available: :queue.new(),
      checked_out: MapSet.new(),
      stats: %{
        created: 0,
        destroyed: 0,
        checkouts: 0,
        checkins: 0,
        health_checks: 0
      }
    }

    # Start with initial pool size
    initial_size = Map.get(config, :pool_size, 3)
    {:ok, warm_pool(state, initial_size)}
  end

  @impl GenServer
  def handle_call(:checkout, _from, state) do
    case :queue.out(state.available) do
      {{:value, container_id}, new_available} ->
        # Mark container as checked out
        new_checked_out = MapSet.put(state.checked_out, container_id)
        new_stats = %{state.stats | checkouts: state.stats.checkouts + 1}

        new_state = %{
          state
          | available: new_available,
            checked_out: new_checked_out,
            stats: new_stats
        }

        Logger.debug("Pool #{state.id}: Checked out container #{container_id}")
        {:reply, {:ok, container_id}, new_state}

      {:empty, _} ->
        # Try to create a new container if under limit
        max_containers = Map.get(state.config, :max_containers, 10)
        current_count = map_size(state.containers)

        if current_count < max_containers do

          handle_new_container_creation(state)

        else
          Logger.warning("Pool #{state.id}: No containers available and at maximum capacity")
          {:reply, {:error, :no_containers}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:checkin, container_id}, _from, state) do
    if MapSet.member?(state.checked_out, container_id) do
      # Verify container is still healthy
      case verify_container_health(container_id) do
        :ok ->
          # Return container to available pool
          new_available = :queue.in(container_id, state.available)
          new_checked_out = MapSet.delete(state.checked_out, container_id)
          new_stats = %{state.stats | checkins: state.stats.checkins + 1}

          new_state = %{
            state
            | available: new_available,
              checked_out: new_checked_out,
              stats: new_stats
          }

          Logger.debug("Pool #{state.id}: Checked in container #{container_id}")
          {:reply, :ok, new_state}

        {:error, reason} ->
          Logger.warning(
            "Pool #{state.id}: Container #{container_id} failed health check: #{inspect(reason)}"
          )

          # Remove unhealthy container
          new_state = remove_container_from_pool(state, container_id)
          {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status_info = %{
      pool_id: state.id,
      total_containers: map_size(state.containers),
      available_containers: :queue.len(state.available),
      checked_out_containers: MapSet.size(state.checked_out),
      statistics: state.stats,
      config: state.config
    }

    {:reply, status_info, state}
  end

  @impl GenServer
  def handle_call({:scale, new_size}, _from, state) do
    current_size = map_size(state.containers)

    cond do
      new_size > current_size ->
        # Scale up
        containers_to_add = new_size - current_size
        new_state = warm_pool(state, containers_to_add)
        Logger.info("Pool #{state.id}: Scaled up to #{new_size} containers")
        {:reply, :ok, new_state}

      new_size < current_size ->
        # Scale down
        containers_to_remove = current_size - new_size
        new_state = scale_down_pool(state, containers_to_remove)
        Logger.info("Pool #{state.id}: Scaled down to #{new_size} containers")
        {:reply, :ok, new_state}

      true ->
        # No change needed
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast(:health_check, state) do
    Logger.debug("Pool #{state.id}: Performing health check")

    new_state = perform_pool_health_check(state)
    new_stats = %{new_state.stats | health_checks: new_state.stats.health_checks + 1}

    {:noreply, %{new_state | stats: new_stats}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("Pool #{state.id}: Shutting down, cleaning up containers")
    cleanup_all_containers(state)
    :ok
  end

  # Private Functions

  defp via_tuple(pool_id) do
    {:via, Registry, {SweBench.Container.PoolRegistry, pool_id}}
  end

  defp warm_pool(state, count) when count > 0 do
    Logger.info("Pool #{state.id}: Warming pool with #{count} containers")

    Enum.reduce(1..count, state, fn _, acc_state ->
      case create_new_container(acc_state) do
        {:ok, container_id, new_state} ->
          # Add to available queue
          new_available = :queue.in(container_id, new_state.available)
          %{new_state | available: new_available}

        {:error, reason} ->
          Logger.warning(
            "Pool #{state.id}: Failed to create container during warming: #{inspect(reason)}"
          )

          acc_state
      end
    end)
  end

  defp warm_pool(state, _count), do: state

  defp create_new_container(state) do
    case Builder.create_instance_container(state.config) do
      {:ok, container_id} ->
        # Store container info
        container_info = %{
          id: container_id,
          created_at: DateTime.utc_now(),
          health_checks: 0,
          last_used: nil
        }

        new_containers = Map.put(state.containers, container_id, container_info)
        new_stats = %{state.stats | created: state.stats.created + 1}

        new_state = %{state | containers: new_containers, stats: new_stats}

        Logger.debug("Pool #{state.id}: Created container #{container_id}")
        {:ok, container_id, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_container_from_pool(state, container_id) do
    Logger.debug("Pool #{state.id}: Removing container #{container_id}")

    # Remove from Docker
    Builder.remove_container(container_id)

    # Update state
    new_containers = Map.delete(state.containers, container_id)
    new_available = :queue.filter(fn id -> id != container_id end, state.available)
    new_checked_out = MapSet.delete(state.checked_out, container_id)
    new_stats = %{state.stats | destroyed: state.stats.destroyed + 1}

    %{
      state
      | containers: new_containers,
        available: new_available,
        checked_out: new_checked_out,
        stats: new_stats
    }
  end

  defp verify_container_health(container_id) do
    # Run a simple health check on the container
    inspect_args = ["inspect", "--format={{.State.Running}}", container_id]

    case System.cmd("docker", inspect_args, stderr_to_stdout: true) do
      {"true\n", 0} -> :ok
      {_output, _code} -> {:error, :not_running}
    end
  end

  defp perform_pool_health_check(state) do
    Logger.debug("Pool #{state.id}: Checking health of #{map_size(state.containers)} containers")

    # Check all containers and remove unhealthy ones
    Enum.reduce(state.containers, state, fn {container_id, _info}, acc_state ->
      case verify_container_health(container_id) do
        :ok ->
          acc_state

        {:error, reason} ->
          Logger.warning("Pool #{state.id}: Container #{container_id} unhealthy: #{inspect(reason)}")
          remove_container_from_pool(acc_state, container_id)
      end
    end)
  end

  defp scale_down_pool(state, containers_to_remove) do
    # Remove containers from available queue first
    available_list = :queue.to_list(state.available)
    {to_remove, to_keep} = Enum.split(available_list, containers_to_remove)

    # Remove the selected containers
    final_state =
      Enum.reduce(to_remove, state, fn container_id, acc_state ->
        remove_container_from_pool(acc_state, container_id)
      end)

    # Update available queue
    new_available = :queue.from_list(to_keep)
    %{final_state | available: new_available}
  end

  defp cleanup_all_containers(state) do
    Enum.each(state.containers, fn {container_id, _info} ->
      Builder.remove_container(container_id)
    end)
  end


  defp handle_new_container_creation(state) do
    case create_new_container(state) do
      {:ok, container_id, new_state} ->
        new_checked_out = MapSet.put(new_state.checked_out, container_id)
        new_stats = %{new_state.stats | checkouts: new_state.stats.checkouts + 1}
        final_state = %{new_state | checked_out: new_checked_out, stats: new_stats}
        {:reply, {:ok, container_id}, final_state}


      {:error, reason} ->
        Logger.warning("Pool #{state.id}: Failed to create container: #{inspect(reason)}")
        {:reply, {:error, :no_containers}, state}
    end
  end

end
