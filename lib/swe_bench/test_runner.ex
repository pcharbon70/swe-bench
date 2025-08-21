defmodule SweBench.TestRunner do
  @moduledoc """
  Core test execution engine for SWE-bench-Elixir evaluation system.
  
  This module provides the main interface for executing tests with detailed
  result capture, integrating with the container system from Phase 1.1.
  
  Features:
  - Custom ExUnit formatter for detailed result capture
  - Test execution orchestration with timeout handling
  - Result analysis for FAIL_TO_PASS transition detection
  - Process isolation for clean test execution
  - Integration with Docker container system
  """

  alias SweBench.TestRunner.{Formatter, Orchestrator, Analyzer, Isolation}
  require Logger

  @doc """
  Executes tests in a project with comprehensive result capture.
  
  ## Parameters
  
  - `project_path` - Path to the Elixir project to test
  - `opts` - Options for test execution
  
  ## Options
  
  - `:timeout` - Execution timeout in milliseconds (default: 300_000)
  - `:isolation` - Whether to use process isolation (default: true)
  - `:formatter` - Custom formatter options (default: comprehensive)
  - `:coverage` - Whether to collect coverage data (default: true)
  - `:container_id` - Container ID for execution (optional)
  
  ## Returns
  
  - `{:ok, results}` - Successful execution with detailed results
  - `{:error, reason}` - Execution failure with error details
  
  ## Examples
  
      iex> SweBench.TestRunner.execute_tests("/path/to/project")
      {:ok, %{
        total_tests: 25,
        passed: 23,
        failed: 2,
        execution_time: 15_432,
        failures: [...],
        coverage: %{...}
      }}
  """
  def execute_tests(project_path, opts \\ []) do
    Logger.info("Starting test execution for project: #{project_path}")
    
    timeout = Keyword.get(opts, :timeout, 300_000)
    use_isolation = Keyword.get(opts, :isolation, true)
    container_id = Keyword.get(opts, :container_id)
    
    with {:ok, execution_id} <- start_execution(project_path, opts),
         {:ok, results} <- run_tests_with_capture(execution_id, project_path, timeout, container_id),
         {:ok, analyzed_results} <- analyze_results(results, opts),
         :ok <- cleanup_execution(execution_id, use_isolation) do
      
      Logger.info("Test execution completed successfully: #{execution_id}")
      {:ok, analyzed_results}
    else
      {:error, reason} ->
        Logger.error("Test execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Compares test results between base and patched versions to detect transitions.
  
  ## Parameters
  
  - `base_results` - Test results from base (unpatched) code
  - `patched_results` - Test results from patched code
  
  ## Returns
  
  - `{:ok, transition_report}` - Detailed transition analysis
  - `{:error, reason}` - Analysis failure
  """
  def compare_test_results(base_results, patched_results) do
    Logger.info("Analyzing test result transitions")
    
    case Analyzer.detect_transitions(base_results, patched_results) do
      {:ok, transitions} ->
        report = %{
          fail_to_pass: transitions.fail_to_pass,
          pass_to_pass: transitions.pass_to_pass,
          pass_to_fail: transitions.pass_to_fail,
          new_tests: transitions.new_tests,
          removed_tests: transitions.removed_tests,
          evaluation_score: calculate_evaluation_score(transitions)
        }
        
        {:ok, report}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the status of the test runner system.
  """
  def status do
    %{
      formatter_running: Formatter.running?(),
      active_executions: Orchestrator.active_executions(),
      isolation_enabled: Isolation.enabled?(),
      system_ready: system_ready?()
    }
  end

  @doc """
  Starts the test runner system components.
  """
  def start_system(opts \\ []) do
    with {:ok, _formatter} <- Formatter.start_link(opts),
         {:ok, _orchestrator} <- Orchestrator.start_link(opts),
         {:ok, _isolation} <- Isolation.start_link(opts) do
      
      Logger.info("Test runner system started successfully")
      {:ok, :system_started}
    else
      {:error, reason} ->
        Logger.error("Failed to start test runner system: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops the test runner system and cleans up resources.
  """
  def stop_system do
    Logger.info("Stopping test runner system")
    
    Isolation.stop()
    Orchestrator.stop()
    Formatter.stop()
    
    :ok
  end

  # Private Functions

  defp start_execution(project_path, opts) do
    execution_id = generate_execution_id()
    
    case Orchestrator.start_execution(execution_id, project_path, opts) do
      :ok -> {:ok, execution_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_tests_with_capture(execution_id, project_path, timeout, container_id) do
    # Configure formatter for this execution
    formatter_opts = [
      execution_id: execution_id,
      capture_detailed: true,
      output_format: :structured
    ]
    
    if container_id do
      # Execute in existing container
      Orchestrator.execute_in_container(execution_id, container_id, timeout)
    else
      # Execute in current environment
      Orchestrator.execute_locally(execution_id, project_path, timeout, formatter_opts)
    end
  end

  defp analyze_results(raw_results, opts) do
    analysis_opts = [
      include_coverage: Keyword.get(opts, :coverage, true),
      include_timing: true,
      include_transitions: true
    ]
    
    Analyzer.analyze_execution_results(raw_results, analysis_opts)
  end

  defp cleanup_execution(execution_id, use_isolation) do
    if use_isolation do
      Isolation.cleanup_execution(execution_id)
    else
      :ok
    end
  end

  defp calculate_evaluation_score(transitions) do
    # Calculate score based on FAIL_TO_PASS transitions
    fail_to_pass_count = length(transitions.fail_to_pass)
    pass_to_fail_count = length(transitions.pass_to_fail)
    
    # Basic scoring: positive for fixes, negative for regressions
    base_score = fail_to_pass_count * 100 - pass_to_fail_count * 50
    
    # Normalize to 0-100 scale
    max(0, min(100, base_score))
  end

  defp generate_execution_id do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    "test_exec_#{timestamp}_#{:rand.uniform(9999)}"
  end

  defp system_ready? do
    Formatter.running?() and 
    Orchestrator.running?() and 
    Isolation.running?()
  end
end