defmodule SweBench.Issues.Collector do
  @moduledoc """
  Issue and PR data collection with relationship detection.

  Collects GitHub issues and pull requests, identifies relationships,
  and extracts relevant data for evaluation task generation.
  """

  require Logger

  alias SweBench.GitHub.{Cache, Paginator}

  @doc """
  Collects all issues and PRs for a repository.
  """
  def collect_repository_data(client, owner, repo_name, opts \\ []) do
    Logger.info("Collecting issues and PRs for #{owner}/#{repo_name}")

    cache_key = Cache.repository_cache_key(owner, repo_name, "issues_prs")

    Cache.fetch(
      cache_key,
      fn ->
        perform_collection(client, owner, repo_name, opts)
      end,
      opts
    )
  end

  @doc """
  Collects closed issues with linked pull requests.
  """
  def collect_closed_issues_with_prs(client, owner, repo_name, _opts \\ []) do
    Logger.debug("Collecting closed issues with PRs for #{owner}/#{repo_name}")

    with {:ok, issues} <- collect_issues(client, owner, repo_name, state: "closed"),
         {:ok, prs} <- collect_pull_requests(client, owner, repo_name, state: "closed") do
      linked_data = link_issues_and_prs(issues, prs)
      {:ok, linked_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Collects issues from repository with pagination.
  """
  def collect_issues(client, owner, repo_name, opts \\ []) do
    Logger.debug("Collecting issues for #{owner}/#{repo_name}")

    path = "/repos/#{owner}/#{repo_name}/issues"
    query_opts = build_query_options(opts)

    case Paginator.fetch_all_pages(client, path, query: query_opts) do
      {:ok, issues} ->
        processed_issues = Enum.map(issues, &process_issue_data/1)
        {:ok, processed_issues}

      {:error, reason} ->
        Logger.error("Failed to collect issues: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Collects pull requests from repository with pagination.
  """
  def collect_pull_requests(client, owner, repo_name, opts \\ []) do
    Logger.debug("Collecting pull requests for #{owner}/#{repo_name}")

    path = "/repos/#{owner}/#{repo_name}/pulls"
    query_opts = build_query_options(opts)

    case Paginator.fetch_all_pages(client, path, query: query_opts) do
      {:ok, prs} ->
        processed_prs = Enum.map(prs, &process_pr_data/1)
        {:ok, processed_prs}

      {:error, reason} ->
        Logger.error("Failed to collect pull requests: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Links issues and pull requests based on various relationship indicators.
  """
  def link_issues_and_prs(issues, prs) do
    Logger.debug("Linking #{length(issues)} issues with #{length(prs)} PRs")

    issue_map = Map.new(issues, fn issue -> {issue.number, issue} end)

    prs
    |> Enum.map(fn pr ->
      linked_issue = find_linked_issue(pr, issue_map)
      Map.put(pr, :linked_issue, linked_issue)
    end)
    |> Enum.filter(fn pr -> pr.linked_issue != nil end)
  end

  # Private helper functions

  defp perform_collection(client, owner, repo_name, opts) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, issues} <- collect_issues(client, owner, repo_name, opts),
         {:ok, prs} <- collect_pull_requests(client, owner, repo_name, opts) do
      collection_time = System.monotonic_time(:millisecond) - start_time

      result = %{
        issues: issues,
        pull_requests: prs,
        linked_issues_prs: link_issues_and_prs(issues, prs),
        collection_metadata: %{
          issues_count: length(issues),
          prs_count: length(prs),
          collection_time_ms: collection_time,
          collected_at: DateTime.utc_now()
        }
      }

      Logger.info(
        "Collected #{length(issues)} issues and #{length(prs)} PRs in #{collection_time}ms"
      )

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_query_options(opts) do
    base_opts = [
      state: Keyword.get(opts, :state, "all"),
      per_page: Keyword.get(opts, :per_page, 100),
      sort: "updated",
      direction: "desc"
    ]

    # Add since parameter if provided
    case Keyword.get(opts, :since) do
      nil -> base_opts
      since_date -> [{:since, since_date} | base_opts]
    end
  end

  defp process_issue_data(issue_data) do
    %{
      github_id: issue_data["id"],
      number: issue_data["number"],
      title: issue_data["title"],
      body: issue_data["body"],
      state: issue_data["state"],
      labels: extract_label_names(issue_data["labels"] || []),
      created_at: parse_github_datetime(issue_data["created_at"]),
      updated_at: parse_github_datetime(issue_data["updated_at"]),
      closed_at: parse_github_datetime(issue_data["closed_at"]),
      user: issue_data["user"]["login"],
      assignees: extract_assignee_names(issue_data["assignees"] || [])
    }
  end

  defp process_pr_data(pr_data) do
    %{
      github_id: pr_data["id"],
      number: pr_data["number"],
      title: pr_data["title"],
      body: pr_data["body"],
      state: pr_data["state"],
      additions: pr_data["additions"] || 0,
      deletions: pr_data["deletions"] || 0,
      changed_files: pr_data["changed_files"] || 0,
      created_at: parse_github_datetime(pr_data["created_at"]),
      updated_at: parse_github_datetime(pr_data["updated_at"]),
      merged_at: parse_github_datetime(pr_data["merged_at"]),
      closed_at: parse_github_datetime(pr_data["closed_at"]),
      user: pr_data["user"]["login"],
      mergeable: pr_data["mergeable"]
    }
  end

  defp find_linked_issue(pr, issue_map) do
    # Try multiple strategies to find linked issues
    cond do
      # Strategy 1: PR title contains "fixes #123" or similar
      issue_number = extract_issue_number_from_text(pr.title) ->
        Map.get(issue_map, issue_number)

      # Strategy 2: PR body contains issue references
      issue_number = extract_issue_number_from_text(pr.body || "") ->
        Map.get(issue_map, issue_number)

      # Strategy 3: Same number (GitHub auto-links)
      issue = Map.get(issue_map, pr.number) ->
        issue

      true ->
        nil
    end
  end

  defp extract_issue_number_from_text(text) when is_binary(text) do
    case Regex.run(~r/(?:fix|fixes|close|closes|resolve|resolves)\s*#(\d+)/i, text) do
      [_, number_str] -> String.to_integer(number_str)
      nil -> nil
    end
  end

  defp extract_issue_number_from_text(_), do: nil

  defp extract_label_names(labels) when is_list(labels) do
    Enum.map(labels, fn label -> label["name"] end)
  end

  defp extract_label_names(_), do: []

  defp extract_assignee_names(assignees) when is_list(assignees) do
    Enum.map(assignees, fn assignee -> assignee["login"] end)
  end

  defp extract_assignee_names(_), do: []

  defp parse_github_datetime(nil), do: nil

  defp parse_github_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end
end
