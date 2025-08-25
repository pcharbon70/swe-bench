defmodule SweBench.GitHub.EnhancedIssuesClient do
  @moduledoc """
  Enhanced GitHub client for issue and pull request operations.

  Extends the existing GitHub client with specialized functions for
  issue-PR correlation analysis and benchmark task generation.
  """

  require Logger

  alias SweBench.GitHub.Client
  alias SweBench.RepositoryMining.GitHubRateLimiter

  @doc """
  Fetches all closed issues for a repository with comprehensive metadata.
  """
  def get_closed_issues(owner, repo_name, opts \\ []) do
    Logger.debug("Fetching closed issues for #{owner}/#{repo_name}")

    per_page = Keyword.get(opts, :per_page, 100)
    since_date = Keyword.get(opts, :since)

    params = %{
      state: "closed",
      per_page: per_page,
      sort: "updated",
      direction: "desc"
    }

    params =
      if since_date do
        Map.put(params, :since, since_date)
      else
        params
      end

    fetch_paginated_data("/repos/#{owner}/#{repo_name}/issues", params, opts)
  end

  @doc """
  Fetches all merged pull requests for a repository.
  """
  def get_merged_pull_requests(owner, repo_name, opts \\ []) do
    Logger.debug("Fetching merged PRs for #{owner}/#{repo_name}")

    per_page = Keyword.get(opts, :per_page, 100)

    params = %{
      state: "closed",
      per_page: per_page,
      sort: "updated",
      direction: "desc"
    }

    fetch_paginated_data("/repos/#{owner}/#{repo_name}/pulls", params, opts)
    |> filter_merged_prs()
  end

  @doc """
  Gets detailed pull request information including diff and commit data.
  """
  def get_pull_request_details(owner, repo_name, pr_number) do
    Logger.debug("Fetching PR details: #{owner}/#{repo_name}##{pr_number}")

    case GitHubRateLimiter.request_permission(:standard) do
      :ok ->
        client = Client.new()

        with {:ok, pr_data} <- Client.api_get(client, "/repos/#{owner}/#{repo_name}/pulls/#{pr_number}"),
             {:ok, commits} <- get_pr_commits(client, owner, repo_name, pr_number),
             {:ok, files} <- get_pr_files(client, owner, repo_name, pr_number) do

          enhanced_pr = Map.merge(pr_data, %{
            commits: commits,
            files: files,
            commit_messages: extract_commit_messages(commits)
          })

          {:ok, enhanced_pr}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets commit messages for a pull request.
  """
  def get_pr_commits(client, owner, repo_name, pr_number) do
    Logger.debug("Fetching commits for PR #{owner}/#{repo_name}##{pr_number}")

    case GitHubRateLimiter.request_permission(:standard) do
      :ok ->
        case Client.api_get(client, "/repos/#{owner}/#{repo_name}/pulls/#{pr_number}/commits") do
          {:ok, commits} when is_list(commits) ->
            {:ok, commits}

          {:ok, response} ->
            {:error, {:unexpected_response, response}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Gets file changes for a pull request.
  """
  def get_pr_files(client, owner, repo_name, pr_number) do
    Logger.debug("Fetching file changes for PR #{owner}/#{repo_name}##{pr_number}")

    case GitHubRateLimiter.request_permission(:standard) do
      :ok ->
        case Client.api_get(client, "/repos/#{owner}/#{repo_name}/pulls/#{pr_number}/files") do
          {:ok, files} when is_list(files) ->
            {:ok, files}

          {:ok, response} ->
            {:error, {:unexpected_response, response}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Searches for issues related to specific keywords or patterns.
  """
  def search_issues(owner, repo_name, query, opts \\ []) do
    Logger.debug("Searching issues in #{owner}/#{repo_name}: #{query}")

    case GitHubRateLimiter.request_permission(:search) do
      :ok ->
        client = Client.new()
        per_page = Keyword.get(opts, :per_page, 100)

        search_query = "#{query} repo:#{owner}/#{repo_name} is:issue is:closed"

        search_params = %{
          q: search_query,
          sort: "updated",
          order: "desc",
          per_page: per_page
        }

        case Client.api_get(client, "/search/issues", query: search_params) do
          {:ok, %{"items" => issues, "total_count" => total}} ->
            Logger.info("Found #{length(issues)} issues (#{total} total) for query: #{query}")
            {:ok, issues}

          {:ok, response} ->
            Logger.warning("Unexpected search response: #{inspect(response)}")
            {:error, {:unexpected_response, response}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  # Private implementation functions

  defp fetch_paginated_data(endpoint, params, opts) do
    max_pages = Keyword.get(opts, :max_pages, 10)
    all_items = []

    case GitHubRateLimiter.request_permission(:standard) do
      :ok ->
        client = Client.new()
        fetch_pages(client, endpoint, params, all_items, 1, max_pages)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp fetch_pages(client, endpoint, params, acc_items, current_page, max_pages)
       when current_page <= max_pages do
    page_params = Map.put(params, :page, current_page)

    case Client.api_get(client, endpoint, query: page_params) do
      {:ok, items} when is_list(items) ->
        all_items = acc_items ++ items

        if length(items) < Map.get(params, :per_page, 100) do
          # Last page reached
          {:ok, all_items}
        else
          # Continue to next page (with rate limiting consideration)
          fetch_pages(client, endpoint, params, all_items, current_page + 1, max_pages)
        end

      {:ok, response} ->
        Logger.warning("Unexpected pagination response: #{inspect(response)}")
        {:ok, acc_items}

      {:error, reason} ->
        Logger.warning("Failed to fetch page #{current_page}: #{inspect(reason)}")
        {:ok, acc_items}
    end
  end

  defp fetch_pages(_client, _endpoint, _params, acc_items, current_page, max_pages)
       when current_page > max_pages do
    Logger.info("Reached maximum pages limit (#{max_pages}), returning #{length(acc_items)} items")
    {:ok, acc_items}
  end

  defp filter_merged_prs({:ok, prs}) do
    merged_prs = Enum.filter(prs, &(&1["merged_at"] != nil))
    Logger.debug("Filtered to #{length(merged_prs)} merged PRs from #{length(prs)} total")
    {:ok, merged_prs}
  end

  defp filter_merged_prs({:error, reason}), do: {:error, reason}

  defp extract_commit_messages(commits) when is_list(commits) do
    commits
    |> Enum.map(&get_in(&1, ["commit", "message"]))
    |> Enum.filter(&is_binary/1)
  end

  defp extract_commit_messages(_), do: []
end