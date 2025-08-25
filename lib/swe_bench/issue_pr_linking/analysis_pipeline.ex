defmodule SweBench.IssuePrLinking.AnalysisPipeline do
  @moduledoc """
  Analysis pipeline for Issue-PR correlation using multiple strategies.

  Coordinates different correlation methods including commit message analysis,
  semantic similarity, code change analysis, and temporal proximity detection.
  """

  use GenServer
  require Logger

  defstruct [
    :active_analyses,
    :completed_analyses,
    :failed_analyses,
    :analysis_stats
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Applies correlation strategies to find issue-PR relationships.
  """
  def correlate_issue_with_prs(issue, pull_requests, strategies \\ [:all]) do
    GenServer.call(__MODULE__, {:correlate, issue, pull_requests, strategies})
  end

  @doc """
  Gets analysis pipeline statistics.
  """
  def get_analysis_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_analyses: %{},
      completed_analyses: [],
      failed_analyses: [],
      analysis_stats: %{
        total_processed: 0,
        avg_processing_time: 0.0,
        strategy_success_rates: %{}
      }
    }

    Logger.info("Analysis pipeline started")
    {:ok, state}
  end

  @impl true
  def handle_call({:correlate, issue, pull_requests, strategies}, _from, state) do
    analysis_id = generate_analysis_id()
    start_time = System.monotonic_time(:millisecond)

    try do
      correlations = apply_correlation_strategies(issue, pull_requests, strategies)
      processing_time = System.monotonic_time(:millisecond) - start_time

      # Update statistics
      updated_stats = update_analysis_stats(state.analysis_stats, processing_time, :success)
      updated_state = %{state | analysis_stats: updated_stats}

      Logger.debug("Correlation analysis #{analysis_id} completed: #{length(correlations)} relationships found")

      {:reply, {:ok, correlations}, updated_state}
    rescue
      error ->
        processing_time = System.monotonic_time(:millisecond) - start_time
        updated_stats = update_analysis_stats(state.analysis_stats, processing_time, :error)
        updated_state = %{state | analysis_stats: updated_stats}

        Logger.error("Correlation analysis #{analysis_id} failed: #{inspect(error)}")
        {:reply, {:error, error}, updated_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.analysis_stats, state}
  end

  # Private implementation functions

  defp apply_correlation_strategies(issue, pull_requests, strategies) do
    enabled_strategies = normalize_strategies(strategies)

    correlations =
      enabled_strategies
      |> Enum.flat_map(fn strategy ->
        apply_single_strategy(strategy, issue, pull_requests)
      end)
      |> deduplicate_by_pr()
      |> enhance_with_combined_confidence()

    correlations
  end

  defp normalize_strategies([:all]), do: [:commit_message, :semantic_similarity, :temporal_proximity]
  defp normalize_strategies(strategies) when is_list(strategies), do: strategies
  defp normalize_strategies(_), do: [:commit_message]

  defp apply_single_strategy(:commit_message, issue, pull_requests) do
    issue_number = issue["number"]

    pull_requests
    |> Enum.filter(&has_commit_reference?(&1, issue_number))
    |> Enum.map(fn pr ->
      confidence = calculate_commit_reference_confidence(pr, issue_number)

      %{
        issue: issue,
        pull_request: pr,
        relationship_type: determine_relationship_from_commits(pr, issue_number),
        confidence_score: confidence,
        detection_method: :commit_message,
        evidence: %{
          matching_commits: extract_matching_commits(pr, issue_number),
          reference_strength: calculate_reference_strength(pr, issue_number)
        }
      }
    end)
  end

  defp apply_single_strategy(:semantic_similarity, issue, pull_requests) do
    # Placeholder - will be implemented in Phase 2
    Logger.debug("Semantic similarity analysis - placeholder implementation")
    []
  end

  defp apply_single_strategy(:temporal_proximity, issue, pull_requests) do
    # Placeholder - will be implemented in Phase 2
    Logger.debug("Temporal proximity analysis - placeholder implementation")
    []
  end

  defp has_commit_reference?(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])

    Enum.any?(commit_messages, fn message ->
      Regex.match?(~r/##{issue_number}\b/i, message || "")
    end)
  end

  defp calculate_commit_reference_confidence(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])
    pr_body = Map.get(pr, "body", "")

    # Count explicit references
    reference_count = count_issue_references(commit_messages ++ [pr_body], issue_number)

    # Base confidence on reference strength
    case reference_count do
      count when count >= 3 -> 0.95  # Multiple strong references
      count when count >= 2 -> 0.85  # Multiple references
      count when count >= 1 -> 0.75  # Single reference
      _ -> 0.50  # Weak or no reference
    end
  end

  defp count_issue_references(texts, issue_number) do
    strong_patterns = [
      ~r/(?:fix|fixes|fixed|close|closes|closed|resolve|resolves|resolved)\s+##{issue_number}/i
    ]

    weak_patterns = [
      ~r/##{issue_number}\b/i
    ]

    strong_count =
      texts
      |> Enum.flat_map(fn text ->
        Enum.flat_map(strong_patterns, &Regex.scan(&1, text || ""))
      end)
      |> length()

    weak_count =
      texts
      |> Enum.flat_map(fn text ->
        Enum.flat_map(weak_patterns, &Regex.scan(&1, text || ""))
      end)
      |> length()

    strong_count * 2 + weak_count
  end

  defp determine_relationship_from_commits(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])
    pr_body = Map.get(pr, "body", "")

    all_text = Enum.join([pr_body | commit_messages], " ")

    cond do
      Regex.match?(~r/(?:fix|fixes|fixed)\s+##{issue_number}/i, all_text) -> :fixes
      Regex.match?(~r/(?:close|closes|closed)\s+##{issue_number}/i, all_text) -> :closes
      Regex.match?(~r/(?:resolve|resolves|resolved)\s+##{issue_number}/i, all_text) -> :addresses
      true -> :references
    end
  end

  defp extract_matching_commits(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])

    commit_messages
    |> Enum.filter(fn message ->
      Regex.match?(~r/##{issue_number}\b/i, message || "")
    end)
    |> Enum.map(fn message ->
      %{
        message: message,
        reference_type: determine_reference_type(message, issue_number)
      }
    end)
  end

  defp determine_reference_type(message, issue_number) do
    cond do
      Regex.match?(~r/(?:fix|fixes|fixed)\s+##{issue_number}/i, message) -> :fixes
      Regex.match?(~r/(?:close|closes|closed)\s+##{issue_number}/i, message) -> :closes
      Regex.match?(~r/(?:resolve|resolves|resolved)\s+##{issue_number}/i, message) -> :resolves
      true -> :references
    end
  end

  defp calculate_reference_strength(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])
    total_references = count_issue_references(commit_messages, issue_number)

    case total_references do
      count when count >= 5 -> :very_strong
      count when count >= 3 -> :strong
      count when count >= 2 -> :moderate
      count when count >= 1 -> :weak
      _ -> :very_weak
    end
  end

  defp deduplicate_by_pr(correlations) do
    correlations
    |> Enum.group_by(fn corr -> corr.pull_request["id"] end)
    |> Enum.map(fn {_pr_id, group} ->
      # Keep the highest confidence correlation for each PR
      Enum.max_by(group, & &1.confidence_score)
    end)
  end

  defp enhance_with_combined_confidence(correlations) do
    # For Phase 1, use detection method confidence as-is
    # Will be enhanced with multi-strategy combination in Phase 3
    correlations
  end

  defp update_analysis_stats(stats, processing_time, outcome) do
    new_total = stats.total_processed + 1

    new_avg_time =
      if new_total > 1 do
        ((stats.avg_processing_time * (new_total - 1)) + processing_time) / new_total
      else
        processing_time
      end

    %{
      stats
      | total_processed: new_total,
        avg_processing_time: new_avg_time
    }
  end

  defp generate_analysis_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end