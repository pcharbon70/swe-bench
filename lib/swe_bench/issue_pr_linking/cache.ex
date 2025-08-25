defmodule SweBench.IssuePrLinking.Cache do
  @moduledoc """
  Caching system for Issue-PR correlation data.

  Provides multi-layer caching for API responses, correlation results,
  and relationship analysis to improve performance and reduce API usage.
  """

  use GenServer
  require Logger

  @cache_name :issue_pr_correlation_cache
  @default_ttl_seconds 3600  # 1 hour

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached correlation results for a repository.
  """
  def get_repository_correlations(repository_id) do
    GenServer.call(__MODULE__, {:get, {:correlations, repository_id}})
  end

  @doc """
  Caches correlation results for a repository.
  """
  def cache_repository_correlations(repository_id, correlations, ttl \\ @default_ttl_seconds) do
    GenServer.cast(__MODULE__, {:put, {:correlations, repository_id}, correlations, ttl})
  end

  @doc """
  Gets cached issues for a repository.
  """
  def get_repository_issues(repository_id) do
    GenServer.call(__MODULE__, {:get, {:issues, repository_id}})
  end

  @doc """
  Caches issues for a repository.
  """
  def cache_repository_issues(repository_id, issues, ttl \\ @default_ttl_seconds) do
    GenServer.cast(__MODULE__, {:put, {:issues, repository_id}, issues, ttl})
  end

  @doc """
  Gets cached pull requests for a repository.
  """
  def get_repository_prs(repository_id) do
    GenServer.call(__MODULE__, {:get, {:prs, repository_id}})
  end

  @doc """
  Caches pull requests for a repository.
  """
  def cache_repository_prs(repository_id, prs, ttl \\ @default_ttl_seconds) do
    GenServer.cast(__MODULE__, {:put, {:prs, repository_id}, prs, ttl})
  end

  @doc """
  Gets cache statistics and performance metrics.
  """
  def get_cache_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    # Initialize cache with Cachex
    {:ok, _pid} = Cachex.start_link(@cache_name, [
      limit: 1000,           # Max 1000 entries
      expiration: Cachex.Expiration.expiration(
        default: :timer.seconds(@default_ttl_seconds),
        interval: :timer.seconds(60)  # Cleanup every minute
      )
    ])

    state = %{
      cache_hits: 0,
      cache_misses: 0,
      total_gets: 0,
      total_puts: 0
    }

    Logger.info("Issue-PR correlation cache started")
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
    cache_info = Cachex.stats(@cache_name)

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