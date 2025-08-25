defmodule SweBench.RepositoryMining.GitHubRateLimiter do
  @moduledoc """
  Rate limiter for GitHub API requests.

  Implements sophisticated rate limiting for GitHub API with different limits
  for search vs. standard API calls, including secondary rate limit handling.
  """

  use GenServer
  require Logger

  # GitHub API limits (authenticated)
  @github_api_requests_per_hour 5000
  @github_search_requests_per_minute 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Requests permission to make a GitHub API call.
  """
  def request_permission(api_type \\ :standard) do
    GenServer.call(__MODULE__, {:request_permission, api_type}, 5000)
  end

  @doc """
  Gets current rate limiting statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Updates rate limits based on GitHub API response headers.
  """
  def update_from_headers(headers) do
    GenServer.cast(__MODULE__, {:update_from_headers, headers})
  end

  @impl true
  def init(_opts) do
    state = %{
      # Standard API limits (per hour)
      api_window_start: current_timestamp(),
      api_requests_in_window: 0,
      api_requests_per_hour: @github_api_requests_per_hour,

      # Search API limits (per minute)
      search_window_start: current_timestamp(),
      search_requests_in_window: 0,
      search_requests_per_minute: @github_search_requests_per_minute,

      # Statistics
      total_api_requests: 0,
      total_search_requests: 0,
      rejected_requests: 0,

      # Rate limit headers from GitHub
      remaining_api_requests: @github_api_requests_per_hour,
      remaining_search_requests: @github_search_requests_per_minute,
      reset_time: nil
    }

    Logger.info("GitHub rate limiter started")
    {:ok, state}
  end

  @impl true
  def handle_call({:request_permission, api_type}, _from, state) do
    case api_type do
      :standard ->
        handle_api_request(state)

      :search ->
        handle_search_request(state)
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      api_requests_per_hour: state.api_requests_per_hour,
      search_requests_per_minute: state.search_requests_per_minute,
      total_api_requests: state.total_api_requests,
      total_search_requests: state.total_search_requests,
      rejected_requests: state.rejected_requests,
      remaining_api_requests: state.remaining_api_requests,
      remaining_search_requests: state.remaining_search_requests,
      rejection_rate: calculate_rejection_rate(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:update_from_headers, headers}, state) do
    updated_state =
      state
      |> update_remaining_from_headers(headers, "x-ratelimit-remaining", :remaining_api_requests)
      |> update_remaining_from_headers(
        headers,
        "x-ratelimit-search-remaining",
        :remaining_search_requests
      )

    {:noreply, updated_state}
  end

  # Private helper functions

  defp handle_api_request(state) do
    current_time = current_timestamp()

    # Reset window if expired (1 hour = 3,600,000 ms)
    state =
      if current_time - state.api_window_start >= 3_600_000 do
        %{state | api_window_start: current_time, api_requests_in_window: 0}
      else
        state
      end

    # Check if request can be permitted
    # Keep buffer of 10 requests
    if state.api_requests_in_window < state.api_requests_per_hour and
         state.remaining_api_requests > 10 do
      updated_state = %{
        state
        | api_requests_in_window: state.api_requests_in_window + 1,
          total_api_requests: state.total_api_requests + 1,
          remaining_api_requests: max(0, state.remaining_api_requests - 1)
      }

      {:reply, :ok, updated_state}
    else
      updated_state = %{state | rejected_requests: state.rejected_requests + 1}
      {:reply, {:error, :rate_limited}, updated_state}
    end
  end

  defp handle_search_request(state) do
    current_time = current_timestamp()

    # Reset window if expired (1 minute = 60,000 ms)
    state =
      if current_time - state.search_window_start >= 60_000 do
        %{state | search_window_start: current_time, search_requests_in_window: 0}
      else
        state
      end

    # Check if search request can be permitted
    # Keep buffer of 2 requests
    if state.search_requests_in_window < state.search_requests_per_minute and
         state.remaining_search_requests > 2 do
      updated_state = %{
        state
        | search_requests_in_window: state.search_requests_in_window + 1,
          total_search_requests: state.total_search_requests + 1,
          remaining_search_requests: max(0, state.remaining_search_requests - 1)
      }

      {:reply, :ok, updated_state}
    else
      updated_state = %{state | rejected_requests: state.rejected_requests + 1}
      {:reply, {:error, :rate_limited}, updated_state}
    end
  end

  defp update_remaining_from_headers(state, headers, header_key, state_key) do
    case List.keyfind(headers, header_key, 0) do
      {^header_key, value} ->
        case Integer.parse(value) do
          {remaining, _} -> Map.put(state, state_key, remaining)
          _ -> state
        end

      nil ->
        state
    end
  end

  defp calculate_rejection_rate(state) do
    total = state.total_api_requests + state.total_search_requests + state.rejected_requests

    if total > 0 do
      state.rejected_requests / total
    else
      0.0
    end
  end

  defp current_timestamp, do: System.monotonic_time(:millisecond)
end
