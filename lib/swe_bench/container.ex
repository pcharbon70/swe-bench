defmodule SweBench.Container do
  @moduledoc """
  Container orchestration module for Docker-based evaluation infrastructure.

  This module provides the core functionality for managing Docker containers
  optimized for BEAM VM evaluation, including:

  - Three-layer Docker architecture (base, environment, instance)
  - Container lifecycle management
  - Resource monitoring and limits
  - EPMD isolation for distributed Erlang
  - Container pooling and reuse
  """

  use GenServer
  require Logger

  alias SweBench.Container.{Builder, Executor, Pool}

  @default_config %{
    base_image: "swe-bench/base:latest",
    env_image: "swe-bench/env:latest",
    instance_image: "swe-bench/instance:latest",
    pool_size: 5,
    max_containers: 20,
    execution_timeout: 300_000,
    memory_limit: 4_294_967_296,
    cpu_limit: 4
  }

  # Client API

  @doc """
  Starts the container orchestration system.
  """
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, @default_config)
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Builds the three-layer Docker architecture.

  ## Examples

      iex> SweBench.Container.build_images()
      {:ok, %{base: "sha256:abc123", env: "sha256:def456", instance: "sha256:ghi789"}}
      
      iex> SweBench.Container.build_images(force: true)
      {:ok, %{base: "sha256:new123", env: "sha256:new456", instance: "sha256:new789"}}
  """
  def build_images(opts \\ []) do
    GenServer.call(__MODULE__, {:build_images, opts}, 60_000)
  end

  @doc """
  Creates and manages a container pool for improved performance.

  ## Examples

      iex> SweBench.Container.create_pool(size: 10)
      {:ok, pool_id}
  """
  def create_pool(opts \\ []) do
    GenServer.call(__MODULE__, {:create_pool, opts})
  end

  @doc """
  Executes a patch evaluation in an isolated container.

  ## Parameters

  - `patch_file` - Path to the patch file to apply
  - `base_commit` - Git commit to use as base
  - `project_path` - Path to the project being evaluated
  - `opts` - Additional options

  ## Examples

      iex> SweBench.Container.execute_evaluation(
      ...>   "/path/to/patch.diff",
      ...>   "abc123",
      ...>   "/path/to/project",
      ...>   timeout: 300_000
      ...> )
      {:ok, %{
        execution_id: "20231201_143022_patch", 
        exit_code: 0,
        test_results: %{passed: 10, failed: 0},
        execution_time: 45_000
      }}
  """
  def execute_evaluation(patch_file, base_commit, project_path, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:execute_evaluation, patch_file, base_commit, project_path, opts},
      opts[:timeout] || 600_000
    )
  end

  @doc """
  Gets the status of the container orchestration system.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Stops and cleans up all containers.
  """
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end

  # Server Implementation

  @impl GenServer
  def init(config) do
    Logger.info("Starting Container Orchestration System")

    state = %{
      config: config,
      pools: %{},
      active_executions: %{},
      images_built: false,
      stats: %{
        executions_total: 0,
        executions_successful: 0,
        executions_failed: 0,
        average_execution_time: 0
      }
    }

    # Initialize container system
    schedule_health_check()

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:build_images, opts}, _from, state) do
    Logger.info("Building Docker images...")

    case Builder.build_all_images(state.config, opts) do
      {:ok, image_ids} ->
        Logger.info("Successfully built images: #{inspect(image_ids)}")
        new_state = %{state | images_built: true}
        {:reply, {:ok, image_ids}, new_state}

      {:error, reason} ->
        Logger.error("Failed to build images: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:create_pool, opts}, _from, state) do
    pool_id = generate_pool_id()
    pool_config = Map.merge(state.config, Map.new(opts))

    case Pool.create(pool_id, pool_config) do
      {:ok, pool} ->
        new_pools = Map.put(state.pools, pool_id, pool)
        new_state = %{state | pools: new_pools}
        {:reply, {:ok, pool_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:execute_evaluation, patch_file, base_commit, project_path, opts}, from, state) do
    execution_id = generate_execution_id()

    # Find available container from pool or create new one
    case get_or_create_container(state) do
      {:ok, container_id} ->
        # Start execution asynchronously
        task =
          Task.async(fn ->
            Executor.execute_patch_evaluation(
              container_id,
              patch_file,
              base_commit,
              project_path,
              opts
            )
          end)

        # Track execution
        execution = %{
          id: execution_id,
          task: task,
          from: from,
          container_id: container_id,
          start_time: System.monotonic_time(:millisecond),
          patch_file: patch_file,
          base_commit: base_commit,
          project_path: project_path
        }

        new_executions = Map.put(state.active_executions, execution_id, execution)
        new_state = %{state | active_executions: new_executions}

        # Don't reply yet - will reply when execution completes
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status_info = %{
      images_built: state.images_built,
      active_pools: map_size(state.pools),
      active_executions: map_size(state.active_executions),
      statistics: state.stats,
      config: state.config
    }

    {:reply, status_info, state}
  end

  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    Logger.info("Cleaning up container system...")

    # Cancel active executions
    Enum.each(state.active_executions, fn {_id, execution} ->
      Task.shutdown(execution.task, :brutal_kill)
    end)

    # Clean up pools
    Enum.each(state.pools, fn {pool_id, _pool} ->
      Pool.destroy(pool_id)
    end)

    new_state = %{state | pools: %{}, active_executions: %{}}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle task completion
    case find_execution_by_pid(state.active_executions, pid) do
      {execution_id, execution} ->
        handle_execution_complete(execution_id, execution, reason, state)

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    perform_health_check(state)
    schedule_health_check()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    # Handle task result
    case find_execution_by_task_ref(state.active_executions, task_ref) do
      {execution_id, execution} ->
        handle_execution_result(execution_id, execution, result, state)

      nil ->
        {:noreply, state}
    end
  end

  # Private Functions

  defp generate_pool_id do
    "pool_#{System.unique_integer([:positive])}_#{:rand.uniform(9999)}"
  end

  defp generate_execution_id do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    "exec_#{timestamp}_#{:rand.uniform(9999)}"
  end

  defp get_or_create_container(state) do
    # Try to get container from existing pools first
    case Pool.checkout_container(state.pools) do
      {:ok, container_id} ->
        {:ok, container_id}

      {:error, :no_available_containers} ->
        # Create temporary container
        Builder.create_instance_container(state.config)
    end
  end

  defp find_execution_by_pid(executions, pid) do
    Enum.find_value(executions, fn {id, execution} ->
      if execution.task.pid == pid do
        {id, execution}
      end
    end)
  end

  defp find_execution_by_task_ref(executions, task_ref) do
    Enum.find_value(executions, fn {id, execution} ->
      if execution.task.ref == task_ref do
        {id, execution}
      end
    end)
  end

  defp handle_execution_complete(execution_id, execution, reason, state) do
    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - execution.start_time

    Logger.info("Execution #{execution_id} completed in #{execution_time}ms")

    # Reply to original caller
    result =
      case reason do
        :normal ->
          {:ok,
           %{
             execution_id: execution_id,
             execution_time: execution_time,
             status: :completed
           }}

        {:exit, exit_reason} ->
          {:error, {:execution_failed, exit_reason}}
      end

    GenServer.reply(execution.from, result)

    # Return container to pool
    Pool.checkin_container(state.pools, execution.container_id)

    # Update state
    new_executions = Map.delete(state.active_executions, execution_id)
    new_stats = update_execution_stats(state.stats, execution_time, reason == :normal)

    new_state = %{state | active_executions: new_executions, stats: new_stats}

    {:noreply, new_state}
  end

  defp handle_execution_result(execution_id, execution, result, state) do
    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - execution.start_time

    Logger.info("Execution #{execution_id} completed with result in #{execution_time}ms")

    # Add timing information to result
    enhanced_result =
      case result do
        {:ok, data} ->
          {:ok,
           Map.merge(data, %{
             execution_id: execution_id,
             execution_time: execution_time
           })}

        error ->
          error
      end

    # Reply to original caller
    GenServer.reply(execution.from, enhanced_result)

    # Return container to pool
    Pool.checkin_container(state.pools, execution.container_id)

    # Update state
    new_executions = Map.delete(state.active_executions, execution_id)
    success = match?({:ok, _}, result)
    new_stats = update_execution_stats(state.stats, execution_time, success)

    new_state = %{state | active_executions: new_executions, stats: new_stats}

    {:noreply, new_state}
  end

  defp update_execution_stats(stats, execution_time, success) do
    new_total = stats.executions_total + 1

    new_successful =
      if success, do: stats.executions_successful + 1, else: stats.executions_successful

    new_failed = if success, do: stats.executions_failed, else: stats.executions_failed + 1

    new_avg = (stats.average_execution_time * stats.executions_total + execution_time) / new_total

    %{
      executions_total: new_total,
      executions_successful: new_successful,
      executions_failed: new_failed,
      average_execution_time: round(new_avg)
    }
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end

  defp perform_health_check(state) do
    Logger.debug("Performing container system health check")

    # Check container pools
    Enum.each(state.pools, fn {pool_id, _pool} ->
      Pool.health_check(pool_id)
    end)

    # Check active executions for timeouts
    current_time = System.monotonic_time(:millisecond)
    timeout = state.config.execution_timeout

    Enum.each(state.active_executions, fn {execution_id, execution} ->
      if current_time - execution.start_time > timeout do
        Logger.warning("Execution #{execution_id} exceeded timeout, terminating")
        Task.shutdown(execution.task, :brutal_kill)
      end
    end)
  end
end
