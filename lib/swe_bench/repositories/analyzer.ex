defmodule SweBench.Repositories.Analyzer do
  @moduledoc """
  Repository metadata analysis and processing.

  Analyzes GitHub repositories to extract metadata, detect Elixir-specific
  patterns, and identify project structure for evaluation task generation.
  """

  require Logger

  alias SweBench.GitHub.{Cache, Client}

  @doc """
  Analyzes a repository by owner and name, extracting all relevant metadata.
  """
  def analyze_repository(client, owner, repo_name, opts \\ []) do
    Logger.info("Starting analysis of #{owner}/#{repo_name}")

    cache_key = Cache.repository_cache_key(owner, repo_name, "full_analysis")

    Cache.fetch(
      cache_key,
      fn ->
        perform_full_analysis(client, owner, repo_name, opts)
      end,
      opts
    )
  end

  @doc """
  Extracts basic repository metadata from GitHub API.
  """
  def extract_repository_metadata(repo_data) do
    %{
      github_id: repo_data["id"],
      name: repo_data["name"],
      full_name: repo_data["full_name"],
      owner: repo_data["owner"]["login"],
      description: repo_data["description"],
      language: repo_data["language"],
      stars_count: repo_data["stargazers_count"] || 0,
      forks_count: repo_data["forks_count"] || 0,
      has_issues: repo_data["has_issues"] || false,
      default_branch: repo_data["default_branch"] || "main",
      topics: repo_data["topics"] || [],
      license: extract_license_info(repo_data["license"]),
      created_at: parse_github_datetime(repo_data["created_at"]),
      updated_at: parse_github_datetime(repo_data["updated_at"])
    }
  end

  @doc """
  Detects if a repository is an Elixir umbrella project.
  """
  def detect_umbrella_project(client, owner, repo_name) do
    Logger.debug("Detecting umbrella project structure for #{owner}/#{repo_name}")

    case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contents/mix.exs") do
      {:ok, mix_file} ->
        analyze_mix_file_for_umbrella(mix_file)

      {:error, :not_found} ->
        {:ok, false}

      {:error, reason} ->
        Logger.warning("Failed to fetch mix.exs for #{owner}/#{repo_name}: #{inspect(reason)}")
        {:ok, false}
    end
  end

  @doc """
  Extracts Hex.pm package information if available.
  """
  def extract_hex_package_info(client, owner, repo_name) do
    Logger.debug("Extracting Hex package info for #{owner}/#{repo_name}")

    case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contents/mix.exs") do
      {:ok, mix_file} ->
        analyze_mix_file_for_hex_package(mix_file)

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        Logger.warning("Failed to fetch mix.exs for hex analysis: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  @doc """
  Analyzes commit history to understand repository activity patterns.
  """
  def analyze_commit_history(client, owner, repo_name, opts \\ []) do
    Logger.debug("Analyzing commit history for #{owner}/#{repo_name}")

    since_date = Keyword.get(opts, :since, days_ago(90))

    case Client.get_commits(client, owner, repo_name, since: since_date, per_page: 100) do
      {:ok, commits} ->
        analyze_commits_for_patterns(commits)

      {:error, reason} ->
        Logger.warning("Failed to fetch commits: #{inspect(reason)}")
        {:ok, %{commit_count: 0, test_modifications: 0, active_contributors: []}}
    end
  end

  @doc """
  Calculates repository complexity metrics.
  """
  def calculate_complexity_metrics(client, owner, repo_name) do
    Logger.debug("Calculating complexity metrics for #{owner}/#{repo_name}")

    with {:ok, repo_data} <- Client.get_repository(client, owner, repo_name),
         {:ok, languages} <- get_repository_languages(client, owner, repo_name),
         {:ok, file_structure} <- analyze_file_structure(client, owner, repo_name) do
      metrics = %{
        size_kb: repo_data["size"] || 0,
        languages: languages,
        file_count: count_repository_files(file_structure),
        test_file_count: count_test_files(file_structure),
        complexity_score: calculate_complexity_score(repo_data, languages, file_structure)
      }

      {:ok, metrics}
    else
      {:error, reason} ->
        Logger.warning("Failed to calculate complexity metrics: #{inspect(reason)}")
        {:ok, %{complexity_score: 0}}
    end
  end

  # Private helper functions

  defp perform_full_analysis(client, owner, repo_name, opts) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, repo_data} <- Client.get_repository(client, owner, repo_name),
         metadata <- extract_repository_metadata(repo_data),
         {:ok, is_umbrella} <- detect_umbrella_project(client, owner, repo_name),
         {:ok, hex_package} <- extract_hex_package_info(client, owner, repo_name),
         {:ok, commit_analysis} <- analyze_commit_history(client, owner, repo_name, opts),
         {:ok, complexity} <- calculate_complexity_metrics(client, owner, repo_name) do
      analysis_time = System.monotonic_time(:millisecond) - start_time

      full_metadata =
        Map.merge(metadata, %{
          is_umbrella_project: is_umbrella,
          hex_package_name: hex_package,
          analysis_metadata: %{
            commit_analysis: commit_analysis,
            complexity_metrics: complexity,
            analysis_time_ms: analysis_time,
            analyzed_at: DateTime.utc_now()
          }
        })

      Logger.info("Completed analysis of #{owner}/#{repo_name} in #{analysis_time}ms")
      {:ok, full_metadata}
    else
      {:error, reason} ->
        Logger.error("Repository analysis failed for #{owner}/#{repo_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_license_info(nil), do: nil

  defp extract_license_info(license_data) when is_map(license_data) do
    license_data["spdx_id"] || license_data["name"]
  end

  defp parse_github_datetime(nil), do: nil

  defp parse_github_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end

  defp analyze_mix_file_for_umbrella(mix_file) do
    case decode_file_content(mix_file) do
      {:ok, content} ->
        is_umbrella =
          String.contains?(content, "umbrella: true") or
            String.contains?(content, "apps_path:")

        {:ok, is_umbrella}

      {:error, reason} ->
        Logger.warning("Failed to decode mix.exs content: #{inspect(reason)}")
        {:ok, false}
    end
  end

  defp analyze_mix_file_for_hex_package(mix_file) do
    case decode_file_content(mix_file) do
      {:ok, content} ->
        extract_package_name_from_mix_content(content)

      {:error, reason} ->
        Logger.warning("Failed to decode mix.exs for hex analysis: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  defp decode_file_content(%{"content" => content, "encoding" => "base64"}) do
    case Base.decode64(content) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_file_content(_), do: {:error, :invalid_file_format}

  defp extract_package_name_from_mix_content(content) do
    case Regex.run(~r/package:\s*\[\s*name:\s*:(\w+)/, content) do
      [_, package_name] -> {:ok, package_name}
      nil -> {:ok, nil}
    end
  end

  defp analyze_commits_for_patterns(commits) when is_list(commits) do
    analysis = %{
      commit_count: length(commits),
      test_modifications: count_test_modifications(commits),
      active_contributors: extract_unique_contributors(commits),
      recent_activity_score: calculate_activity_score(commits)
    }

    {:ok, analysis}
  end

  defp count_test_modifications(commits) do
    commits
    |> Enum.count(fn commit ->
      message = commit["commit"]["message"] || ""
      String.contains?(String.downcase(message), "test")
    end)
  end

  defp extract_unique_contributors(commits) do
    commits
    |> Enum.map(fn commit -> commit["author"]["login"] end)
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp calculate_activity_score(commits) do
    # Simple scoring based on commit frequency and recency
    now = DateTime.utc_now()

    commits
    |> Enum.map(fn commit ->
      commit_date = parse_github_datetime(commit["commit"]["author"]["date"])

      case commit_date do
        nil ->
          0

        date ->
          days_old = DateTime.diff(now, date, :day)
          max(0, 100 - days_old)
      end
    end)
    |> Enum.sum()
    |> div(max(1, length(commits)))
  end

  defp get_repository_languages(client, owner, repo_name) do
    case Client.api_get(client, "/repos/#{owner}/#{repo_name}/languages") do
      {:ok, languages} ->
        {:ok, languages}

      {:error, reason} ->
        Logger.warning("Failed to fetch languages: #{inspect(reason)}")
        {:ok, %{}}
    end
  end

  defp analyze_file_structure(client, owner, repo_name) do
    case Client.api_get(client, "/repos/#{owner}/#{repo_name}/contents") do
      {:ok, contents} when is_list(contents) ->
        {:ok, contents}

      {:error, reason} ->
        Logger.warning("Failed to fetch file structure: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp count_repository_files(file_structure) when is_list(file_structure) do
    file_structure
    |> Enum.count(fn item -> item["type"] == "file" end)
  end

  defp count_repository_files(_), do: 0

  defp count_test_files(file_structure) when is_list(file_structure) do
    file_structure
    |> Enum.count(fn item ->
      item["type"] == "file" && String.contains?(item["name"] || "", "test")
    end)
  end

  defp count_test_files(_), do: 0

  defp calculate_complexity_score(repo_data, languages, file_structure) do
    size_score = min(50, (repo_data["size"] || 0) / 1000)
    language_score = map_size(languages) * 5
    file_score = min(30, count_repository_files(file_structure) / 10)

    round(size_score + language_score + file_score)
  end

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 24 * 3600, :second)
    |> DateTime.to_iso8601()
  end
end
