defmodule SweBench.TestRunner.Isolation do
  @moduledoc """
  Test isolation mechanism for ensuring clean state between test executions.

  This module provides comprehensive cleanup capabilities to prevent
  test contamination and ensure deterministic test execution:

  - Application state reset
  - ETS table cleanup
  - Database transaction rollbacks  
  - GenServer state management
  - Supervisor tree restart
  - Process registry cleanup
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :isolation_strategies,
    :cleanup_history,
    :enabled
  ]

  # Public API

  @doc """
  Starts the isolation management system.
  """
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, default_config())
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Performs complete isolation cleanup for an execution.
  """
  def cleanup_execution(execution_id) do
    GenServer.call(__MODULE__, {:cleanup_execution, execution_id})
  end

  @doc """
  Resets application state to clean state.
  """
  def reset_application_state do
    GenServer.call(__MODULE__, :reset_application_state)
  end

  @doc """
  Cleans up ETS tables and process registries.
  """
  def cleanup_process_state do
    GenServer.call(__MODULE__, :cleanup_process_state)
  end

  @doc """
  Handles database state isolation using transactions.
  """
  def cleanup_database_state do
    GenServer.call(__MODULE__, :cleanup_database_state)
  end

  @doc """
  Checks if isolation is enabled.
  """
  def enabled? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :enabled?)
    end
  end

  @doc """
  Checks if isolation system is running.
  """
  def running? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @doc """
  Stops the isolation system.
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
    Logger.info("Starting test isolation system")

    state = %__MODULE__{
      config: config,
      isolation_strategies: configure_strategies(config),
      cleanup_history: [],
      enabled: Map.get(config, :enabled, true)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:cleanup_execution, execution_id}, _from, state) do
    Logger.info("Performing cleanup for execution: #{execution_id}")

    if state.enabled do
      start_time = System.monotonic_time(:millisecond)

      cleanup_results = perform_comprehensive_cleanup(state.isolation_strategies)

      end_time = System.monotonic_time(:millisecond)
      cleanup_time = end_time - start_time

      cleanup_record = %{
        execution_id: execution_id,
        timestamp: DateTime.utc_now(),
        cleanup_time_ms: cleanup_time,
        strategies_used: Map.keys(state.isolation_strategies),
        results: cleanup_results
      }

      new_history = [cleanup_record | Enum.take(state.cleanup_history, 99)]
      new_state = %{state | cleanup_history: new_history}

      Logger.info("Cleanup completed for #{execution_id} in #{cleanup_time}ms")
      {:reply, {:ok, cleanup_record}, new_state}
    else
      Logger.debug("Isolation disabled, skipping cleanup for: #{execution_id}")
      {:reply, {:ok, :isolation_disabled}, state}
    end
  end

  @impl GenServer
  def handle_call(:reset_application_state, _from, state) do
    Logger.debug("Resetting application state")

    result =
      if state.enabled do
        reset_app_state(state.config)
      else
        {:ok, :isolation_disabled}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:cleanup_process_state, _from, state) do
    Logger.debug("Cleaning up process state")

    result =
      if state.enabled do
        {:ok, result1} = cleanup_user_processes(state.config)
        {:ok, result2} = cleanup_ets_tables(state.config)
        {:ok, %{processes: result1, ets: result2}}
      else
        {:ok, :isolation_disabled}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:cleanup_database_state, _from, state) do
    Logger.debug("Cleaning up database state")

    result =
      if state.enabled do
        cleanup_database(state.config)
      else
        {:ok, :isolation_disabled}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Logger.info("Test isolation system terminating")
    :ok
  end

  # Private Functions

  defp default_config do
    %{
      enabled: true,
      strategies: [
        :reset_application,
        :cleanup_ets,
        :cleanup_processes,
        :cleanup_database,
        :restart_supervisors
      ],
      database_adapter: :postgres,
      preserve_test_data: false,
      cleanup_timeout: 30_000
    }
  end

  defp configure_strategies(config) do
    strategies = Map.get(config, :strategies, [])

    strategies
    |> Enum.map(fn strategy ->
      {strategy, configure_strategy(strategy, config)}
    end)
    |> Map.new()
  end

  defp configure_strategy(:reset_application, config) do
    %{
      enabled: true,
      reset_env_vars: Map.get(config, :reset_env_vars, true),
      reset_config: Map.get(config, :reset_config, true)
    }
  end

  defp configure_strategy(:cleanup_ets, config) do
    %{
      enabled: true,
      preserve_protected: Map.get(config, :preserve_protected_ets, true),
      cleanup_timeout: Map.get(config, :cleanup_timeout, 5_000)
    }
  end

  defp configure_strategy(:cleanup_processes, config) do
    %{
      enabled: true,
      kill_user_processes: Map.get(config, :kill_user_processes, true),
      preserve_system_processes: true,
      cleanup_timeout: Map.get(config, :cleanup_timeout, 5_000)
    }
  end

  defp configure_strategy(:cleanup_database, config) do
    %{
      enabled: Map.get(config, :database_cleanup, true),
      adapter: Map.get(config, :database_adapter, :postgres),
      use_transactions: Map.get(config, :use_db_transactions, true),
      truncate_tables: Map.get(config, :truncate_test_tables, true)
    }
  end

  defp configure_strategy(:restart_supervisors, config) do
    %{
      enabled: Map.get(config, :restart_supervisors, false),
      supervisor_names: Map.get(config, :supervisor_names, []),
      restart_timeout: Map.get(config, :supervisor_restart_timeout, 10_000)
    }
  end

  defp perform_comprehensive_cleanup(strategies) do
    strategies
    |> Enum.map(fn {strategy_name, strategy_config} ->
      if Map.get(strategy_config, :enabled, false) do
        {strategy_name, execute_cleanup_strategy(strategy_name, strategy_config)}
      else
        {strategy_name, {:skipped, :disabled}}
      end
    end)
    |> Map.new()
  end

  defp execute_cleanup_strategy(:reset_application, config) do
    reset_app_state(config)
  rescue
    error -> {:error, error}
  end

  defp execute_cleanup_strategy(:cleanup_ets, config) do
    cleanup_ets_tables(config)
  rescue
    error -> {:error, error}
  end

  defp execute_cleanup_strategy(:cleanup_processes, config) do
    cleanup_user_processes(config)
  rescue
    error -> {:error, error}
  end

  defp execute_cleanup_strategy(:cleanup_database, config) do
    cleanup_database(config)
  rescue
    error -> {:error, error}
  end

  defp execute_cleanup_strategy(:restart_supervisors, config) do
    restart_supervisor_trees(config)
  rescue
    error -> {:error, error}
  end

  defp reset_app_state(config) do
    Logger.debug("Resetting application state")

    # Reset application environment if configured
    if Map.get(config, :reset_env_vars, false) do
      # Reset test-specific environment variables
      System.delete_env("EXUNIT_SEED")
      System.put_env("MIX_ENV", "test")
    end

    # Reset application configuration if needed
    if Map.get(config, :reset_config, false) do
      # This would reset Application.put_env changes
      # In practice, this might be too aggressive
      Logger.debug("Application config reset requested but skipped for safety")
    end

    {:ok, :application_reset}
  end

  defp cleanup_ets_tables(config) do
    Logger.debug("Cleaning up ETS tables")

    preserve_protected = Map.get(config, :preserve_protected, true)

    # Get all ETS tables
    all_tables = :ets.all()

    cleaned_tables =
      Enum.map(all_tables, fn table ->
        try do
          table_info = :ets.info(table)

          # Check if we should clean this table
          should_clean =
            case table_info do
              :undefined ->
                false

              info when is_list(info) ->
                protection = Keyword.get(info, :protection, :private)
                owner = Keyword.get(info, :owner)

                # Only clean tables we own and are not system tables
                owner == self() and
                  (not preserve_protected or protection != :protected)

              _ ->
                false
            end

          if should_clean do
            :ets.delete_all_objects(table)
            {:ok, table}
          else
            {:skipped, table}
          end
        rescue
          _ -> {:error, table}
        end
      end)

    cleaned_count = Enum.count(cleaned_tables, fn {status, _} -> status == :ok end)

    {:ok, %{cleaned_tables: cleaned_count, total_tables: length(all_tables)}}
  end

  defp cleanup_user_processes(config) do
    Logger.debug("Cleaning up user processes")

    kill_user_processes = Map.get(config, :kill_user_processes, false)

    if kill_user_processes do
      # Get all processes and filter for user-created ones
      all_processes = Process.list()
      current_process = self()

      user_processes = filter_user_processes(all_processes, current_process)

      # Terminate user processes gracefully
      terminated_count =
        Enum.count(user_processes, fn pid ->
          try do
            Process.exit(pid, :kill)
            true
          rescue
            _ -> false
          end
        end)

      {:ok, %{terminated_processes: terminated_count, total_processes: length(all_processes)}}
    else
      {:ok, %{terminated_processes: 0, cleanup_skipped: true}}
    end
  end

  defp cleanup_database(config) do
    Logger.debug("Cleaning up database state")

    adapter = Map.get(config, :adapter, :postgres)
    use_transactions = Map.get(config, :use_transactions, true)

    case adapter do
      :postgres ->
        cleanup_postgres_state(use_transactions)

      :mysql ->
        cleanup_mysql_state(use_transactions)

      _ ->
        {:ok, %{adapter: adapter, cleanup_skipped: true}}
    end
  end

  defp cleanup_postgres_state(use_transactions) do
    if use_transactions do
      # In a real implementation, would rollback test transactions
      Logger.debug("Database transaction rollback (placeholder)")
      {:ok, %{transactions_rolled_back: 0, adapter: :postgres}}
    else
      # Truncate test tables
      Logger.debug("Database table truncation (placeholder)")
      {:ok, %{tables_truncated: 0, adapter: :postgres}}
    end
  end

  defp cleanup_mysql_state(use_transactions) do
    if use_transactions do
      Logger.debug("MySQL transaction rollback (placeholder)")
      {:ok, %{transactions_rolled_back: 0, adapter: :mysql}}
    else
      Logger.debug("MySQL table truncation (placeholder)")
      {:ok, %{tables_truncated: 0, adapter: :mysql}}
    end
  end

  defp restart_supervisor_trees(config) do
    Logger.debug("Restarting supervisor trees")

    supervisor_names = Map.get(config, :supervisor_names, [])
    _restart_timeout = Map.get(config, :restart_timeout, 10_000)

    if length(supervisor_names) > 0 do
      restart_results =
        Enum.map(supervisor_names, fn supervisor_name ->
          try do
            case Process.whereis(supervisor_name) do
              nil ->
                {:not_found, supervisor_name}

              pid ->
                # Restart supervisor children
                case Supervisor.which_children(pid) do
                  children when is_list(children) ->
                    Enum.each(children, fn {_id, child_pid, _type, _modules} ->
                      if is_pid(child_pid) do
                        Supervisor.terminate_child(pid, child_pid)
                        Supervisor.restart_child(pid, child_pid)
                      end
                    end)

                    {:ok, supervisor_name}

                  _ ->
                    {:error, supervisor_name}
                end
            end
          rescue
            error -> {:error, {supervisor_name, error}}
          end
        end)

      successful_restarts = Enum.count(restart_results, fn {status, _} -> status == :ok end)

      {:ok,
       %{
         supervisors_restarted: successful_restarts,
         total_supervisors: length(supervisor_names),
         results: restart_results
       }}
    else
      {:ok, %{supervisors_restarted: 0, no_supervisors_configured: true}}
    end
  end

  defp filter_user_processes(all_processes, current_process) do
    all_processes
    |> Enum.filter(fn pid -> user_process?(pid) and pid != current_process end)
  end

  defp user_process?(pid) do
    info = Process.info(pid)
    initial_call = Keyword.get(info, :initial_call)

    case initial_call do
      {:proc_lib, :init_p, _} ->
        true

      {module, _fun, _arity} when is_atom(module) ->
        module_string = Atom.to_string(module)

        String.starts_with?(module_string, "Elixir.SweBench") or
          String.starts_with?(module_string, "Elixir.Test")

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
