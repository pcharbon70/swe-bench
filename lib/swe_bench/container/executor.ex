defmodule SweBench.Container.Executor do
  @moduledoc """
  Executes patch evaluations within Docker containers.

  Handles:
  - Code patching and verification
  - Test execution with timeout and resource monitoring
  - Result collection and analysis
  - Container cleanup and state management
  """

  require Logger

  @doc """
  Executes a complete patch evaluation within a container.
  """
  def execute_patch_evaluation(container_id, patch_file, base_commit, project_path, opts \\ []) do
    Logger.info("Starting patch evaluation in container #{container_id}")

    timeout = Keyword.get(opts, :timeout, 300_000)
    keep_artifacts = Keyword.get(opts, :keep_artifacts, false)

    with :ok <- prepare_container(container_id, project_path),
         :ok <- apply_patch(container_id, patch_file, base_commit),
         {:ok, results} <- execute_tests(container_id, timeout),
         :ok <- collect_results(container_id, results),
         :ok <- cleanup_container(container_id, keep_artifacts) do
      {:ok, format_execution_results(results)}
    else
      {:error, reason} ->
        Logger.error("Patch evaluation failed: #{inspect(reason)}")
        # Keep artifacts on failure
        cleanup_container(container_id, true)
        {:error, reason}
    end
  end

  @doc """
  Prepares the container by copying project files and setting up environment.
  """
  def prepare_container(container_id, project_path) do
    Logger.debug("Preparing container #{container_id} with project from #{project_path}")

    # Copy project files to container
    copy_args = [
      "cp",
      "#{project_path}/.",
      "#{container_id}:/opt/app/execution/"
    ]

    case run_docker_command(copy_args) do
      {_output, 0} ->
        Logger.debug("Successfully copied project files to container")
        :ok

      {error_output, exit_code} ->
        Logger.error("Failed to copy project files: #{error_output}")
        {:error, {:copy_failed, exit_code, error_output}}
    end
  end

  @doc """
  Applies a patch within the container using the patch application script.
  """
  def apply_patch(container_id, patch_file, base_commit) do
    Logger.debug("Applying patch #{patch_file} to container #{container_id}")

    # First copy the patch file to the container
    patch_copy_args = [
      "cp",
      patch_file,
      "#{container_id}:/opt/app/patches/current.patch"
    ]

    case run_docker_command(patch_copy_args) do
      {_output, 0} ->
        # Execute the patch application script
        patch_exec_args = [
          "exec",
          container_id,
          "/opt/app/apply_patch.sh",
          "/opt/app/patches/current.patch",
          base_commit || "",
          "/opt/app/execution"
        ]

        case run_docker_command(patch_exec_args) do
          {output, 0} ->
            Logger.debug("Patch applied successfully: #{String.slice(output, 0, 200)}...")
            :ok

          {error_output, exit_code} ->
            Logger.error("Patch application failed: #{error_output}")
            {:error, {:patch_failed, exit_code, error_output}}
        end

      {error_output, exit_code} ->
        Logger.error("Failed to copy patch file: #{error_output}")
        {:error, {:patch_copy_failed, exit_code, error_output}}
    end
  end

  @doc """
  Executes tests within the container with monitoring and timeout.
  """
  def execute_tests(container_id, timeout) do
    Logger.debug("Executing tests in container #{container_id} with timeout #{timeout}ms")

    # Execute the test execution script
    test_exec_args = [
      "exec",
      container_id,
      "timeout",
      "#{div(timeout, 1000)}",
      "/opt/app/execute_tests.sh",
      "/opt/app/execution"
    ]

    start_time = System.monotonic_time(:millisecond)

    case run_docker_command(test_exec_args, timeout) do
      {output, exit_code} ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = end_time - start_time

        Logger.debug(
          "Test execution completed with exit code #{exit_code} in #{execution_time}ms"
        )

        results = %{
          exit_code: exit_code,
          output: output,
          execution_time: execution_time,
          timeout_reached: exit_code == 124
        }

        {:ok, results}
    end
  end

  @doc """
  Collects detailed results from the container after test execution.
  """
  def collect_results(container_id, initial_results) do
    Logger.debug("Collecting detailed results from container #{container_id}")

    # Copy results file from container if it exists
    results_copy_args = [
      "cp",
      "#{container_id}:/opt/app/results/test_results.json",
      "/tmp/container_#{container_id}_results.json"
    ]

    detailed_results = load_detailed_results_from_container(container_id, results_copy_args)

    # Copy resource usage logs
    resource_copy_args = [
      "cp",
      "#{container_id}:/opt/app/logs/resource_usage.log",
      "/tmp/container_#{container_id}_resources.log"
    ]

    resource_stats =
      case run_docker_command(resource_copy_args) do
        {_output, 0} ->
          parse_resource_usage("/tmp/container_#{container_id}_resources.log")

        {_error_output, _exit_code} ->
          %{}
      end

    # Merge all results
    _enhanced_results =
      initial_results
      |> Map.merge(detailed_results)
      |> Map.put(:resource_usage, resource_stats)

    :ok
  end

  @doc """
  Cleans up the container after execution.
  """
  def cleanup_container(container_id, keep_artifacts) do
    Logger.debug("Cleaning up container #{container_id}, keep_artifacts: #{keep_artifacts}")

    cleanup_args = [
      "exec",
      container_id,
      "/opt/app/cleanup.sh",
      "/opt/app/execution",
      if(keep_artifacts, do: "true", else: "false")
    ]

    case run_docker_command(cleanup_args) do
      {_output, 0} ->
        Logger.debug("Container cleanup completed successfully")
        :ok

      {error_output, _exit_code} ->
        Logger.warning("Container cleanup had issues: #{error_output}")
        # Don't fail the entire operation due to cleanup issues
        :ok
    end
  end

  @doc """
  Executes a command directly in a container for debugging/testing.
  """
  def execute_command(container_id, command, args \\ []) do
    exec_args = ["exec", container_id] ++ [command] ++ args

    case run_docker_command(exec_args) do
      {output, 0} -> {:ok, output}
      {error_output, exit_code} -> {:error, {exit_code, error_output}}
    end
  end

  @doc """
  Gets detailed information about a container's current state.
  """
  def inspect_container(container_id) do
    inspect_args = ["inspect", container_id]

    case run_docker_command(inspect_args) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, [container_info]} -> {:ok, container_info}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {error_output, exit_code} ->
        {:error, {:inspect_failed, exit_code, error_output}}
    end
  end

  @doc """
  Monitors resource usage of a running container.
  """
  def monitor_container_resources(container_id) do
    stats_args = [
      "stats",
      "--no-stream",
      "--format",
      "table {{.Container}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.MemPerc}}\\t{{.NetIO}}\\t{{.BlockIO}}",
      container_id
    ]

    case run_docker_command(stats_args) do
      {output, 0} ->
        {:ok, parse_container_stats(output)}

      {error_output, exit_code} ->
        {:error, {:stats_failed, exit_code, error_output}}
    end
  end

  # Private Functions

  defp run_docker_command(args, timeout \\ 30_000) do
    Logger.debug("Running docker command: docker #{Enum.join(args, " ")}")

    try do
      case System.cmd("docker", args, stderr_to_stdout: true, timeout: timeout) do
        {output, exit_code} ->
          if exit_code != 0 do
            Logger.debug(
              "Docker command failed with exit code #{exit_code}: #{String.slice(output, 0, 500)}"
            )
          end

          {output, exit_code}

        error ->
          Logger.error("Failed to execute docker command: #{inspect(error)}")
          {"Command execution failed", 1}
      end
    catch
      :exit, {:timeout, _} ->
        Logger.error("Docker command timed out after #{timeout}ms")
        {"Command timed out", 124}
    end
  end

  defp format_execution_results(results) do
    %{
      success: results.exit_code == 0,
      exit_code: results.exit_code,
      execution_time: results.execution_time,
      timeout_reached: results.timeout_reached,
      output_summary: String.slice(results.output || "", 0, 1000),
      resource_usage: results[:resource_usage] || %{},
      test_results: extract_test_results(results),
      timestamp: DateTime.utc_now()
    }
  end

  defp extract_test_results(results) do
    # Parse test results from output
    output = results.output || ""

    cond do
      String.contains?(output, "test") and String.contains?(output, "passed") ->
        # Try to extract test counts
        extract_test_counts(output)

      results.exit_code == 0 ->
        %{status: "passed", details: "Execution completed successfully"}

      results.timeout_reached ->
        %{status: "timeout", details: "Execution timed out"}

      true ->
        %{status: "failed", details: "Execution failed", exit_code: results.exit_code}
    end
  end

  defp extract_test_counts(output) do
    # Try to extract test counts using various patterns
    patterns = [
      ~r/(\d+)\s+tests?,\s+(\d+)\s+passed/i,
      ~r/(\d+)\s+passed,\s+(\d+)\s+failed/i,
      ~r/Finished in .+ seconds, (\d+) tests, (\d+) failures/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case {pattern, Regex.run(pattern, output)} do
        {~r/(\d+)\s+tests?,\s+(\d+)\s+passed/i, [_, total, passed]} ->
          %{
            total: String.to_integer(total),
            passed: String.to_integer(passed),
            failed: String.to_integer(total) - String.to_integer(passed)
          }

        {~r/(\d+)\s+passed,\s+(\d+)\s+failed/i, [_, passed, failed]} ->
          %{
            passed: String.to_integer(passed),
            failed: String.to_integer(failed),
            total: String.to_integer(passed) + String.to_integer(failed)
          }

        {~r/Finished in .+ seconds, (\d+) tests, (\d+) failures/i, [_, total, failures]} ->
          %{
            total: String.to_integer(total),
            passed: String.to_integer(total) - String.to_integer(failures),
            failed: String.to_integer(failures)
          }

        _ ->
          nil
      end
    end) || %{status: "unknown", output_sample: String.slice(output, 0, 200)}
  end

  defp parse_resource_usage(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)
        # Skip header
        data_lines = Enum.drop(lines, 1)

        stats = parse_resource_stats_lines(data_lines)

        if length(stats) > 0 do
          %{
            peak_memory_mb: Enum.max_by(stats, & &1.memory_mb).memory_mb,
            average_memory_mb: Enum.sum(Enum.map(stats, & &1.memory_mb)) / length(stats),
            peak_cpu_percent: Enum.max_by(stats, & &1.cpu_percent).cpu_percent,
            average_cpu_percent: Enum.sum(Enum.map(stats, & &1.cpu_percent)) / length(stats),
            sample_count: length(stats)
          }
        else
          %{}
        end

      {:error, _} ->
        %{}
    end
  end

  defp parse_container_stats(output) do
    lines = String.split(output, "\n", trim: true)
    # Skip header
    data_lines = Enum.drop(lines, 1)

    case data_lines do
      [stats_line | _] ->
        parts = String.split(stats_line, "\t", trim: true)

        case parts do
          [_container, cpu, mem_usage, mem_perc, net_io, block_io] ->
            %{
              cpu_percent: parse_percentage(cpu),
              memory_usage: mem_usage,
              memory_percent: parse_percentage(mem_perc),
              network_io: net_io,
              block_io: block_io
            }

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp parse_percentage(perc_str) do
    case Regex.run(~r/([\d.]+)%/, perc_str) do
      [_, number] -> String.to_float(number)
      _ -> 0.0
    end
  end

  defp parse_resource_stats_lines(data_lines) do
    data_lines
    |> Enum.map(&parse_resource_line/1)
    |> Enum.filter(& &1)
  end

  defp parse_resource_line(line) do
    case String.split(line, ",") do
      [timestamp, memory_mb, cpu_percent] ->
        %{
          timestamp: timestamp,
          memory_mb: String.to_integer(memory_mb),
          cpu_percent: String.to_float(cpu_percent)
        }
      _ ->
        nil
    end
  end

  defp load_detailed_results_from_container(container_id, results_copy_args) do
    case run_docker_command(results_copy_args) do
      {_output, 0} ->
        load_and_parse_results_file(container_id)
      {_error_output, _exit_code} ->
        %{}
    end
  end

  defp load_and_parse_results_file(container_id) do
    case File.read("/tmp/container_#{container_id}_results.json") do
      {:ok, content} ->
        parse_json_content(content)
      {:error, _} ->
        %{}
    end
  end

  defp parse_json_content(content) do
    case Jason.decode(content) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end
end
