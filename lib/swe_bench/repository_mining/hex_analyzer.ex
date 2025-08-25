defmodule SweBench.RepositoryMining.HexAnalyzer do
  @moduledoc """
  Hex.pm package analysis for repository discovery.

  Fetches package metadata, download statistics, and GitHub repository URLs
  from Hex.pm to identify high-quality Elixir packages for benchmarking.
  """

  require Logger

  alias SweBench.RepositoryMining.HexRateLimiter

  @hex_api_base "https://hex.pm/api"

  @doc """
  Discovers repositories from Hex.pm packages.

  ## Parameters
    - query_params: Search and filtering parameters
    - max_repositories: Maximum number of repositories to discover

  ## Returns
    - {:ok, repositories} - List of repository data
    - {:error, reason} - Error details
  """
  def discover_repositories(query_params \\ %{}, max_repositories \\ 100) do
    Logger.info("Discovering repositories from Hex.pm (max: #{max_repositories})")

    try do
      query_params
      |> fetch_packages_by_criteria(max_repositories)
      |> filter_packages_with_github()
      |> enhance_with_hex_metadata()
      |> convert_to_repository_format()
    catch
      error ->
        Logger.error("Hex.pm discovery failed: #{inspect(error)}")
        {:error, {:hex_discovery_failed, error}}
    end
  end

  @doc """
  Fetches detailed package information from Hex.pm.
  """
  def get_package_details(package_name) do
    Logger.debug("Fetching details for package: #{package_name}")

    # Placeholder implementation - will be enhanced in Phase 2
    case make_hex_request("/packages/#{package_name}") do
      {:ok, package_data} ->
        {:ok, package_data}

      {:error, reason} ->
        Logger.warning("Failed to fetch package #{package_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private implementation functions

  defp fetch_packages_by_criteria(query_params, max_repositories) do
    # Determine search strategy based on parameters
    sort_by = Map.get(query_params, :sort, "downloads")
    search_term = Map.get(query_params, :search)

    packages =
      if search_term do
        search_packages(search_term, max_repositories)
      else
        fetch_top_packages(sort_by, max_repositories)
      end

    case packages do
      {:ok, package_list} ->
        Logger.debug("Fetched #{length(package_list)} packages from Hex.pm")
        {:ok, package_list}

      {:error, reason} ->
        {:error, {:package_fetch_failed, reason}}
    end
  end

  defp fetch_top_packages(sort_by, max_repositories) do
    # Calculate pages needed (100 per page)
    pages_needed = div(max_repositories, 100) + 1

    packages =
      1..pages_needed
      |> Enum.reduce_while([], fn page, acc ->
        case make_hex_request("/packages", %{sort: sort_by, page: page}) do
          {:ok, page_packages} ->
            combined = acc ++ page_packages

            if length(combined) >= max_repositories do
              {:halt, Enum.take(combined, max_repositories)}
            else
              {:cont, combined}
            end

          {:error, reason} ->
            Logger.warning("Failed to fetch packages page #{page}: #{inspect(reason)}")
            {:halt, acc}
        end
      end)

    {:ok, packages}
  end

  defp search_packages(search_term, _max_repositories) do
    # Placeholder for package search implementation
    Logger.debug("Searching Hex.pm for: #{search_term}")
    {:ok, []}
  end

  defp filter_packages_with_github({:ok, packages}) do
    github_packages =
      packages
      |> Enum.filter(&has_github_repository?/1)
      |> Enum.map(&extract_github_url/1)

    Logger.debug("Filtered to #{length(github_packages)} packages with GitHub repositories")
    {:ok, github_packages}
  end

  defp filter_packages_with_github({:error, reason}), do: {:error, reason}

  defp has_github_repository?(package) do
    links = Map.get(package, "links", %{})

    Map.has_key?(links, "GitHub") or
      Map.has_key?(links, "Github") or
      Map.has_key?(links, "github")
  end

  defp extract_github_url(package) do
    links = Map.get(package, "links", %{})

    github_url =
      links["GitHub"] ||
        links["Github"] ||
        links["github"]

    package
    |> Map.put("github_url", github_url)
    |> Map.put("hex_package_name", Map.get(package, "name"))
  end

  defp enhance_with_hex_metadata({:ok, packages}) do
    enhanced_packages =
      packages
      |> Enum.map(fn package ->
        case get_package_details(package["name"]) do
          {:ok, details} ->
            Map.merge(package, details)

          {:error, _reason} ->
            # Use basic data if detailed fetch fails
            package
        end
      end)

    Logger.debug("Enhanced #{length(enhanced_packages)} packages with detailed metadata")
    {:ok, enhanced_packages}
  end

  defp enhance_with_hex_metadata({:error, reason}), do: {:error, reason}

  defp convert_to_repository_format({:ok, packages}) do
    repositories =
      packages
      |> Enum.map(&convert_package_to_repository/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, repo} -> repo end)

    Logger.debug("Converted #{length(repositories)} packages to repository format")
    {:ok, repositories}
  end

  defp convert_to_repository_format({:error, reason}), do: {:error, reason}

  defp convert_package_to_repository(package) do
    # Parse GitHub URL to extract owner and name
    case parse_github_url(package["github_url"]) do
      {:ok, {owner, repo_name}} ->
        repository_data = %{
          name: repo_name,
          full_name: "#{owner}/#{repo_name}",
          owner: %{login: owner},
          hex_package_name: package["hex_package_name"],
          description: Map.get(package, "description"),
          topics: Map.get(package, "topics", []),
          language: "Elixir",
          # Additional metadata from Hex.pm
          hex_metadata: %{
            downloads: Map.get(package, "downloads"),
            latest_version: get_latest_version(package),
            updated_at: Map.get(package, "updated_at")
          }
        }

        {:ok, repository_data}

      {:error, reason} ->
        {:error, {:invalid_github_url, reason}}
    end
  rescue
    error ->
      {:error, {:conversion_error, error}}
  end

  defp parse_github_url(url) when is_binary(url) do
    case Regex.run(~r{github\.com/([^/]+)/([^/\.]+)}, url) do
      [_full, owner, repo] ->
        {:ok, {owner, repo}}

      nil ->
        {:error, "Invalid GitHub URL format"}
    end
  end

  defp parse_github_url(_), do: {:error, "GitHub URL must be a string"}

  defp get_latest_version(package) do
    case Map.get(package, "releases") do
      [latest | _] -> Map.get(latest, "version")
      _ -> Map.get(package, "latest_version")
    end
  end

  defp make_hex_request(endpoint, params \\ %{}) do
    Logger.debug("Making Hex.pm request to #{endpoint}")

    case HexRateLimiter.request_permission() do
      :ok ->
      url = @hex_api_base <> endpoint

      case Req.get(url, params: params) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Hex.pm API returned status #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("Hex.pm API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end

      {:error, :rate_limited} ->
        Logger.warning("Hex.pm request rate limited, waiting...")
        Process.sleep(1000)
        make_hex_request(endpoint, params)
    end
  end
end
