defmodule SweBench.RepositoryMining.GitHubAnalyzer do
  @moduledoc """
  GitHub repository analysis for discovery and quality assessment.

  Leverages GitHub Search API and repository metadata to identify high-quality
  Elixir repositories with comprehensive analysis capabilities.
  """

  require Logger

  alias SweBench.GitHub.Client
  alias SweBench.RepositoryMining.EnhancedGitHubClient

  @doc """
  Discovers trending Elixir repositories from GitHub.

  ## Parameters
    - query_params: Search and filtering parameters
    - max_repositories: Maximum number of repositories to discover

  ## Returns
    - {:ok, repositories} - List of repository data
    - {:error, reason} - Error details
  """
  def discover_trending_repositories(query_params \\ %{}, max_repositories \\ 100) do
    Logger.info("Discovering trending repositories from GitHub (max: #{max_repositories})")

    search_query = build_trending_search_query(query_params)

    EnhancedGitHubClient.search_repositories(search_query, max_repositories)
  end

  @doc """
  Searches GitHub repositories with custom criteria.
  """
  def search_repositories(query_params, max_repositories \\ 100) do
    Logger.info("Searching GitHub repositories with custom criteria (max: #{max_repositories})")

    search_query = build_custom_search_query(query_params)

    EnhancedGitHubClient.search_repositories(search_query, max_repositories)
  end

  @doc """
  Fetches detailed repository information from GitHub.
  """
  def get_repository_details(owner, repo_name) do
    Logger.debug("Fetching details for repository: #{owner}/#{repo_name}")

    with {:ok, repo_data} <- EnhancedGitHubClient.get_repository_details(owner, repo_name) do
      {:ok, repo_data}
    else
      {:error, reason} ->
        Logger.warning("Failed to fetch repository details for #{owner}/#{repo_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Analyzes repository structure for Elixir-specific patterns.
  """
  def analyze_repository_structure(owner, repo_name) do
    Logger.debug("Analyzing repository structure: #{owner}/#{repo_name}")

    client = Client.new()

    with {:ok, contents} <- EnhancedGitHubClient.get_repository_contents(client, owner, repo_name, ""),
         {:ok, mix_exs} <- fetch_mix_file(client, owner, repo_name),
         {:ok, test_structure} <- analyze_test_structure(owner, repo_name) do
      structure_analysis = %{
        has_mix_file: not is_nil(mix_exs),
        is_umbrella_project: detect_umbrella_project(mix_exs),
        test_directories: test_structure.directories,
        test_file_count: test_structure.file_count,
        has_ci_config: detect_ci_configuration(contents),
        project_structure: categorize_project_structure(contents)
      }

      {:ok, structure_analysis}
    else
      {:error, reason} ->
        Logger.warning("Failed to analyze structure for #{owner}/#{repo_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private implementation functions

  defp build_trending_search_query(query_params) do
    base_query = "language:elixir"

    # Add time-based filtering for trending
    days_back = Map.get(query_params, :days_back, 30)
    date_filter = Date.add(Date.utc_today(), -days_back) |> Date.to_string()

    trending_query = "#{base_query} pushed:>#{date_filter}"

    # Add minimum stars for quality filtering
    min_stars = Map.get(query_params, :min_stars, 10)
    quality_query = "#{trending_query} stars:>#{min_stars}"

    # Add additional filters
    quality_query
    |> add_optional_filter("fork:false", Map.get(query_params, :exclude_forks, true))
    |> add_optional_filter("archived:false", Map.get(query_params, :exclude_archived, true))
  end

  defp build_custom_search_query(query_params) do
    base_query = Map.get(query_params, :query, "language:elixir")

    base_query
    |> add_optional_filter("stars:>#{query_params[:min_stars]}", Map.has_key?(query_params, :min_stars))
    |> add_optional_filter("fork:false", Map.get(query_params, :exclude_forks, true))
    |> add_optional_filter("archived:false", Map.get(query_params, :exclude_archived, true))
  end

  defp add_optional_filter(query, _filter, false), do: query
  defp add_optional_filter(query, filter, true), do: "#{query} #{filter}"

  defp fetch_mix_file(client, owner, repo_name) do
    case EnhancedGitHubClient.get_file_content(client, owner, repo_name, "mix.exs") do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:ok, nil}
    end
  end

  defp analyze_test_structure(_owner, _repo_name) do
    # Placeholder implementation for test structure analysis
    test_structure = %{
      directories: ["test"],
      file_count: 0,
      test_frameworks: ["ExUnit"]
    }

    {:ok, test_structure}
  end

  defp detect_umbrella_project(mix_content) when is_binary(mix_content) do
    String.contains?(mix_content, "umbrella: true") or
      String.contains?(mix_content, ":umbrella")
  end

  defp detect_umbrella_project(_), do: false

  defp detect_ci_configuration(contents) when is_list(contents) do
    Enum.any?(contents, fn item ->
      name = Map.get(item, "name", "")

      name in [".github", "circle.yml", ".travis.yml", ".gitlab-ci.yml"] or
        String.starts_with?(name, ".github/workflows/")
    end)
  end

  defp detect_ci_configuration(_), do: false

  defp categorize_project_structure(contents) when is_list(contents) do
    directory_names =
      contents
      |> Enum.filter(&(Map.get(&1, "type") == "dir"))
      |> Enum.map(&Map.get(&1, "name"))

    cond do
      "apps" in directory_names -> :umbrella
      "lib" in directory_names and "test" in directory_names -> :standard
      "lib" in directory_names -> :library
      true -> :unknown
    end
  end

  defp categorize_project_structure(_), do: :unknown
end
