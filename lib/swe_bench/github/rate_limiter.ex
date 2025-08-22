defmodule SweBench.GitHub.RateLimiter do
  @moduledoc """
  Rate limiting mechanism for GitHub API requests with exponential backoff.

  Respects GitHub's API rate limits and implements intelligent backoff
  strategies to prevent API limit violations while maintaining performance.
  """

  use GenServer
  require Logger

  @default_config %{
    max_requests_per_hour: 4500,
    exponential_backoff_base: 2,
    max_backoff_seconds: 300,
    reset_buffer_seconds: 60
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a request can be made based on current rate limits.
  Returns :ok if request can proceed, {:error, reason} if rate limited.
  """
  def check_rate_limit do
    GenServer.call(__MODULE__, :check_rate_limit)
  end

  @doc """
  Records a successful API request for rate limit tracking.
  """
  def record_request do
    GenServer.cast(__MODULE__, :record_request)
  end

  @doc """
  Updates rate limit information from GitHub API response headers.
  """
  def update_rate_limit(remaining, reset_time) do
    GenServer.cast(__MODULE__, {:update_rate_limit, remaining, reset_time})
  end

  @doc """
  Gets current rate limit status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # GenServer implementation

  @impl GenServer
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))

    state = %{
      config: config,
      requests_this_hour: 0,
      hour_window_start: System.system_time(:second),
      github_remaining: nil,
      github_reset_time: nil,
      last_request_time: 0,
      backoff_factor: 1
    }

    Logger.debug("Rate limiter started with config: #{inspect(config)}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:check_rate_limit, _from, state) do
    current_time = System.system_time(:second)

    # Reset hour window if needed
    state = maybe_reset_hour_window(state, current_time)

    case can_make_request?(state, current_time) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      requests_this_hour: state.requests_this_hour,
      github_remaining: state.github_remaining,
      github_reset_time: state.github_reset_time,
      backoff_factor: state.backoff_factor,
      config: state.config
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast(:record_request, state) do
    current_time = System.system_time(:second)

    new_state = %{
      state
      | requests_this_hour: state.requests_this_hour + 1,
        last_request_time: current_time,
        backoff_factor: max(1, state.backoff_factor - 0.1)
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:update_rate_limit, remaining, reset_time}, state) do
    new_state = %{state | github_remaining: remaining, github_reset_time: reset_time}

    {:noreply, new_state}
  end

  # Private functions

  defp can_make_request?(state, current_time) do
    cond do
      # Check local rate limit
      state.requests_this_hour >= state.config.max_requests_per_hour ->
        wait_seconds = calculate_hour_window_reset(state, current_time)
        {:error, {:local_rate_limit, wait_seconds}, state}

      # Check GitHub rate limit if available
      state.github_remaining && state.github_remaining <= 10 ->
        wait_seconds = state.github_reset_time - current_time
        {:error, {:github_rate_limit, wait_seconds}, state}

      # Check backoff period
      backoff_wait_needed?(state, current_time) ->
        wait_seconds = calculate_backoff_wait(state, current_time)
        {:error, {:backoff_wait, wait_seconds}, state}

      true ->
        {:ok, state}
    end
  end

  defp maybe_reset_hour_window(state, current_time) do
    if current_time - state.hour_window_start >= 3600 do
      %{state | requests_this_hour: 0, hour_window_start: current_time}
    else
      state
    end
  end

  defp calculate_hour_window_reset(state, current_time) do
    max(0, 3600 - (current_time - state.hour_window_start))
  end

  defp backoff_wait_needed?(state, current_time) do
    state.backoff_factor > 1 &&
      current_time - state.last_request_time < calculate_backoff_seconds(state)
  end

  defp calculate_backoff_wait(state, current_time) do
    backoff_seconds = calculate_backoff_seconds(state)
    elapsed = current_time - state.last_request_time
    max(0, backoff_seconds - elapsed)
  end

  defp calculate_backoff_seconds(state) do
    base_seconds = :math.pow(state.config.exponential_backoff_base, state.backoff_factor)
    min(base_seconds, state.config.max_backoff_seconds)
  end
end
