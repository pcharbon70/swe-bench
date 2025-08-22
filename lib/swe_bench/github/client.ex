defmodule SweBench.GitHub.Client do
  @moduledoc """
  GitHub API HTTP client with OAuth authentication and rate limiting.

  Provides a Tesla-based HTTP client for GitHub API interactions with:
  - OAuth authentication flow
  - Rate limiting with exponential backoff
  - Request/response error handling
  - Secure token management
  """

  use Tesla

  require Logger

  alias SweBench.GitHub.RateLimiter

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "SweBench-Elixir/1.0"}]
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Timeout, timeout: 30_000

  @doc """
  Creates an authenticated client with access token.
  """
  def new(access_token) when is_binary(access_token) do
    Tesla.client([
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{access_token}"}]}
    ])
  end

  @doc """
  Creates an unauthenticated client with basic rate limiting.
  """
  def new do
    Tesla.client([])
  end

  @doc """
  Makes a rate-limited GET request to the GitHub API.
  """
  def api_get(client, path, opts \\ []) do
    with :ok <- RateLimiter.check_rate_limit(),
         {:ok, response} <- Tesla.get(client, path, opts) do
      case response.status do
        200 ->
          {:ok, response.body}

        404 ->
          {:error, :not_found}

        403 ->
          handle_rate_limit_response(response)

        status when status >= 400 ->
          {:error, {:api_error, status, response.body}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes a rate-limited POST request to the GitHub API.
  """
  def api_post(client, path, body, opts \\ []) do
    with :ok <- RateLimiter.check_rate_limit(),
         {:ok, response} <- Tesla.post(client, path, body, opts) do
      case response.status do
        200..299 ->
          {:ok, response.body}

        403 ->
          handle_rate_limit_response(response)

        status when status >= 400 ->
          {:error, {:api_error, status, response.body}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches repository information by owner and name.
  """
  def get_repository(client, owner, repo) do
    api_get(client, "/repos/#{owner}/#{repo}")
  end

  @doc """
  Fetches repository issues with optional state filter.
  """
  def get_issues(client, owner, repo, opts \\ []) do
    state = Keyword.get(opts, :state, "all")
    per_page = Keyword.get(opts, :per_page, 100)

    api_get(client, "/repos/#{owner}/#{repo}/issues", query: [state: state, per_page: per_page])
  end

  @doc """
  Fetches repository pull requests.
  """
  def get_pull_requests(client, owner, repo, opts \\ []) do
    state = Keyword.get(opts, :state, "all")
    per_page = Keyword.get(opts, :per_page, 100)

    api_get(client, "/repos/#{owner}/#{repo}/pulls", query: [state: state, per_page: per_page])
  end

  @doc """
  Fetches commits for a repository.
  """
  def get_commits(client, owner, repo, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 100)
    since = Keyword.get(opts, :since)

    query_params = [per_page: per_page]
    query_params = if since, do: [{:since, since} | query_params], else: query_params

    api_get(client, "/repos/#{owner}/#{repo}/commits", query: query_params)
  end

  defp handle_rate_limit_response(response) do
    rate_limit_remaining = get_header_value(response.headers, "x-ratelimit-remaining")
    rate_limit_reset = get_header_value(response.headers, "x-ratelimit-reset")

    Logger.warning(
      "Rate limit exceeded. Remaining: #{rate_limit_remaining}, Reset: #{rate_limit_reset}"
    )

    case rate_limit_remaining do
      "0" ->
        reset_time = String.to_integer(rate_limit_reset)
        wait_seconds = reset_time - System.system_time(:second)
        {:error, {:rate_limit_exceeded, wait_seconds}}

      _ ->
        {:error, :rate_limit_secondary}
    end
  end

  defp get_header_value(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> "unknown"
    end
  end
end
