defmodule SweBench.TaskGeneration.Formatter do
  @moduledoc """
  SWE-bench format compliance and serialization.

  Ensures task instances conform to SWE-bench standards while supporting
  Elixir-specific extensions and maintaining backward compatibility.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Formats a task instance for SWE-bench compatibility.
  """
  def format_for_swe_bench(task_instance) do
    GenServer.call(__MODULE__, {:format_instance, task_instance})
  end

  @impl true
  def init(_opts) do
    state = %{
      instances_formatted: 0,
      format_errors: 0
    }

    Logger.info("Task formatter started")
    {:ok, state}
  end

  @impl true
  def handle_call({:format_instance, task_instance}, _from, state) do
    result =
      task_instance
      |> convert_to_swe_bench_format()
      |> validate_format_compliance()
      |> add_elixir_extensions()

    updated_state = update_format_stats(state, result)
    {:reply, result, updated_state}
  end

  # Private implementation functions

  defp convert_to_swe_bench_format(task_instance) do
    # Convert to standard SWE-bench JSON format
    swe_bench_format = %{
      instance_id: task_instance.instance_id,
      repo: extract_repo_identifier(task_instance),
      base_commit: task_instance.base_commit_sha,
      problem_statement: task_instance.problem_statement,
      patch: task_instance.patch_content,
      test_patch: extract_test_patch(task_instance),
      hints: task_instance.hints || [],
      created_at: DateTime.to_iso8601(task_instance.created_at)
    }

    {:ok, swe_bench_format}
  end

  defp validate_format_compliance({:ok, formatted_instance}) do
    # Validate against SWE-bench schema requirements
    required_fields = [:instance_id, :repo, :base_commit, :problem_statement, :patch]
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(formatted_instance, &1)))

    if Enum.empty?(missing_fields) do
      {:ok, formatted_instance}
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp validate_format_compliance({:error, reason}) do
    {:error, reason}
  end

  defp add_elixir_extensions({:ok, formatted_instance}) do
    # Add Elixir-specific extensions while maintaining compatibility
    elixir_extensions = %{
      elixir_metadata: %{
        language: "elixir",
        framework_version: System.version(),
        otp_version: System.otp_release(),
        test_framework: "ExUnit"
      }
    }

    extended_instance = Map.merge(formatted_instance, elixir_extensions)
    {:ok, extended_instance}
  end

  defp add_elixir_extensions({:error, reason}) do
    {:error, reason}
  end

  defp extract_repo_identifier(task_instance) do
    case Ash.load(task_instance, :repository) do
      {:ok, loaded} -> loaded.repository.full_name
      _ -> "unknown/unknown"
    end
  end

  defp extract_test_patch(task_instance) do
    # Extract test patch from test specification
    case Map.get(task_instance, :test_specification, %{}) do
      %{test_patch: patch} when is_binary(patch) -> patch
      _ -> ""
    end
  end

  defp update_format_stats(state, result) do
    new_total = state.instances_formatted + 1

    {new_errors} =
      case result do
        {:ok, _} -> {state.format_errors}
        {:error, _} -> {state.format_errors + 1}
      end

    %{
      state
      | instances_formatted: new_total,
        format_errors: new_errors
    }
  end
end
