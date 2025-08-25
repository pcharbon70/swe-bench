defmodule SweBench.TestTransition.ValidationCache do
  @moduledoc """
  Caching system for test transition validation results.

  Provides intelligent caching for patch applications, test executions,
  and validation results to improve performance and reduce resource usage.
  """

  use GenServer
  require Logger

  @cache_name :test_transition_validation_cache
  # 2 hours
  @default_ttl_seconds 7200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached validation result by patch hash.
  """
  def get_validation_result(patch_hash) do
    GenServer.call(__MODULE__, {:get, {:validation, patch_hash}})
  end

  @doc """
  Caches validation result with patch hash key.
  """
  def cache_validation_result(patch_hash, validation_result, ttl \\ @default_ttl_seconds) do
    GenServer.cast(__MODULE__, {:put, {:validation, patch_hash}, validation_result, ttl})
  end

  @doc """
  Gets cached test execution results.
  """
  def get_test_execution_result(repo_commit_hash) do
    GenServer.call(__MODULE__, {:get, {:test_execution, repo_commit_hash}})
  end

  @doc """
  Caches test execution results.
  """
  def cache_test_execution_result(repo_commit_hash, test_results, ttl \\ @default_ttl_seconds) do
    GenServer.cast(__MODULE__, {:put, {:test_execution, repo_commit_hash}, test_results, ttl})
  end

  @doc """
  Gets cache performance statistics.
  """
  def get_cache_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    # Initialize cache with Cachex
    {:ok, _pid} =
      Cachex.start_link(@cache_name,
        # Max 500 entries (validations are expensive)
        limit: 500,
        # Default TTL in milliseconds
        default_ttl: @default_ttl_seconds * 1000
      )

    state = %{
      cache_hits: 0,
      cache_misses: 0,
      total_gets: 0,
      total_puts: 0
    }

    Logger.info("Test transition validation cache started")
    {:ok, state}
  end

  @impl true
  def handle_call({:get, cache_key}, _from, state) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss
        updated_state = %{
          state
          | cache_misses: state.cache_misses + 1,
            total_gets: state.total_gets + 1
        }

        {:reply, {:error, :not_found}, updated_state}

      {:ok, cached_value} ->
        # Cache hit
        updated_state = %{
          state
          | cache_hits: state.cache_hits + 1,
            total_gets: state.total_gets + 1
        }

        {:reply, {:ok, cached_value}, updated_state}

      {:error, reason} ->
        Logger.warning("Cache get error for #{inspect(cache_key)}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      cache_hits: state.cache_hits,
      cache_misses: state.cache_misses,
      hit_rate: calculate_hit_rate(state),
      total_gets: state.total_gets,
      total_puts: state.total_puts,
      cache_size: get_cache_size(),
      memory_usage: get_cache_memory_usage()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:put, cache_key, value, ttl}, state) do
    case Cachex.put(@cache_name, cache_key, value, ttl: :timer.seconds(ttl)) do
      {:ok, true} ->
        updated_state = %{state | total_puts: state.total_puts + 1}
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.warning("Cache put error for #{inspect(cache_key)}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private helper functions

  defp calculate_hit_rate(state) do
    if state.total_gets > 0 do
      state.cache_hits / state.total_gets
    else
      0.0
    end
  end

  defp get_cache_size do
    case Cachex.size(@cache_name) do
      {:ok, size} -> size
      _ -> 0
    end
  end

  defp get_cache_memory_usage do
    case Cachex.stats(@cache_name) do
      {:ok, stats} -> Map.get(stats, :memory, 0)
      _ -> 0
    end
  end
end
