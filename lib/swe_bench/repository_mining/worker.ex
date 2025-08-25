defmodule SweBench.RepositoryMining.Worker do
  @moduledoc """
  Individual worker process for repository mining operations.

  Handles discovery, analysis, and quality assessment of repositories from
  various sources (Hex.pm, GitHub) with proper error handling and reporting.
  """

  use GenServer
  require Logger

  alias SweBench.Repositories.{MiningJob, Repository, QualityMetrics}
  alias SweBench.RepositoryMining.{HexAnalyzer, GitHubAnalyzer, QualityScorer}

  defstruct [
    :job,
    :coordinator,
    :start_time,
    :repositories_discovered,
    :repositories_analyzed,
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
      repositories_discovered: 0,
      repositories_analyzed: 0,
      current_operation: :initializing
    }

    # Start processing immediately
    send(self(), :start_mining)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_mining, state) do
    Logger.info("Starting mining job #{state.job.id} for source: #{state.job.source}")

    # Mark job as running
    mark_job_running(state.job)

    # Update state and begin processing
    updated_state = %{state | current_operation: :discovering}

    case execute_mining_pipeline(state) do
      {:ok, results} ->
        complete_mining_job(state, results)

      {:error, reason} ->
        fail_mining_job(state, reason)
    end

    {:stop, :normal, updated_state}
  end

  # Private implementation functions

  defp execute_mining_pipeline(state) do
    try do
      repositories =
        state.job.source
        |> discover_repositories(state.job.query_params, state.job.max_repositories)
        |> analyze_repositories(state)
        |> persist_repositories(state)

      processing_time = DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)

      result = %{
        repositories_discovered: length(repositories),
        repositories_analyzed: count_analyzed_repositories(repositories),
        processing_time_ms: processing_time,
        discovery_source: state.job.source
      }

      {:ok, result}
    rescue
      error ->
        Logger.error("Mining pipeline error in job #{state.job.id}: #{inspect(error)}")
        {:error, {:pipeline_error, error}}
    end
  end

  defp discover_repositories(source, query_params, max_repositories) do
    Logger.debug("Discovering repositories from #{source}")

    case source do
      :hex_pm ->
        HexAnalyzer.discover_repositories(query_params, max_repositories)

      :github_trending ->
        GitHubAnalyzer.discover_trending_repositories(query_params, max_repositories)

      :github_search ->
        GitHubAnalyzer.search_repositories(query_params, max_repositories)

      :manual_list ->
        get_manual_repository_list(query_params)
    end
  end

  defp analyze_repositories({:ok, repositories}, state) do
    Logger.debug("Analyzing #{length(repositories)} repositories")

    analyzed_repositories =
      repositories
      |> Enum.map(fn repo_data ->
        _updated_state = %{state | current_operation: {:analyzing, repo_data.name}}

        case analyze_single_repository(repo_data) do
          {:ok, analyzed_repo} ->
            analyzed_repo

          {:error, reason} ->
            Logger.warning("Failed to analyze repository #{repo_data.name}: #{inspect(reason)}")
            Map.put(repo_data, :analysis_error, reason)
        end
      end)

    {:ok, analyzed_repositories}
  end

  defp analyze_repositories({:error, reason}, _state) do
    {:error, {:discovery_failed, reason}}
  end

  defp analyze_single_repository(repo_data) do
    with {:ok, enhanced_data} <- fetch_detailed_metadata(repo_data),
         {:ok, quality_scores} <- QualityScorer.calculate_quality_scores(enhanced_data),
         {:ok, _categorized_data} <- categorize_repository(enhanced_data, quality_scores) do
      analyzed_repo =
        Map.merge(enhanced_data, %{
          quality_scores: quality_scores,
          analysis_completed_at: DateTime.utc_now()
        })

      {:ok, analyzed_repo}
    end
  end

  defp fetch_detailed_metadata(repo_data) do
    # Placeholder - will be implemented in Phase 2
    {:ok, repo_data}
  end

  defp categorize_repository(repo_data, quality_scores) do
    # Placeholder - will be implemented in Phase 3
    category = determine_repository_category(quality_scores.overall_score)
    {:ok, Map.put(repo_data, :category, category)}
  end

  defp persist_repositories({:ok, repositories}, state) do
    Logger.debug("Persisting #{length(repositories)} repositories")

    persisted_repos =
      repositories
      |> Enum.map(&persist_single_repository(&1, state.job.id))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, repo} -> repo end)

    Logger.info("Successfully persisted #{length(persisted_repos)} repositories")
    persisted_repos
  end

  defp persist_repositories({:error, reason}, _state) do
    Logger.error("Cannot persist repositories due to analysis failure: #{inspect(reason)}")
    []
  end

  defp persist_single_repository(repo_data, mining_job_id) do
    attrs = %{
      github_id: Map.get(repo_data, :id),
      name: Map.get(repo_data, :name),
      full_name: Map.get(repo_data, :full_name),
      owner: Map.get(repo_data, :owner, %{}) |> Map.get(:login, "unknown"),
      description: Map.get(repo_data, :description),
      language: Map.get(repo_data, :language),
      stars_count: Map.get(repo_data, :stargazers_count, 0),
      forks_count: Map.get(repo_data, :forks_count, 0),
      has_issues: Map.get(repo_data, :has_issues, true),
      hex_package_name: Map.get(repo_data, :hex_package_name),
      default_branch: Map.get(repo_data, :default_branch, "main"),
      topics: Map.get(repo_data, :topics, []),
      license: get_license_name(repo_data),
      mining_status: :completed,
      mining_job_id: mining_job_id,
      mining_metadata: extract_mining_metadata(repo_data)
    }

    Repository
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  defp get_license_name(repo_data) do
    case Map.get(repo_data, :license) do
      %{name: name} when is_binary(name) -> name
      %{"name" => name} when is_binary(name) -> name
      _ -> nil
    end
  end

  defp extract_mining_metadata(repo_data) do
    %{
      discovered_at: DateTime.utc_now(),
      source_api: determine_source_api(repo_data),
      quality_scores: Map.get(repo_data, :quality_scores, %{}),
      category: Map.get(repo_data, :category),
      analysis_version: "1.0.0"
    }
  end

  defp determine_source_api(repo_data) do
    cond do
      Map.has_key?(repo_data, :hex_package_name) -> :hex_pm
      Map.has_key?(repo_data, :stargazers_count) -> :github
      true -> :unknown
    end
  end

  defp count_analyzed_repositories(repositories) do
    Enum.count(repositories, &Map.has_key?(&1, :quality_scores))
  end

  defp get_manual_repository_list(query_params) do
    # Extract repository list from manual specification
    repositories = Map.get(query_params, :repositories, [])
    {:ok, repositories}
  end

  defp determine_repository_category(overall_score) when overall_score >= 85, do: :excellent
  defp determine_repository_category(overall_score) when overall_score >= 70, do: :good
  defp determine_repository_category(overall_score) when overall_score >= 55, do: :average
  defp determine_repository_category(overall_score) when overall_score >= 40, do: :below_average
  defp determine_repository_category(_overall_score), do: :poor

  defp mark_job_running(job) do
    job
    |> Ash.Changeset.for_update(:mark_running, %{})
    |> Ash.update()
  end

  defp complete_mining_job(state, results) do
    Logger.info("Completing mining job #{state.job.id}")

    # Update job with results
    state.job
    |> Ash.Changeset.for_update(:mark_completed, %{
      repositories_discovered: results.repositories_discovered
    })
    |> Ash.update()

    # Notify coordinator
    send(state.coordinator, {:worker_completed, self(), state.job.id, results})
  end

  defp fail_mining_job(state, reason) do
    error_message = inspect(reason)
    Logger.error("Mining job #{state.job.id} failed: #{error_message}")

    # Update job with failure
    state.job
    |> Ash.Changeset.for_update(:mark_failed, %{
      error_message: error_message
    })
    |> Ash.update()

    # Notify coordinator
    send(state.coordinator, {:worker_failed, self(), state.job.id, reason})
  end
end
