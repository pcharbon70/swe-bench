defmodule SweBench.TaskGeneration.Enricher do
  @moduledoc """
  Metadata enrichment for task instances.

  Provides sophisticated code analysis and metadata extraction using
  existing analysis infrastructure and AST-based techniques.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Analyzes code changes in a patch for metadata enrichment.
  """
  def analyze_code_changes(patch_content) do
    GenServer.call(__MODULE__, {:analyze_changes, patch_content})
  end

  @doc """
  Gets enrichment statistics.
  """
  def get_enrichment_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      analyses_performed: 0,
      avg_analysis_time: 0.0,
      successful_analyses: 0,
      failed_analyses: 0
    }

    Logger.info("Task enricher started")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_changes, patch_content}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      patch_content
      |> parse_patch_changes()
      |> extract_function_modifications()
      |> detect_otp_behavior_changes()
      |> analyze_pattern_matching_changes()
      |> compile_enrichment_result()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_enrichment_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp parse_patch_changes(patch_content) do
    # Parse unified diff format
    # Placeholder - will implement comprehensive patch parsing
    Logger.debug("Parsing patch changes from #{String.length(patch_content)} character patch")

    file_changes =
      patch_content
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "diff --git"))
      |> Enum.map(&extract_file_path/1)

    {:ok, %{files_changed: file_changes, patch_content: patch_content}}
  end

  defp extract_function_modifications({:ok, patch_data}) do
    # Extract function-level changes
    # Placeholder - will implement AST-based function analysis
    Logger.debug("Extracting function modifications")

    function_changes = %{
      functions_added: [],
      functions_modified: [],
      functions_removed: [],
      arity_changes: []
    }

    {:ok, Map.put(patch_data, :function_changes, function_changes)}
  end

  defp extract_function_modifications({:error, reason}) do
    {:error, reason}
  end

  defp detect_otp_behavior_changes({:ok, patch_data}) do
    # Detect OTP behavior implementations and modifications
    # Placeholder - will integrate with existing OTP analysis
    Logger.debug("Detecting OTP behavior changes")

    otp_changes = %{
      behaviors_added: [],
      behaviors_modified: [],
      callbacks_implemented: [],
      supervision_tree_changes: false
    }

    {:ok, Map.put(patch_data, :otp_changes, otp_changes)}
  end

  defp detect_otp_behavior_changes({:error, reason}) do
    {:error, reason}
  end

  defp analyze_pattern_matching_changes({:ok, patch_data}) do
    # Analyze pattern matching and guard changes
    # Placeholder - will integrate with existing pattern analysis
    Logger.debug("Analyzing pattern matching changes")

    pattern_changes = %{
      clauses_added: [],
      clauses_modified: [],
      guards_added: [],
      exhaustiveness_improved: false
    }

    {:ok, Map.put(patch_data, :pattern_changes, pattern_changes)}
  end

  defp analyze_pattern_matching_changes({:error, reason}) do
    {:error, reason}
  end

  defp compile_enrichment_result({:ok, patch_data}) do
    enrichment_result = %{
      code_analysis: %{
        files_changed: length(patch_data.files_changed),
        function_changes: patch_data.function_changes,
        otp_behavior_changes: patch_data.otp_changes,
        pattern_matching_changes: patch_data.pattern_changes
      },
      analysis_metadata: %{
        analyzer_version: "1.0.0",
        analyzed_at: DateTime.utc_now(),
        patch_size_chars: String.length(patch_data.patch_content)
      }
    }

    {:ok, enrichment_result}
  end

  defp compile_enrichment_result({:error, reason}) do
    {:error, reason}
  end

  defp extract_file_path(diff_line) do
    # Extract file path from "diff --git a/file.ex b/file.ex" format
    case Regex.run(~r/diff --git a\/(.+) b\//, diff_line) do
      [_full, file_path] -> file_path
      _ -> "unknown"
    end
  end

  defp update_enrichment_stats(state, result, processing_time) do
    new_total = state.analyses_performed + 1

    {new_successful, new_failed} =
      case result do
        {:ok, _} -> {state.successful_analyses + 1, state.failed_analyses}
        {:error, _} -> {state.successful_analyses, state.failed_analyses + 1}
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_analysis_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | analyses_performed: new_total,
        successful_analyses: new_successful,
        failed_analyses: new_failed,
        avg_analysis_time: new_avg_time
    }
  end
end
