defmodule SweBench.RepositoryMining.HexRateLimiter do
  @moduledoc """
  Rate limiter for Hex.pm API requests.

  Implements conservative rate limiting for Hex.pm to ensure reliable
  package discovery without overwhelming the service.
  """

  use GenServer
  require Logger

  # Conservative rate limiting: 10 requests per second
  @default_requests_per_second 10
  @request_window_ms 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Requests permission to make a Hex.pm API call.
  Returns :ok | {:error, :rate_limited}
  """
  def request_permission do
    GenServer.call(__MODULE__, :request_permission, 5000)
  end

  @doc """
  Gets current rate limiting statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(opts) do
    requests_per_second = Keyword.get(opts, :requests_per_second, @default_requests_per_second)

    state = %{
      requests_per_second: requests_per_second,
      window_start: current_timestamp(),
      requests_in_window: 0,
      total_requests: 0,
      rejected_requests: 0
    }

    Logger.info("Hex rate limiter started: #{requests_per_second} requests/second")
    {:ok, state}
  end

  @impl true
  def handle_call(:request_permission, _from, state) do
    current_time = current_timestamp()

    # Reset window if expired
    state =
      if current_time - state.window_start >= @request_window_ms do
        %{state | window_start: current_time, requests_in_window: 0}
      else
        state
      end

    # Check if request can be permitted
    if state.requests_in_window < state.requests_per_second do
      # Permit request
      updated_state = %{
        state
        | requests_in_window: state.requests_in_window + 1,
          total_requests: state.total_requests + 1
      }

      {:reply, :ok, updated_state}
    else
      # Rate limited
      updated_state = %{state | rejected_requests: state.rejected_requests + 1}
      {:reply, {:error, :rate_limited}, updated_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      requests_per_second: state.requests_per_second,
      total_requests: state.total_requests,
      rejected_requests: state.rejected_requests,
      current_window_usage: state.requests_in_window,
      rejection_rate: calculate_rejection_rate(state)
    }

    {:reply, stats, state}
  end

  defp current_timestamp, do: System.monotonic_time(:millisecond)

  defp calculate_rejection_rate(state) do
    total = state.total_requests + state.rejected_requests

    if total > 0 do
      state.rejected_requests / total
    else
      0.0
    end
  end
end
