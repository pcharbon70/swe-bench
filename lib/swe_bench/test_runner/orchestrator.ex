defmodule SweBench.TestRunner.Orchestrator do
  @moduledoc """
  Test execution orchestrator for managing ExUnit test runs with comprehensive control.

  This module handles:
  - Mix test environment configuration
  - Synchronous and asynchronous test execution
  - Timeout and infinite loop detection
  - Compilation error capture
  - Integration with container system
  - Test execution coordination
  """

  use GenServer
  require Logger

  alias SweBench.Container.Executor
  alias SweBench.TestRunner.Formatter

  defstruct [
    :active_executions,
    :config,
    :stats
  ]

  # Public API

  @doc """
  Starts the orchestrator GenServer.
  """
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, default_config())
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Starts a new test execution.
  """
  def start_execution(execution_id, project_path, opts \\ []) do
    GenServer.call(__MODULE__, {:start_execution, execution_id, project_path, opts})
  end

  @doc """
  Executes tests locally with custom formatter.
  """
  def execute_locally(execution_id, project_path, timeout, formatter_opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:execute_locally, execution_id, project_path, timeout, formatter_opts},
      # Add buffer to GenServer timeout
      timeout + 10_000
    )
  end

  @doc """
  Executes tests in a Docker container.
  """
  def execute_in_container(execution_id, container_id, timeout) do
    GenServer.call(
      __MODULE__,
      {:execute_in_container, execution_id, container_id, timeout},
      timeout + 10_000
    )
  end

  @doc """
  Gets list of active executions.
  """
  def active_executions do
    GenServer.call(__MODULE__, :active_executions)
  end

  @doc """
  Checks if orchestrator is running.
  """
  def running? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @doc """
  Stops the orchestrator.
  """
  def stop do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  # GenServer Implementation

  @impl GenServer
  def init(config) do
    Logger.info("Starting test execution orchestrator")

    state = %__MODULE__{
      active_executions: %{},
      config: config,
      stats: %{
        total_executions: 0,
        successful_executions: 0,
        failed_executions: 0,
        timeout_executions: 0
      }
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_execution, execution_id, project_path, opts}, _from, state) do
    Logger.info("Starting execution: #{execution_id} for project: #{project_path}")

    execution_info = %{
      id: execution_id,
      project_path: project_path,
      opts: opts,
      start_time: System.monotonic_time(:millisecond),
      status: :started
    }

    new_executions = Map.put(state.active_executions, execution_id, execution_info)
    new_state = %{state | active_executions: new_executions}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(
        {:execute_locally, execution_id, project_path, timeout, formatter_opts},
        from,
        state
      ) do
    Logger.info("Executing tests locally: #{execution_id}")

    # Start async execution
    task =
      Task.async(fn ->
        execute_tests_with_formatter(project_path, timeout, formatter_opts)
      end)

    # Update execution status
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:reply, {:error, :execution_not_found}, state}

      execution_info ->
        updated_execution = %{
          execution_info
          | status: :running,
            task: task,
            from: from,
            timeout: timeout
        }

        new_executions = Map.put(state.active_executions, execution_id, updated_execution)
        new_state = %{state | active_executions: new_executions}

        # Don't reply yet - will reply when execution completes
        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_call({:execute_in_container, execution_id, container_id, timeout}, from, state) do
    Logger.info("Executing tests in container: #{execution_id} -> #{container_id}")

    # Start async container execution
    task =
      Task.async(fn ->
        execute_tests_in_container(container_id, timeout)
      end)

    # Update execution status
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:reply, {:error, :execution_not_found}, state}

      execution_info ->
        updated_execution = %{
          execution_info
          | status: :running,
            task: task,
            from: from,
            container_id: container_id,
            timeout: timeout
        }

        new_executions = Map.put(state.active_executions, execution_id, updated_execution)
        new_state = %{state | active_executions: new_executions}

        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_call(:active_executions, _from, state) do
    active_list =
      state.active_executions
      |> Enum.map(fn {id, execution} ->
        %{
          id: id,
          project_path: execution.project_path,
          status: execution.status,
          start_time: execution.start_time,
          container_id: Map.get(execution, :container_id)
        }
      end)

    {:reply, active_list, state}
  end

  @impl GenServer
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    # Find execution by task reference
    case find_execution_by_task_ref(state.active_executions, task_ref) do
      {execution_id, execution} ->
        handle_execution_result(execution_id, execution, result, state)

      nil ->
        Logger.warning("Received result for unknown task: #{inspect(task_ref)}")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.debug("Task process down with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.info("Test orchestrator terminating")

    # Cancel any running executions
    Enum.each(state.active_executions, fn {_id, execution} ->
      if Map.has_key?(execution, :task) do
        Task.shutdown(execution.task, :brutal_kill)
      end
    end)

    :ok
  end

  # Private Functions

  defp default_config do
    %{
      default_timeout: 300_000,
      max_concurrent: 5,
      force_sync: true,
      capture_compilation_errors: true,
      environment_variables: %{
        "MIX_ENV" => "test",
        "EXUNIT_ASSERT_RECEIVE_TIMEOUT" => "1000",
        "EXUNIT_CAPTURE_LOG" => "true"
      }
    }
  end

  defp execute_tests_with_formatter(project_path, timeout, formatter_opts) do
    Logger.debug("Executing tests with formatter in: #{project_path}")

    # Change to project directory
    original_cwd = File.cwd!()

    try do
      File.cd!(project_path)

      # Configure environment for deterministic execution
      configure_test_environment()

      # Start formatter for this execution
      {:ok, _formatter_pid} = Formatter.start_link(formatter_opts)

      # Configure ExUnit with our custom formatter
      ExUnit.configure(
        formatters: [SweBench.TestRunner.Formatter],
        timeout: timeout,
        capture_log: true,
        assert_receive_timeout: 1_000,
        exclude: [],
        include: [],
        trace: false,
        slowest: 0,
        max_failures: :infinity
      )

      # Execute tests with timeout
      start_time = System.monotonic_time(:millisecond)

      result =
        try do
          # Force synchronous execution
          System.put_env("EXUNIT_ASYNC", "false")

          # Run tests and capture results
          case execute_mix_test(timeout) do
            {:ok, exit_code} ->
              # Get results from formatter
              results = Formatter.get_results()
              Formatter.stop()
              {:ok, Map.merge(results, %{exit_code: exit_code})}

            {:error, reason} ->
              {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            {:error, :execution_timeout}
        end

      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      case result do
        {:ok, results} ->
          {:ok, Map.put(results, :total_execution_time, execution_time)}

        {:error, reason} ->
          {:error, {reason, execution_time}}
      end
    after
      File.cd!(original_cwd)
    end
  end

  defp execute_tests_in_container(container_id, timeout) do
    Logger.debug("Executing tests in container: #{container_id}")

    # Use the container executor to run tests with our formatter
    test_command = [
      "bash",
      "-c",
      """
      cd /opt/app/execution && \
      export MIX_ENV=test && \
      export EXUNIT_ASYNC=false && \
      export EXUNIT_CAPTURE_LOG=true && \
      timeout #{div(timeout, 1000)} mix test --formatter SweBench.TestRunner.Formatter
      """
    ]

    case Executor.execute_command(container_id, "sh", [
           "-c",
           Enum.join(test_command, " ")
         ]) do
      {:ok, output} ->
        # Parse output to extract results
        parse_container_test_output(output)

      {:error, {exit_code, error_output}} ->
        {:error, {:container_execution_failed, exit_code, error_output}}
    end
  end

  defp configure_test_environment do
    # Set environment variables for deterministic test execution
    System.put_env("MIX_ENV", "test")
    System.put_env("EXUNIT_ASYNC", "false")
    System.put_env("EXUNIT_CAPTURE_LOG", "true")
    System.put_env("EXUNIT_ASSERT_RECEIVE_TIMEOUT", "1000")

    # Configure ExUnit for deterministic behavior
    ExUnit.configure(
      capture_log: true,
      assert_receive_timeout: 1_000,
      timeout: 60_000,
      trace: false
    )
  end

  defp execute_mix_test(timeout) do
    # Execute mix test command with timeout
    args = [
      "test",
      "--formatter",
      "SweBench.TestRunner.Formatter",
      "--timeout",
      "#{timeout}",
      # Assume already compiled
      "--no-compile"
    ]

    case System.cmd("mix", args,
           stderr_to_stdout: true,
           timeout: timeout,
           env: [{"MIX_ENV", "test"}]
         ) do
      {output, exit_code} ->
        Logger.debug("Mix test completed with exit code: #{exit_code}")
        Logger.debug("Output (first 500 chars): #{String.slice(output, 0, 500)}")
        {:ok, exit_code}

      error ->
        Logger.error("Mix test execution failed: #{inspect(error)}")
        {:error, {:mix_test_failed, error}}
    end
  rescue
    error ->
      Logger.error("Exception during mix test: #{inspect(error)}")
      {:error, {:exception_during_test, error}}
  end

  defp parse_container_test_output(output) do
    # Parse the output from container test execution
    # This is a simplified parser - in production would be more sophisticated

    cond do
      String.contains?(output, "0 failures") ->
        {:ok,
         %{
           exit_code: 0,
           output: output,
           success: true,
           container_execution: true
         }}

      String.contains?(output, "failures") ->
        {:ok,
         %{
           exit_code: 1,
           output: output,
           success: false,
           container_execution: true
         }}

      String.contains?(output, "timeout") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           exit_code: 2,
           output: output,
           success: false,
           container_execution: true,
           unknown_result: true
         }}
    end
  end

  defp find_execution_by_task_ref(executions, task_ref) do
    Enum.find_value(executions, fn {id, execution} ->
      if Map.has_key?(execution, :task) and execution.task.ref == task_ref do
        {id, execution}
      end
    end)
  end

  defp handle_execution_result(execution_id, execution, result, state) do
    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - execution.start_time

    Logger.info("Execution #{execution_id} completed in #{execution_time}ms")

    # Reply to caller
    GenServer.reply(execution.from, result)

    # Update statistics
    success = match?({:ok, _}, result)
    new_stats = update_execution_stats(state.stats, success, execution_time)

    # Remove from active executions
    new_executions = Map.delete(state.active_executions, execution_id)

    new_state = %{state | active_executions: new_executions, stats: new_stats}

    {:noreply, new_state}
  end

  defp update_execution_stats(stats, success, _execution_time) do
    new_total = stats.total_executions + 1

    new_stats = %{stats | total_executions: new_total}

    if success do
      %{new_stats | successful_executions: new_stats.successful_executions + 1}
    else
      %{new_stats | failed_executions: new_stats.failed_executions + 1}
    end
  end
end
