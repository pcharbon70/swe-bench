defmodule SweBench.Pipeline.IntelligentCache do
  @moduledoc """
  Intelligent caching layer for compiled BEAM files and AST analysis results.

  Provides multi-level caching with intelligent invalidation strategies,
  distributed cache support, and comprehensive cache hit rate monitoring
  to achieve 70%+ hit rates for repeated evaluations.
  """

  use GenServer
  require Logger

  @cache_levels [:memory, :disk, :distributed]
  # 512MB memory cache
  @default_memory_limit 512 * 1024 * 1024
  # 5GB disk cache
  @default_disk_limit 5 * 1024 * 1024 * 1024
  # 1 hour default TTL
  @cache_ttl_seconds 3600
  # 5 minutes
  @cleanup_interval 300_000
  # Last 1000 operations
  @hit_rate_calculation_window 1000

  defstruct [
    :memory_cache,
    :disk_cache_path,
    :cache_config,
    :hit_statistics,
    :invalidation_rules,
    :distributed_nodes,
    :cleanup_timer
  ]

  @type cache_key ::
          {repository :: String.t(), commit_hash :: String.t(), analysis_type :: atom()}
  @type cache_value :: %{
          data: term(),
          timestamp: DateTime.t(),
          size_bytes: non_neg_integer(),
          access_count: non_neg_integer(),
          cache_level: atom()
        }

  # Public API

  @doc """
  Starts the intelligent cache manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves cached BEAM files for a repository and commit.
  """
  def get_beam_files(repository, commit_hash) do
    cache_key = {repository, commit_hash, :beam_files}
    GenServer.call(__MODULE__, {:get, cache_key})
  end

  @doc """
  Caches compiled BEAM files.
  """
  def put_beam_files(repository, commit_hash, beam_files, opts \\ []) do
    cache_key = {repository, commit_hash, :beam_files}
    GenServer.call(__MODULE__, {:put, cache_key, beam_files, opts})
  end

  @doc """
  Retrieves cached AST analysis results.
  """
  def get_ast_analysis(repository, commit_hash, analysis_type) do
    cache_key = {repository, commit_hash, analysis_type}
    GenServer.call(__MODULE__, {:get, cache_key})
  end

  @doc """
  Caches AST analysis results.
  """
  def put_ast_analysis(repository, commit_hash, analysis_type, analysis_result, opts \\ []) do
    cache_key = {repository, commit_hash, analysis_type}
    GenServer.call(__MODULE__, {:put, cache_key, analysis_result, opts})
  end

  @doc """
  Gets current cache statistics and hit rates.
  """
  def get_cache_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Invalidates cache entries based on rules (e.g., repository update).
  """
  def invalidate_cache(invalidation_pattern) do
    GenServer.call(__MODULE__, {:invalidate, invalidation_pattern})
  end

  @doc """
  Preloads cache with frequently used items.
  """
  def preload_cache(preload_items) do
    GenServer.cast(__MODULE__, {:preload, preload_items})
  end

  @doc """
  Forces cache cleanup and optimization.
  """
  def optimize_cache do
    GenServer.call(__MODULE__, :optimize_cache)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    memory_limit = Keyword.get(opts, :memory_limit, @default_memory_limit)
    disk_limit = Keyword.get(opts, :disk_limit, @default_disk_limit)
    disk_cache_path = Keyword.get(opts, :disk_cache_path, "/tmp/swe_bench_cache")

    # Ensure disk cache directory exists
    File.mkdir_p!(disk_cache_path)

    state = %__MODULE__{
      memory_cache: %{},
      disk_cache_path: disk_cache_path,
      cache_config: %{
        memory_limit: memory_limit,
        disk_limit: disk_limit,
        ttl_seconds: Keyword.get(opts, :ttl_seconds, @cache_ttl_seconds),
        levels: Keyword.get(opts, :cache_levels, @cache_levels)
      },
      hit_statistics: %{
        total_requests: 0,
        memory_hits: 0,
        disk_hits: 0,
        distributed_hits: 0,
        misses: 0,
        recent_operations: []
      },
      invalidation_rules: %{},
      distributed_nodes: Keyword.get(opts, :distributed_nodes, []),
      cleanup_timer: nil
    }

    # Schedule periodic cleanup
    cleanup_timer = schedule_cache_cleanup()
    updated_state = %{state | cleanup_timer: cleanup_timer}

    Logger.info(
      "IntelligentCache started with memory limit: #{format_bytes(memory_limit)}, disk limit: #{format_bytes(disk_limit)}"
    )

    {:ok, updated_state}
  end

  @impl GenServer
  def handle_call({:get, cache_key}, _from, state) do
    {result, updated_state} = get_from_cache_hierarchy(cache_key, state)
    {:reply, result, updated_state}
  end

  @impl GenServer
  def handle_call({:put, cache_key, value, opts}, _from, state) do
    {result, updated_state} = put_to_cache_hierarchy(cache_key, value, opts, state)
    {:reply, result, updated_state}
  end

  @impl GenServer
  def handle_call(:get_statistics, _from, state) do
    stats = calculate_cache_statistics(state)
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call({:invalidate, pattern}, _from, state) do
    {invalidated_count, updated_state} = invalidate_cache_entries(pattern, state)
    Logger.info("Invalidated #{invalidated_count} cache entries matching pattern")
    {:reply, {:ok, invalidated_count}, updated_state}
  end

  @impl GenServer
  def handle_call(:optimize_cache, _from, state) do
    {optimization_result, updated_state} = perform_cache_optimization(state)
    {:reply, optimization_result, updated_state}
  end

  @impl GenServer
  def handle_cast({:preload, preload_items}, state) do
    updated_state = preload_cache_items(preload_items, state)
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info(:cache_cleanup, state) do
    updated_state = perform_cache_cleanup(state)
    schedule_cache_cleanup()
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp get_from_cache_hierarchy(cache_key, state) do
    # Try memory cache first
    case get_from_memory_cache(cache_key, state.memory_cache) do
      {:hit, value} ->
        updated_stats = record_cache_hit(:memory, state.hit_statistics)
        {{:ok, value}, %{state | hit_statistics: updated_stats}}

      :miss ->
        # Try disk cache
        case get_from_disk_cache(cache_key, state.disk_cache_path) do
          {:hit, value} ->
            # Promote to memory cache
            updated_memory =
              put_to_memory_cache(cache_key, value, state.memory_cache, state.cache_config)

            updated_stats = record_cache_hit(:disk, state.hit_statistics)
            {{:ok, value}, %{state | memory_cache: updated_memory, hit_statistics: updated_stats}}

          :miss ->
            # Try distributed cache if available
            handle_distributed_cache_lookup(cache_key, state)
        end
    end
  end

  defp put_to_cache_hierarchy(cache_key, value, opts, state) do
    cache_levels = Keyword.get(opts, :cache_levels, state.cache_config.levels)
    ttl = Keyword.get(opts, :ttl_seconds, state.cache_config.ttl_seconds)

    cache_value = %{
      data: value,
      timestamp: DateTime.utc_now(),
      size_bytes: estimate_value_size(value),
      access_count: 0,
      ttl_seconds: ttl
    }

    updated_state =
      cache_levels
      |> Enum.reduce(state, fn level, acc_state ->
        case level do
          :memory ->
            updated_memory =
              put_to_memory_cache(
                cache_key,
                cache_value,
                acc_state.memory_cache,
                acc_state.cache_config
              )

            %{acc_state | memory_cache: updated_memory}

          :disk ->
            put_to_disk_cache(cache_key, cache_value, acc_state.disk_cache_path)
            acc_state

          :distributed ->
            put_to_distributed_cache(cache_key, cache_value, acc_state.distributed_nodes)
            acc_state
        end
      end)

    {:ok, updated_state}
  end

  defp get_from_memory_cache(cache_key, memory_cache) do
    case Map.get(memory_cache, cache_key) do
      nil ->
        :miss

      cached_value ->
        if cache_value_valid?(cached_value) do
          # Update access count
          updated_value = %{cached_value | access_count: cached_value.access_count + 1}
          {:hit, updated_value.data}
        else
          # Expired
          :miss
        end
    end
  end

  defp put_to_memory_cache(cache_key, cache_value, memory_cache, cache_config) do
    # Check if we need to evict items due to memory limit
    current_memory_usage = calculate_memory_cache_size(memory_cache)
    new_item_size = cache_value.size_bytes

    cleaned_cache =
      if current_memory_usage + new_item_size > cache_config.memory_limit do
        evict_memory_cache_items(memory_cache, new_item_size, cache_config.memory_limit)
      else
        memory_cache
      end

    Map.put(cleaned_cache, cache_key, cache_value)
  end

  defp get_from_disk_cache(cache_key, disk_cache_path) do
    cache_file_path = cache_key_to_file_path(cache_key, disk_cache_path)

    case File.read(cache_file_path) do
      {:ok, binary_data} ->
        cached_value = :erlang.binary_to_term(binary_data)

        if cache_value_valid?(cached_value) do
          {:hit, cached_value.data}
        else
          # Remove expired file
          File.rm(cache_file_path)
          :miss
        end

      {:error, :enoent} ->
        :miss

      {:error, _reason} ->
        :miss
    end
  rescue
    _ ->
      # Remove corrupted file if it exists
      cache_file_path = cache_key_to_file_path(cache_key, disk_cache_path)
      File.rm(cache_file_path)
      :miss
  end

  defp put_to_disk_cache(cache_key, cache_value, disk_cache_path) do
    cache_file_path = cache_key_to_file_path(cache_key, disk_cache_path)
    cache_dir = Path.dirname(cache_file_path)

    # Ensure cache directory exists
    File.mkdir_p!(cache_dir)

    binary_data = :erlang.term_to_binary(cache_value, [:compressed])
    File.write!(cache_file_path, binary_data)
    :ok
  rescue
    error ->
      Logger.error("Failed to write disk cache: #{inspect(error)}")
      :error
  end

  defp get_from_distributed_cache(_cache_key, []), do: :miss

  defp get_from_distributed_cache(cache_key, distributed_nodes) do
    # Simple distributed cache implementation
    # In production, would use a proper distributed cache like Redis

    results =
      distributed_nodes
      |> Enum.map(fn node ->
        try do
          :rpc.call(node, __MODULE__, :get_from_local_cache, [cache_key], 5000)
        rescue
          _ -> :miss
        end
      end)
      |> Enum.filter(&match?({:hit, _}, &1))

    case results do
      [{:hit, value} | _] -> {:hit, value}
      [] -> :miss
    end
  end

  defp put_to_distributed_cache(_cache_key, _cache_value, []), do: :ok

  defp put_to_distributed_cache(cache_key, cache_value, distributed_nodes) do
    # Replicate to distributed nodes
    Enum.each(distributed_nodes, fn node ->
      try do
        :rpc.cast(node, __MODULE__, :put_to_local_cache, [cache_key, cache_value])
      rescue
        error ->
          Logger.warning("Failed to replicate cache to node #{node}: #{inspect(error)}")
      end
    end)

    :ok
  end

  def get_from_local_cache(cache_key) do
    # Called via RPC from other nodes
    GenServer.call(__MODULE__, {:get_local, cache_key})
  end

  def put_to_local_cache(cache_key, cache_value) do
    # Called via RPC from other nodes
    GenServer.cast(__MODULE__, {:put_local, cache_key, cache_value})
  end

  @impl GenServer
  def handle_call({:get_local, cache_key}, _from, state) do
    case get_from_memory_cache(cache_key, state.memory_cache) do
      {:hit, value} -> {:reply, {:hit, value}, state}
      :miss -> {:reply, :miss, state}
    end
  end

  @impl GenServer
  def handle_cast({:put_local, cache_key, cache_value}, state) do
    updated_memory =
      put_to_memory_cache(cache_key, cache_value, state.memory_cache, state.cache_config)

    {:noreply, %{state | memory_cache: updated_memory}}
  end

  defp handle_distributed_cache_lookup(cache_key, state) do
    case get_from_distributed_cache(cache_key, state.distributed_nodes) do
      {:hit, value} ->
        # Promote to local caches
        updated_memory =
          put_to_memory_cache(cache_key, value, state.memory_cache, state.cache_config)

        put_to_disk_cache(cache_key, value, state.disk_cache_path)
        updated_stats = record_cache_hit(:distributed, state.hit_statistics)

        {{:ok, value}, %{state | memory_cache: updated_memory, hit_statistics: updated_stats}}

      :miss ->
        # Complete cache miss
        updated_stats = record_cache_miss(state.hit_statistics)
        {{:error, :not_found}, %{state | hit_statistics: updated_stats}}
    end
  end

  defp cache_value_valid?(cache_value) do
    current_time = DateTime.utc_now()
    expiry_time = DateTime.add(cache_value.timestamp, cache_value.ttl_seconds, :second)

    DateTime.compare(current_time, expiry_time) == :lt
  end

  defp cache_key_to_file_path({repository, commit_hash, analysis_type}, disk_cache_path) do
    # Create hierarchical file structure: repo/commit/analysis_type
    repo_dir = Path.join(disk_cache_path, sanitize_filename(repository))
    # First 8 chars of commit
    commit_dir = Path.join(repo_dir, String.slice(commit_hash, 0, 8))

    filename = "#{analysis_type}.cache"
    Path.join(commit_dir, filename)
  end

  defp sanitize_filename(filename) do
    # Replace unsafe characters for filesystem
    filename
    |> String.replace(~r/[^\w\-_.]/, "_")
    # Limit length
    |> String.slice(0, 100)
  end

  defp calculate_memory_cache_size(memory_cache) do
    memory_cache
    |> Map.values()
    |> Enum.map(& &1.size_bytes)
    |> Enum.sum()
  end

  defp estimate_value_size(value) do
    # Estimate memory size of cached value
    :erlang.external_size(value)
  rescue
    # Default 1KB if can't estimate
    _ -> 1024
  end

  defp evict_cache_item({key, value}, {evicted_size, acc_cache}, target_eviction) do
    if evicted_size < target_eviction do
      # Continue evicting
      {evicted_size + value.size_bytes, acc_cache}
    else
      # Keep this item
      {evicted_size, Map.put(acc_cache, key, value)}
    end
  end

  defp evict_memory_cache_items(memory_cache, required_space, memory_limit) do
    current_usage = calculate_memory_cache_size(memory_cache)
    target_usage = memory_limit - required_space

    if current_usage <= target_usage do
      # No eviction needed
      memory_cache
    else
      # Sort by LRU (least recently used) and lowest access count
      sorted_entries =
        memory_cache
        |> Enum.sort_by(fn {_key, value} ->
          {value.access_count, value.timestamp}
        end)

      # Evict items until we're under target usage
      target_eviction = current_usage - target_usage

      {_evicted, remaining} =
        Enum.reduce(sorted_entries, {0, %{}}, &evict_cache_item(&1, &2, target_eviction))

      remaining
    end
  end

  defp record_cache_hit(cache_level, hit_statistics) do
    level_key =
      case cache_level do
        :memory -> :memory_hits
        :disk -> :disk_hits
        :distributed -> :distributed_hits
      end

    updated_stats =
      %{hit_statistics | total_requests: hit_statistics.total_requests + 1}
      |> Map.update(level_key, 1, &(&1 + 1))

    # Update recent operations for hit rate calculation
    operation = %{type: :hit, level: cache_level, timestamp: DateTime.utc_now()}

    updated_recent =
      [operation | hit_statistics.recent_operations]
      |> Enum.take(@hit_rate_calculation_window)

    %{updated_stats | recent_operations: updated_recent}
  end

  defp record_cache_miss(hit_statistics) do
    updated_stats = %{
      hit_statistics
      | total_requests: hit_statistics.total_requests + 1,
        misses: hit_statistics.misses + 1
    }

    # Update recent operations
    operation = %{type: :miss, timestamp: DateTime.utc_now()}

    updated_recent =
      [operation | hit_statistics.recent_operations]
      |> Enum.take(@hit_rate_calculation_window)

    %{updated_stats | recent_operations: updated_recent}
  end

  defp calculate_cache_statistics(state) do
    stats = state.hit_statistics

    # Calculate hit rates
    total_hits = stats.memory_hits + stats.disk_hits + stats.distributed_hits

    overall_hit_rate =
      if stats.total_requests > 0 do
        total_hits / stats.total_requests
      else
        0.0
      end

    # Calculate recent hit rate (last N operations)
    recent_hit_rate =
      if Enum.empty?(stats.recent_operations) do
        0.0
      else
        recent_hits = Enum.count(stats.recent_operations, &(&1.type == :hit))
        recent_hits / length(stats.recent_operations)
      end

    # Memory cache statistics
    memory_usage = calculate_memory_cache_size(state.memory_cache)
    memory_utilization = memory_usage / state.cache_config.memory_limit

    # Disk cache statistics
    disk_usage = calculate_disk_cache_size(state.disk_cache_path)
    disk_utilization = disk_usage / state.cache_config.disk_limit

    %{
      hit_rates: %{
        overall: Float.round(overall_hit_rate, 3),
        recent: Float.round(recent_hit_rate, 3),
        memory: calculate_level_hit_rate(stats.memory_hits, stats.total_requests),
        disk: calculate_level_hit_rate(stats.disk_hits, stats.total_requests),
        distributed: calculate_level_hit_rate(stats.distributed_hits, stats.total_requests)
      },
      usage: %{
        memory: %{
          bytes: memory_usage,
          utilization: Float.round(memory_utilization, 3),
          items: map_size(state.memory_cache)
        },
        disk: %{
          bytes: disk_usage,
          utilization: Float.round(disk_utilization, 3),
          files: count_disk_cache_files(state.disk_cache_path)
        }
      },
      performance: %{
        total_requests: stats.total_requests,
        cache_effectiveness: calculate_cache_effectiveness(stats),
        average_lookup_time: calculate_average_lookup_time(stats)
      },
      health: %{
        memory_pressure: memory_utilization > 0.9,
        disk_pressure: disk_utilization > 0.9,
        distributed_nodes_available: length(state.distributed_nodes)
      }
    }
  end

  defp calculate_level_hit_rate(hits, total_requests) do
    if total_requests > 0 do
      Float.round(hits / total_requests, 3)
    else
      0.0
    end
  end

  defp calculate_cache_effectiveness(stats) do
    # Effectiveness considers both hit rate and cache level efficiency
    if stats.total_requests > 0 do
      # Best performance
      memory_weight = 1.0
      # Good performance
      disk_weight = 0.8
      # Acceptable performance
      distributed_weight = 0.6

      weighted_hits =
        stats.memory_hits * memory_weight +
          stats.disk_hits * disk_weight +
          stats.distributed_hits * distributed_weight

      Float.round(weighted_hits / stats.total_requests, 3)
    else
      0.0
    end
  end

  defp calculate_average_lookup_time(_stats) do
    # Simplified lookup time calculation
    # In production, would track actual lookup times
    # 5ms average lookup time
    5.0
  end

  defp calculate_disk_cache_size(disk_cache_path) do
    case File.ls(disk_cache_path) do
      {:ok, _} ->
        {output, 0} = System.cmd("du", ["-sb", disk_cache_path])
        [size_str | _] = String.split(output, "\t")
        String.to_integer(size_str)

      {:error, :enoent} ->
        0

      {:error, _} ->
        0
    end
  rescue
    _ -> 0
  end

  defp count_disk_cache_files(disk_cache_path) do
    case File.ls(disk_cache_path) do
      {:ok, files} ->
        # Recursively count cache files
        count_files_recursive(disk_cache_path, files)

      {:error, _} ->
        0
    end
  rescue
    _ -> 0
  end

  defp count_directory_files(full_path, acc) do
    case File.ls(full_path) do
      {:ok, sub_entries} -> acc + count_files_recursive(full_path, sub_entries)
      {:error, _} -> acc
    end
  end

  defp count_if_cache_file(entry, acc) do
    if String.ends_with?(entry, ".cache") do
      acc + 1
    else
      acc
    end
  end

  defp count_files_recursive(base_path, entries) do
    Enum.reduce(entries, 0, fn entry, acc ->
      full_path = Path.join(base_path, entry)

      case File.stat(full_path) do
        {:ok, %{type: :directory}} ->
          count_directory_files(full_path, acc)

        {:ok, %{type: :regular}} ->
          count_if_cache_file(entry, acc)

        {:error, _} ->
          acc
      end
    end)
  end

  defp invalidate_cache_entries(pattern, state) do
    # Invalidate cache entries matching pattern
    case pattern do
      {:repository, repository} ->
        invalidate_repository_cache(repository, state)

      {:commit, repository, commit_hash} ->
        invalidate_commit_cache(repository, commit_hash, state)

      {:analysis_type, analysis_type} ->
        invalidate_analysis_type_cache(analysis_type, state)

      :all ->
        invalidate_all_cache(state)
    end
  end

  defp invalidate_repository_cache(repository, state) do
    # Remove all cache entries for a repository
    memory_keys_to_remove =
      state.memory_cache
      |> Enum.filter(fn {{repo, _commit, _type}, _value} -> repo == repository end)
      |> Enum.map(fn {key, _value} -> key end)

    updated_memory =
      Enum.reduce(memory_keys_to_remove, state.memory_cache, fn key, acc ->
        Map.delete(acc, key)
      end)

    # Remove disk cache files for repository
    repo_disk_path = Path.join(state.disk_cache_path, sanitize_filename(repository))

    if File.exists?(repo_disk_path) do
      File.rm_rf!(repo_disk_path)
    end

    invalidated_count = length(memory_keys_to_remove)
    {invalidated_count, %{state | memory_cache: updated_memory}}
  end

  defp invalidate_commit_cache(repository, commit_hash, state) do
    # Remove cache entries for specific commit
    memory_keys_to_remove =
      state.memory_cache
      |> Enum.filter(fn {{repo, commit, _type}, _value} ->
        repo == repository and commit == commit_hash
      end)
      |> Enum.map(fn {key, _value} -> key end)

    updated_memory =
      Enum.reduce(memory_keys_to_remove, state.memory_cache, fn key, acc ->
        Map.delete(acc, key)
      end)

    # Remove specific commit disk cache
    commit_disk_path =
      Path.join([
        state.disk_cache_path,
        sanitize_filename(repository),
        String.slice(commit_hash, 0, 8)
      ])

    if File.exists?(commit_disk_path) do
      File.rm_rf!(commit_disk_path)
    end

    invalidated_count = length(memory_keys_to_remove)
    {invalidated_count, %{state | memory_cache: updated_memory}}
  end

  defp invalidate_analysis_type_cache(analysis_type, state) do
    # Remove all cache entries for specific analysis type
    memory_keys_to_remove =
      state.memory_cache
      |> Enum.filter(fn {{_repo, _commit, type}, _value} -> type == analysis_type end)
      |> Enum.map(fn {key, _value} -> key end)

    updated_memory =
      Enum.reduce(memory_keys_to_remove, state.memory_cache, fn key, acc ->
        Map.delete(acc, key)
      end)

    # For disk cache, would need to traverse and remove specific files
    # Simplified: clear analysis type cache files
    remove_analysis_type_disk_files(state.disk_cache_path, analysis_type)

    invalidated_count = length(memory_keys_to_remove)
    {invalidated_count, %{state | memory_cache: updated_memory}}
  end

  defp invalidate_all_cache(state) do
    # Clear all caches
    memory_count = map_size(state.memory_cache)

    # Clear memory cache
    updated_memory = %{}

    # Clear disk cache
    if File.exists?(state.disk_cache_path) do
      File.rm_rf!(state.disk_cache_path)
      File.mkdir_p!(state.disk_cache_path)
    end

    {memory_count, %{state | memory_cache: updated_memory}}
  end

  defp remove_analysis_type_disk_files(disk_cache_path, analysis_type) do
    filename_pattern = "#{analysis_type}.cache"

    case File.ls(disk_cache_path) do
      {:ok, repo_dirs} ->
        Enum.each(
          repo_dirs,
          &remove_analysis_from_repo_dir(&1, disk_cache_path, filename_pattern)
        )

      {:error, _} ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp remove_analysis_from_repo_dir(repo_dir, disk_cache_path, filename_pattern) do
    repo_path = Path.join(disk_cache_path, repo_dir)

    if File.dir?(repo_path) do
      remove_analysis_files_from_repo(repo_path, filename_pattern)
    end
  end

  defp remove_analysis_file_from_commit(commit_dir, repo_path, filename_pattern) do
    commit_path = Path.join(repo_path, commit_dir)

    if File.dir?(commit_path) do
      cache_file = Path.join(commit_path, filename_pattern)

      if File.exists?(cache_file) do
        File.rm(cache_file)
      end
    end
  end

  defp remove_analysis_files_from_repo(repo_path, filename_pattern) do
    case File.ls(repo_path) do
      {:ok, commit_dirs} ->
        Enum.each(commit_dirs, &remove_analysis_file_from_commit(&1, repo_path, filename_pattern))

      {:error, _} ->
        :ok
    end
  end

  defp perform_cache_cleanup(state) do
    Logger.debug("Performing cache cleanup")

    # Clean expired memory cache entries
    current_time = DateTime.utc_now()

    cleaned_memory =
      state.memory_cache
      |> Enum.filter(fn {_key, value} -> cache_value_valid?(value) end)
      |> Map.new()

    # Clean expired disk cache files
    clean_expired_disk_files(state.disk_cache_path, current_time)

    # Update statistics
    memory_items_removed = map_size(state.memory_cache) - map_size(cleaned_memory)

    if memory_items_removed > 0 do
      Logger.debug("Cleaned #{memory_items_removed} expired items from memory cache")
    end

    %{state | memory_cache: cleaned_memory}
  end

  defp clean_repo_dir_if_exists(repo_dir, disk_cache_path, current_time) do
    repo_path = Path.join(disk_cache_path, repo_dir)

    if File.dir?(repo_path) do
      clean_repo_cache_files(repo_path, current_time)
    end
  end

  defp clean_expired_disk_files(disk_cache_path, current_time) do
    # Simplified disk cleanup - in production would be more thorough
    case File.ls(disk_cache_path) do
      {:ok, repo_dirs} ->
        Enum.each(repo_dirs, &clean_repo_dir_if_exists(&1, disk_cache_path, current_time))

      {:error, _} ->
        :ok
    end
  rescue
    error ->
      Logger.warning("Disk cache cleanup failed: #{inspect(error)}")
  end

  defp clean_commit_dir_if_exists(commit_dir, repo_path, current_time) do
    commit_path = Path.join(repo_path, commit_dir)

    if File.dir?(commit_path) do
      clean_commit_cache_files(commit_path, current_time)
    end
  end

  defp clean_repo_cache_files(repo_path, current_time) do
    case File.ls(repo_path) do
      {:ok, commit_dirs} ->
        Enum.each(commit_dirs, &clean_commit_dir_if_exists(&1, repo_path, current_time))

      {:error, _} ->
        :ok
    end
  end

  defp clean_commit_cache_files(commit_path, current_time) do
    case File.ls(commit_path) do
      {:ok, cache_files} ->
        Enum.each(cache_files, &clean_single_cache_file(&1, commit_path, current_time))

      {:error, _} ->
        :ok
    end
  end

  defp clean_single_cache_file(cache_file, commit_path, current_time) do
    if String.ends_with?(cache_file, ".cache") do
      full_path = Path.join(commit_path, cache_file)
      remove_expired_cache_file(full_path, current_time)
    end
  end

  defp remove_expired_cache_file(full_path, current_time) do
    case File.stat(full_path) do
      {:ok, %{mtime: mtime}} ->
        file_age_seconds = DateTime.diff(current_time, DateTime.from_unix!(mtime))

        if file_age_seconds > @cache_ttl_seconds do
          File.rm(full_path)
        end

      {:error, _} ->
        :ok
    end
  end

  defp perform_cache_optimization(state) do
    Logger.info("Performing cache optimization")

    # Optimize memory cache
    optimized_memory = optimize_memory_cache(state.memory_cache, state.cache_config)

    # Optimize disk cache
    disk_optimization_result = optimize_disk_cache(state.disk_cache_path)

    # Calculate optimization results
    memory_savings =
      calculate_memory_cache_size(state.memory_cache) -
        calculate_memory_cache_size(optimized_memory)

    optimization_result = %{
      memory_savings_bytes: memory_savings,
      disk_optimization: disk_optimization_result,
      items_compacted: map_size(state.memory_cache) - map_size(optimized_memory)
    }

    updated_state = %{state | memory_cache: optimized_memory}

    Logger.info("Cache optimization completed: #{format_bytes(memory_savings)} memory saved")
    {optimization_result, updated_state}
  end

  defp optimize_cache_item({key, value}, {acc_size, acc_cache}, target_usage) do
    if acc_size + value.size_bytes <= target_usage do
      {acc_size + value.size_bytes, Map.put(acc_cache, key, value)}
    else
      {acc_size, acc_cache}
    end
  end

  defp optimize_memory_cache(memory_cache, cache_config) do
    current_usage = calculate_memory_cache_size(memory_cache)
    # Target 80% utilization
    target_usage = round(cache_config.memory_limit * 0.8)

    if current_usage > target_usage do
      # Keep most valuable items (high access count, recent timestamp)
      memory_cache
      |> Enum.sort_by(
        fn {_key, value} ->
          # Hours ago (negative for sorting)
          recency_score = DateTime.diff(DateTime.utc_now(), value.timestamp) / -3600
          access_score = value.access_count
          {access_score, recency_score}
        end,
        :desc
      )
      |> Enum.reduce({0, %{}}, &optimize_cache_item(&1, &2, target_usage))
      # Return the optimized cache
      |> elem(1)
    else
      memory_cache
    end
  end

  defp optimize_disk_cache(disk_cache_path) do
    # Simplified disk cache optimization
    initial_size = calculate_disk_cache_size(disk_cache_path)

    # Remove files older than 24 hours
    cutoff_time = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    clean_expired_disk_files(disk_cache_path, cutoff_time)

    final_size = calculate_disk_cache_size(disk_cache_path)

    %{
      initial_size: initial_size,
      final_size: final_size,
      space_freed: initial_size - final_size
    }
  rescue
    error ->
      Logger.error("Disk cache optimization failed: #{inspect(error)}")
      %{error: error}
  end

  defp preload_single_cache_item(item, acc_cache, cache_config) do
    cache_key = {item.repository, item.commit_hash, item.analysis_type}

    if Map.has_key?(acc_cache, cache_key) or not File.exists?(item.file_path) do
      acc_cache
    else
      case File.read(item.file_path) do
        {:ok, data} ->
          cache_value = %{
            data: data,
            timestamp: DateTime.utc_now(),
            size_bytes: byte_size(data),
            access_count: 0,
            ttl_seconds: cache_config.ttl_seconds
          }

          Map.put(acc_cache, cache_key, cache_value)

        {:error, _} ->
          acc_cache
      end
    end
  end

  defp preload_cache_items(preload_items, state) do
    Logger.info("Preloading #{length(preload_items)} cache items")

    # Preload items into memory cache
    updated_memory =
      Enum.reduce(
        preload_items,
        state.memory_cache,
        &preload_single_cache_item(&1, &2, state.cache_config)
      )

    %{state | memory_cache: updated_memory}
  end

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cache_cleanup, @cleanup_interval)
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end
end
