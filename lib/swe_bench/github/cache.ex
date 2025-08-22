defmodule SweBench.GitHub.Cache do
  @moduledoc """
  Multi-level caching system for GitHub API responses.

  Provides memory and persistent caching to reduce redundant API calls
  and improve performance while respecting cache invalidation needs.
  """

  require Logger

  @cache_name :github_api_cache
  @default_ttl :timer.hours(1)

  @doc """
  Starts the cache process.
  """
  def start_link(opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    Cachex.start_link(@cache_name,
      expiration: [
        default: ttl,
        interval: :timer.minutes(5)
      ],
      limit: [
        size: 10_000,
        policy: :lru
      ]
    )
  end

  @doc """
  Retrieves cached response for a given key.
  """
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stores response in cache with optional TTL.
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    case Cachex.put(@cache_name, key, value, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves cached value or executes function and caches result.
  """
  def fetch(key, fun, opts \\ []) when is_function(fun, 0) do
    case get(key) do
      {:ok, value} ->
        Logger.debug("Cache hit for key: #{key}")
        {:ok, value}

      {:error, :not_found} ->
        Logger.debug("Cache miss for key: #{key}, executing function")

        case fun.() do
          {:ok, value} ->
            put(key, value, opts)
            {:ok, value}

          {:error, reason} = error ->
            Logger.debug("Function execution failed for key #{key}: #{inspect(reason)}")
            error
        end

      {:error, reason} = error ->
        Logger.warning("Cache error for key #{key}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Invalidates cache entry for given key.
  """
  def invalidate(key) do
    case Cachex.del(@cache_name, key) do
      {:ok, true} -> :ok
      # Key didn't exist
      {:ok, false} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Invalidates all cache entries matching a pattern.
  """
  def invalidate_pattern(pattern) when is_binary(pattern) do
    case Cachex.stream(@cache_name, :key) do
      {:ok, stream} ->
        stream
        |> Stream.filter(&String.contains?(&1, pattern))
        |> Enum.each(&invalidate/1)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears all cached entries.
  """
  def clear do
    case Cachex.clear(@cache_name) do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Logger.info("Cleared #{count} cache entries")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    case Cachex.stats(@cache_name) do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates a cache key for GitHub API requests.
  """
  def cache_key(method, path, query \\ []) do
    base_key = "#{method}:#{path}"

    case query do
      [] ->
        base_key

      query_params ->
        query_string = URI.encode_query(query_params)
        "#{base_key}?#{query_string}"
    end
  end

  @doc """
  Generates cache key for repository-specific data.
  """
  def repository_cache_key(owner, repo, data_type, opts \\ []) do
    base_key = "repo:#{owner}/#{repo}:#{data_type}"

    case opts do
      [] ->
        base_key

      opts_params ->
        opts_string = opts_params |> Enum.sort() |> inspect()

        :crypto.hash(:md5, opts_string)
        |> Base.encode16(case: :lower)
        |> then(&"#{base_key}:#{&1}")
    end
  end
end
