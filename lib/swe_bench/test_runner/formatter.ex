defmodule SweBench.TestRunner.Formatter do
  @moduledoc """
  Simplified ExUnit formatter for capturing test results.

  This formatter captures test execution details without complex
  GenServer integration, focusing on reliability and simplicity.
  """

  use GenServer
  require Logger

  @doc """
  Starts the formatter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets captured results.
  """
  def get_results do
    GenServer.call(__MODULE__, :get_results)
  end

  @doc """
  Stops the formatter.
  """
  def stop do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  # GenServer Implementation

  @impl GenServer
  def init(_opts) do
    {:ok, %{tests: [], stats: %{total: 0, passed: 0, failed: 0}}}
  end

  @impl GenServer
  def handle_call(:get_results, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:test_result, test_info}, state) do
    new_tests = [test_info | state.tests]
    new_stats = update_stats(state.stats, test_info)
    new_state = %{state | tests: new_tests, stats: new_stats}
    {:noreply, new_state}
  end

  defp update_stats(stats, test_info) do
    case test_info.state do
      :passed -> %{stats | total: stats.total + 1, passed: stats.passed + 1}
      :failed -> %{stats | total: stats.total + 1, failed: stats.failed + 1}
      _ -> %{stats | total: stats.total + 1}
    end
  end
end
