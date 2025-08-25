defmodule SweBench.RepositoryMining.EnhancedGitHubClient do
  @moduledoc """
  Enhanced GitHub client for repository mining operations.

  Extends the existing GitHub client with additional functions needed for
  repository discovery, quality assessment, and mining operations.
  """

  require Logger

  alias SweBench.GitHub.Client
  alias SweBench.RepositoryMining.GitHubRateLimiter

  @doc """
  Searches for repositories using GitHub Search API.
  """
  def search_repositories(query, max_results \\ 100) do
    Logger.debug("Searching GitHub repositories: #{query}")

    with :ok <- GitHubRateLimiter.request_permission(:search) do
      # Use existing GitHub client with search endpoint
      client = Client.new()

      search_params = %{
        q: query,
        sort: "stars",
        order: "desc",
        per_page: min(max_results, 100)
      }

      case Client.api_get(client, "/search/repositories", query: search_params) do
        {:ok, %{"items" => repositories}} ->
          limited_repos = Enum.take(repositories, max_results)
          Logger.info("Found #{length(limited_repos)} repositories for query: #{query}")
          {:ok, limited_repos}

        {:ok, response} ->
          Logger.warning("Unexpected search response format: #{inspect(response)}")
          {:error, {:unexpected_response, response}}

        {:error, reason} ->
          Logger.error("GitHub repository search failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        Logger.warning("GitHub search rate limited")
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets detailed repository information including contributors and languages.
  """
  def get_repository_details(owner, repo_name) do
    Logger.debug("Fetching repository details: #{owner}/#{repo_name}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      client = Client.new()

      # Get basic repository data using existing function
      case Client.get_repository(client, owner, repo_name) do
        {:ok, repo_data} ->
          enhance_repository_data(client, repo_data, owner, repo_name)

        {:error, reason} ->
          Logger.warning("Failed to fetch repository #{owner}/#{repo_name}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets repository contributors.
  """
  def get_contributors(client, owner, repo_name) do
    Logger.debug("Fetching contributors for #{owner}/#{repo_name}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contributors") do
        {:ok, contributors} when is_list(contributors) ->
          {:ok, contributors}

        {:ok, response} ->
          {:error, {:unexpected_response, response}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets repository language statistics.
  """
  def get_languages(client, owner, repo_name) do
    Logger.debug("Fetching languages for #{owner}/#{repo_name}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      case Client.api_get(client, "/repos/#{owner}/#{repo_name}/languages") do
        {:ok, languages} when is_map(languages) ->
          {:ok, languages}

        {:ok, response} ->
          {:error, {:unexpected_response, response}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets repository topics.
  """
  def get_topics(client, owner, repo_name) do
    Logger.debug("Fetching topics for #{owner}/#{repo_name}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      headers = [{"accept", "application/vnd.github.mercy-preview+json"}]

      case Tesla.get(client, "/repos/#{owner}/#{repo_name}/topics", headers: headers) do
        {:ok, %{status: 200, body: %{"names" => topics}}} ->
          {:ok, topics}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Topics API returned status #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets repository contents for a specific path.
  """
  def get_repository_contents(client, owner, repo_name, path \\ "") do
    Logger.debug("Fetching contents for #{owner}/#{repo_name} at path: #{path}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contents/#{path}") do
        {:ok, contents} when is_list(contents) ->
          {:ok, contents}

        {:ok, content} when is_map(content) ->
          # Single file response
          {:ok, [content]}

        {:ok, response} ->
          {:error, {:unexpected_response, response}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets file content from repository.
  """
  def get_file_content(client, owner, repo_name, file_path) do
    Logger.debug("Fetching file content: #{owner}/#{repo_name}/#{file_path}")

    with :ok <- GitHubRateLimiter.request_permission(:standard) do
      case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contents/#{file_path}") do
        {:ok, %{"content" => encoded_content, "encoding" => "base64"}} ->
          case Base.decode64(encoded_content) do
            {:ok, content} -> {:ok, content}
            :error -> {:error, :base64_decode_failed}
          end

        {:ok, response} ->
          {:error, {:unexpected_response, response}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  # Private helper functions

  defp enhance_repository_data(client, repo_data, owner, repo_name) do
    # Collect additional data in parallel tasks with timeouts
    enhancement_tasks = [
      Task.async(fn -> get_contributors(client, owner, repo_name) end),
      Task.async(fn -> get_languages(client, owner, repo_name) end),
      Task.async(fn -> get_topics(client, owner, repo_name) end)
    ]

    # Wait for all tasks with timeout
    enhancement_results = Task.await_many(enhancement_tasks, 30_000)

    # Process results and enhance repository data
    enhanced_data =
      enhancement_results
      |> Enum.zip([:contributors, :languages, :topics])
      |> Enum.reduce(repo_data, fn {result, key}, acc ->
        case result do
          {:ok, data} -> Map.put(acc, key, data)
          {:error, _reason} -> acc
        end
      end)

    {:ok, enhanced_data}
  rescue
    error ->
      Logger.error("Failed to enhance repository data: #{inspect(error)}")
      # Return basic data if enhancement fails
      {:ok, repo_data}
  end
end
