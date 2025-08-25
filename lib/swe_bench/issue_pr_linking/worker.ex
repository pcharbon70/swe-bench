defmodule SweBench.IssuePrLinking.Worker do
  @moduledoc """
  Individual worker process for Issue-PR correlation analysis.

  Handles fetching repository issues and PRs, applying correlation strategies,
  and persisting discovered relationships with proper error handling.
  """

  use GenServer
  require Logger

  alias SweBench.GitHub.EnhancedIssuesClient
  alias SweBench.Issues.{Issue, IssuePrLink, PullRequest}
  alias SweBench.IssuePrLinking.{AnalysisPipeline, ValidationPipeline}

  defstruct [
    :job,
    :coordinator,
    :start_time,
    :issues_fetched,
    :prs_fetched,
    :correlations_found,
    :current_operation
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    job = Keyword.fetch!(opts, :job)
    coordinator = Keyword.fetch!(opts, :coordinator)

    state = %__MODULE__{
      job: job,
      coordinator: coordinator,
      start_time: DateTime.utc_now(),
      issues_fetched: 0,
      prs_fetched: 0,
      correlations_found: 0,
      current_operation: :initializing
    }

    # Start processing immediately
    send(self(), :start_correlation_analysis)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_correlation_analysis, state) do
    Logger.info("Starting correlation analysis for repository #{state.job.repository_id}")

    case execute_correlation_pipeline(state) do
      {:ok, results} ->
        complete_correlation_job(state, results)

      {:error, reason} ->
        fail_correlation_job(state, reason)
    end

    {:stop, :normal, state}
  end

  # Private implementation functions

  defp execute_correlation_pipeline(state) do
    [repository_owner, repository_name] = String.split(state.job.repository_name, "/")

    state.job.repository_name
    |> fetch_repository_data(repository_owner, repository_name)
    |> apply_correlation_strategies(state)
    |> validate_relationships(state)
    |> persist_relationships(state)
    |> compile_results(state)
  rescue
    error ->
      Logger.error(
        "Correlation pipeline error for repository #{state.job.repository_id}: #{inspect(error)}"
      )

      {:error, {:pipeline_error, error}}
  end

  defp fetch_repository_data(repository_name, owner, repo_name) do
    Logger.debug("Fetching issues and PRs for #{repository_name}")

    with {:ok, issues} <- EnhancedIssuesClient.get_closed_issues(owner, repo_name, max_pages: 5),
         {:ok, prs} <-
           EnhancedIssuesClient.get_merged_pull_requests(owner, repo_name, max_pages: 5) do
      Logger.info(
        "Fetched #{length(issues)} issues and #{length(prs)} PRs for #{repository_name}"
      )

      {:ok,
       %{
         repository_name: repository_name,
         issues: issues,
         pull_requests: prs
       }}
    end
  end

  defp apply_correlation_strategies({:ok, data}, state) do
    Logger.debug("Applying correlation strategies for #{data.repository_name}")

    correlations =
      data.issues
      |> Enum.flat_map(fn issue ->
        find_related_prs(issue, data.pull_requests, state.job)
      end)
      |> Enum.filter(&(&1.confidence_score >= state.job.confidence_threshold))
      |> Enum.sort_by(& &1.confidence_score, :desc)
      |> Enum.take(state.job.max_correlations)

    Logger.info(
      "Found #{length(correlations)} potential correlations for #{data.repository_name}"
    )

    {:ok, Map.put(data, :correlations, correlations)}
  end

  defp apply_correlation_strategies({:error, reason}, _state) do
    {:error, {:data_fetch_failed, reason}}
  end

  defp find_related_prs(issue, pull_requests, job) do
    # Apply multiple correlation strategies
    strategies = get_enabled_strategies(job.correlation_strategies)

    strategies
    |> Enum.flat_map(fn strategy ->
      apply_correlation_strategy(strategy, issue, pull_requests)
    end)
    |> deduplicate_correlations()
    |> calculate_combined_confidence()
  end

  defp get_enabled_strategies([:all]),
    do: [:commit_message, :semantic_similarity, :temporal_proximity]

  defp get_enabled_strategies(strategies) when is_list(strategies), do: strategies

  defp apply_correlation_strategy(:commit_message, issue, pull_requests) do
    issue_number = issue["number"]

    pull_requests
    |> Enum.filter(&has_issue_reference?(&1, issue_number))
    |> Enum.map(fn pr ->
      %{
        issue: issue,
        pull_request: pr,
        relationship_type: determine_relationship_type(pr, issue_number),
        # High confidence for explicit references
        confidence_score: 0.95,
        detection_method: :commit_message,
        evidence: %{
          commit_messages: extract_referencing_commits(pr, issue_number)
        }
      }
    end)
  end

  defp apply_correlation_strategy(:semantic_similarity, _issue, _pull_requests) do
    # Placeholder for semantic similarity - will be enhanced in Phase 2
    []
  end

  defp apply_correlation_strategy(:temporal_proximity, _issue, _pull_requests) do
    # Placeholder for temporal analysis - will be enhanced in Phase 2
    []
  end

  defp has_issue_reference?(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])
    pr_body = Map.get(pr, "body", "")

    reference_patterns = [
      ~r/(?:fix|fixes|fixed|close|closes|closed|resolve|resolves|resolved)\s+##{issue_number}\b/i,
      ~r/(?:fix|fixes|fixed|close|closes|closed|resolve|resolves|resolved)\s+(?:issue\s+)?##{issue_number}\b/i,
      ~r/##{issue_number}\b/
    ]

    texts_to_check = [pr_body | commit_messages]

    Enum.any?(texts_to_check, fn text ->
      Enum.any?(reference_patterns, &Regex.match?(&1, text || ""))
    end)
  end

  defp determine_relationship_type(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])
    pr_body = Map.get(pr, "body", "")

    all_text = Enum.join([pr_body | commit_messages], " ")

    cond do
      Regex.match?(~r/(?:fix|fixes|fixed)\s+##{issue_number}/i, all_text) -> :fixes
      Regex.match?(~r/(?:close|closes|closed)\s+##{issue_number}/i, all_text) -> :closes
      Regex.match?(~r/(?:resolve|resolves|resolved)\s+##{issue_number}/i, all_text) -> :addresses
      Regex.match?(~r/##{issue_number}/i, all_text) -> :references
      true -> :related_to
    end
  end

  defp extract_referencing_commits(pr, issue_number) do
    commit_messages = Map.get(pr, "commit_messages", [])

    commit_messages
    |> Enum.filter(fn message ->
      Regex.match?(~r/##{issue_number}\b/i, message || "")
    end)
  end

  defp deduplicate_correlations(correlations) do
    # Remove duplicate issue-PR pairs, keeping highest confidence
    correlations
    |> Enum.group_by(fn corr ->
      {corr.issue["id"], corr.pull_request["id"]}
    end)
    |> Enum.map(fn {_key, group} ->
      Enum.max_by(group, & &1.confidence_score)
    end)
  end

  defp calculate_combined_confidence(correlations) do
    # For now, use the detection method confidence
    # Will be enhanced with multi-strategy combination in Phase 3
    correlations
  end

  defp validate_relationships({:ok, data}, _state) do
    Logger.debug("Validating relationships for #{data.repository_name}")

    validated_correlations =
      data.correlations
      |> Enum.map(&ValidationPipeline.validate_relationship/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, correlation} -> correlation end)

    {:ok, Map.put(data, :validated_correlations, validated_correlations)}
  end

  defp validate_relationships({:error, reason}, _state) do
    {:error, reason}
  end

  defp persist_relationships({:ok, data}, state) do
    Logger.debug("Persisting #{length(data.validated_correlations)} relationships")

    persisted_links =
      data.validated_correlations
      |> Enum.map(&persist_single_relationship(&1, state.job.repository_id))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, link} -> link end)

    Logger.info("Successfully persisted #{length(persisted_links)} relationships")

    {:ok, Map.put(data, :persisted_links, persisted_links)}
  end

  defp persist_relationships({:error, reason}, _state) do
    {:error, reason}
  end

  defp persist_single_relationship(correlation, repository_id) do
    # First, ensure issue and PR exist in database
    with {:ok, issue} <- ensure_issue_exists(correlation.issue, repository_id),
         {:ok, pr} <- ensure_pr_exists(correlation.pull_request, repository_id) do
      attrs = %{
        repository_id: repository_id,
        issue_id: issue.id,
        pull_request_id: pr.id,
        relationship_type: correlation.relationship_type,
        confidence_score: correlation.confidence_score,
        detection_method: correlation.detection_method,
        analysis_metadata: %{
          evidence: correlation.evidence,
          created_by: "automated_analysis",
          analysis_version: "1.0.0"
        }
      }

      IssuePrLink
      |> Ash.Changeset.for_create(:create_link, attrs)
      |> Ash.create()
    end
  end

  defp ensure_issue_exists(issue_data, repository_id) do
    # Check if issue already exists, create if not
    case Ash.get(Issue, issue_data["id"]) do
      {:ok, issue} ->
        {:ok, issue}

      {:error, %Ash.Error.Query.NotFound{}} ->
        create_issue_from_github_data(issue_data, repository_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_pr_exists(pr_data, repository_id) do
    # Check if PR already exists, create if not
    case Ash.get(PullRequest, pr_data["id"]) do
      {:ok, pr} ->
        {:ok, pr}

      {:error, %Ash.Error.Query.NotFound{}} ->
        create_pr_from_github_data(pr_data, repository_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_issue_from_github_data(issue_data, repository_id) do
    attrs = %{
      repository_id: repository_id,
      github_id: issue_data["id"],
      number: issue_data["number"],
      title: issue_data["title"],
      body: issue_data["body"],
      state: issue_data["state"],
      labels: extract_labels(issue_data),
      closed_at: parse_datetime(issue_data["closed_at"])
    }

    Issue
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp create_pr_from_github_data(pr_data, repository_id) do
    attrs = %{
      repository_id: repository_id,
      github_id: pr_data["id"],
      number: pr_data["number"],
      title: pr_data["title"],
      body: pr_data["body"],
      state: pr_data["state"],
      additions: pr_data["additions"] || 0,
      deletions: pr_data["deletions"] || 0,
      changed_files: pr_data["changed_files"] || 0,
      merged_at: parse_datetime(pr_data["merged_at"]),
      closed_at: parse_datetime(pr_data["closed_at"])
    }

    PullRequest
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp extract_labels(issue_data) do
    case Map.get(issue_data, "labels") do
      labels when is_list(labels) ->
        Enum.map(labels, &Map.get(&1, "name", ""))

      _ ->
        []
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp compile_results({:ok, data}, state) do
    processing_time = DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)

    correlations_by_confidence = group_by_confidence(data.persisted_links)

    result = %{
      repository_id: state.job.repository_id,
      repository_name: data.repository_name,
      issues_fetched: length(data.issues),
      prs_fetched: length(data.pull_requests),
      correlations_found: length(data.persisted_links),
      high_confidence_count: Map.get(correlations_by_confidence, :high, 0),
      medium_confidence_count: Map.get(correlations_by_confidence, :medium, 0),
      low_confidence_count: Map.get(correlations_by_confidence, :low, 0),
      auto_validated_count: count_auto_validated(data.persisted_links),
      # Will be updated when validation is enhanced
      rejected_count: 0,
      processing_time_ms: processing_time
    }

    {:ok, result}
  end

  defp compile_results({:error, reason}, _state) do
    {:error, reason}
  end

  defp group_by_confidence(links) do
    links
    |> Enum.group_by(fn link ->
      cond do
        link.confidence_score >= 0.8 -> :high
        link.confidence_score >= 0.6 -> :medium
        true -> :low
      end
    end)
    |> Enum.map(fn {tier, group} -> {tier, length(group)} end)
    |> Map.new()
  end

  defp count_auto_validated(links) do
    Enum.count(links, &(&1.confidence_score >= 0.85))
  end

  defp complete_correlation_job(state, results) do
    Logger.info("Completing correlation analysis for repository #{state.job.repository_id}")

    # Notify coordinator
    send(state.coordinator, {:worker_completed, self(), state.job.repository_id, results})
  end

  defp fail_correlation_job(state, reason) do
    Logger.error(
      "Correlation analysis failed for repository #{state.job.repository_id}: #{inspect(reason)}"
    )

    # Notify coordinator
    send(state.coordinator, {:worker_failed, self(), state.job.repository_id, reason})
  end
end
