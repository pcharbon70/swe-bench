defmodule SweBench.Pipeline.BatchOptimizer do
  @moduledoc """
  Optimizes task batching and repository grouping for parallel evaluation.

  Implements intelligent task distribution based on repository affinity,
  shared dependencies, and container reuse patterns to maximize throughput
  and resource efficiency.
  """

  require Logger

  @default_batch_size 10
  @max_batch_size 50
  @min_batch_size 3
  @affinity_threshold 0.7

  @doc """
  Creates optimized task batches based on repository affinity and resource efficiency.

  ## Parameters
    - tasks: List of evaluation tasks to batch
    - opts: Optimization options (batch_size, affinity_threshold, etc.)

  ## Returns
    - {:ok, batches} where batches is a list of optimized task groups
    - {:error, reason} if batching fails

  ## Examples
      iex> tasks = [%{repo: "elixir", type: :pattern_analysis}, %{repo: "phoenix", type: :otp_validation}]
      iex> BatchOptimizer.optimize_batches(tasks)
      {:ok, [%{tasks: [...], affinity_score: 0.8, estimated_time: 120}]}
  """
  def optimize_batches(tasks, opts \\ []) do
    Logger.debug("Optimizing #{length(tasks)} tasks into efficient batches")

    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    affinity_threshold = Keyword.get(opts, :affinity_threshold, @affinity_threshold)

    with {:ok, repository_affinities} <- calculate_repository_affinities(tasks),
         {:ok, dependency_groups} <- group_by_shared_dependencies(tasks),
         {:ok, optimized_groups} <-
           create_optimized_groups(tasks, repository_affinities, dependency_groups, batch_size) do
      batches =
        optimized_groups
        |> Enum.map(&add_batch_metadata/1)
        |> Enum.filter(&(batch_quality_score(&1) >= affinity_threshold))
        |> balance_batch_sizes(batch_size)

      Logger.info("Created #{length(batches)} optimized batches from #{length(tasks)} tasks")
      {:ok, batches}
    else
      {:error, reason} ->
        Logger.error("Failed to optimize batches: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculates repository affinity scores based on shared characteristics.

  Repository affinity represents how well repositories work together in the same
  batch, considering factors like compilation dependencies, test patterns, and
  container reuse potential.
  """
  def calculate_repository_affinities(tasks) do
    repositories = tasks |> Enum.map(& &1.repository) |> Enum.uniq()

    affinity_matrix =
      repositories
      |> Enum.map(fn repo1 ->
        affinities =
          repositories
          |> Enum.map(fn repo2 ->
            score = calculate_repo_pair_affinity(repo1, repo2)
            {repo2, score}
          end)
          |> Map.new()

        {repo1, affinities}
      end)
      |> Map.new()

    {:ok, affinity_matrix}
  end

  @doc """
  Groups tasks by shared dependencies to optimize container reuse.
  """
  def group_by_shared_dependencies(tasks) do
    dependency_groups =
      tasks
      |> Enum.group_by(&get_task_dependencies/1)
      |> Enum.map(fn {deps, group_tasks} ->
        %{
          dependencies: deps,
          tasks: group_tasks,
          container_reuse_score: calculate_container_reuse_score(deps)
        }
      end)

    {:ok, dependency_groups}
  end

  @doc """
  Handles priority task insertion into existing batches.
  """
  def insert_priority_task(batches, priority_task, opts \\ []) do
    max_batch_size = Keyword.get(opts, :max_batch_size, @max_batch_size)

    # Find best batch for priority task based on affinity
    {best_batch_index, best_affinity} =
      batches
      |> Enum.with_index()
      |> Enum.map(fn {batch, index} ->
        affinity = calculate_task_batch_affinity(priority_task, batch)
        {index, affinity}
      end)
      |> Enum.max_by(fn {_index, affinity} -> affinity end)

    if best_affinity > @affinity_threshold and
         length(Enum.at(batches, best_batch_index).tasks) < max_batch_size do
      # Insert into existing batch
      updated_batch =
        Enum.at(batches, best_batch_index)
        |> Map.update(:tasks, [], &[priority_task | &1])
        |> recalculate_batch_metadata()

      updated_batches = List.replace_at(batches, best_batch_index, updated_batch)
      {:ok, updated_batches}
    else
      # Create new priority batch
      priority_batch = %{
        tasks: [priority_task],
        priority: :high,
        affinity_score: 1.0,
        estimated_time: estimate_task_time(priority_task)
      }

      {:ok, [priority_batch | batches]}
    end
  end

  # Private implementation functions

  defp calculate_repo_pair_affinity(repo1, repo2) do
    cond do
      repo1 == repo2 -> 1.0
      same_ecosystem?(repo1, repo2) -> 0.9
      similar_dependencies?(repo1, repo2) -> 0.8
      similar_test_patterns?(repo1, repo2) -> 0.7
      true -> 0.5
    end
  end

  defp same_ecosystem?(repo1, repo2) do
    ecosystems = %{
      "phoenix" => :web,
      "phoenix_live_view" => :web,
      "plug" => :web,
      "oban" => :job_processing,
      "quantum" => :job_processing,
      "broadway" => :data_processing,
      "gen_stage" => :data_processing,
      "ecto" => :database,
      "postgrex" => :database
    }

    ecosystems[repo1] == ecosystems[repo2] and ecosystems[repo1] != nil
  end

  defp similar_dependencies?(repo1, repo2) do
    # Simplified dependency similarity check
    # In production, would analyze actual mix.exs dependencies
    common_deps = %{
      "phoenix" => ["ecto", "plug", "jason"],
      "phoenix_live_view" => ["phoenix", "jason"],
      "oban" => ["ecto", "postgrex", "jason"],
      "broadway" => ["gen_stage", "telemetry"]
    }

    deps1 = Map.get(common_deps, repo1, [])
    deps2 = Map.get(common_deps, repo2, [])

    if Enum.empty?(deps1) or Enum.empty?(deps2) do
      false
    else
      intersection_size = length(deps1 -- (deps1 -- deps2))
      union_size = length(Enum.uniq(deps1 ++ deps2))
      intersection_size / union_size > 0.3
    end
  end

  defp similar_test_patterns?(repo1, repo2) do
    # Simplified test pattern similarity
    test_patterns = %{
      "phoenix_live_view" => [:browser_automation, :websocket_testing],
      "oban" => [:time_based_scenarios, :database_testing],
      "broadway" => [:message_queue_testing, :backpressure_scenarios]
    }

    patterns1 = Map.get(test_patterns, repo1, [])
    patterns2 = Map.get(test_patterns, repo2, [])

    if Enum.empty?(patterns1) and Enum.empty?(patterns2) do
      # Both have standard patterns
      true
    else
      length(patterns1 -- (patterns1 -- patterns2)) > 0
    end
  end

  defp get_task_dependencies(task) do
    # Extract dependency information from task
    case Map.get(task, :repository_config) do
      %{dependencies: deps} when is_list(deps) -> deps
      _ -> []
    end
  end

  defp calculate_container_reuse_score(dependencies) do
    # Score based on how well dependencies enable container reuse
    base_score = 0.5

    # Common dependencies boost reuse score
    common_deps = ["jason", "ecto", "plug", "telemetry"]
    common_count = length(dependencies -- (dependencies -- common_deps))
    dependency_boost = min(common_count * 0.1, 0.3)

    # Heavy dependencies reduce reuse score
    heavy_deps = ["phoenix", "broadway", "dialyzer"]
    heavy_count = length(dependencies -- (dependencies -- heavy_deps))
    heavy_penalty = min(heavy_count * 0.15, 0.4)

    max(base_score + dependency_boost - heavy_penalty, 0.1)
  end

  defp create_optimized_groups(
         _tasks,
         repository_affinities,
         dependency_groups,
         target_batch_size
       ) do
    # Start with dependency groups as base
    initial_groups =
      dependency_groups
      |> Enum.map(& &1.tasks)
      |> Enum.filter(&(length(&1) > 0))

    # Merge groups with high repository affinity
    merged_groups = merge_high_affinity_groups(initial_groups, repository_affinities)

    # Split oversized groups and merge undersized ones
    balanced_groups = balance_group_sizes(merged_groups, target_batch_size)

    {:ok, balanced_groups}
  end

  defp merge_high_affinity_groups(groups, repository_affinities) do
    # Simplified merging logic - in production would be more sophisticated
    groups
    |> Enum.reduce([], fn group, acc ->
      case find_high_affinity_match(group, acc, repository_affinities) do
        {:merge, match_index} ->
          List.update_at(acc, match_index, &(&1 ++ group))

        :no_match ->
          [group | acc]
      end
    end)
  end

  defp find_high_affinity_match(group, existing_groups, repository_affinities) do
    group_repos = Enum.map(group, & &1.repository) |> Enum.uniq()

    existing_groups
    |> Enum.with_index()
    |> Enum.find(fn {existing_group, _index} ->
      existing_repos = Enum.map(existing_group, & &1.repository) |> Enum.uniq()

      calculate_group_affinity(group_repos, existing_repos, repository_affinities) >
        @affinity_threshold
    end)
    |> case do
      {_group, index} -> {:merge, index}
      nil -> :no_match
    end
  end

  defp calculate_group_affinity(repos1, repos2, repository_affinities) do
    if Enum.empty?(repos1) or Enum.empty?(repos2) do
      0.0
    else
      total_affinity =
        for repo1 <- repos1, repo2 <- repos2 do
          get_in(repository_affinities, [repo1, repo2]) || 0.0
        end
        |> Enum.sum()

      total_affinity / (length(repos1) * length(repos2))
    end
  end

  defp balance_group_sizes(groups, target_batch_size) do
    groups
    |> Enum.flat_map(&split_oversized_group(&1, target_batch_size))
    |> merge_undersized_groups(target_batch_size)
  end

  defp split_oversized_group(group, target_batch_size) do
    if length(group) > @max_batch_size do
      Enum.chunk_every(group, target_batch_size)
    else
      [group]
    end
  end

  defp merge_undersized_groups(groups, target_batch_size) do
    {undersized, properly_sized} = Enum.split_with(groups, &(length(&1) < @min_batch_size))

    merged_undersized =
      undersized
      |> Enum.reduce([], fn small_group, acc ->
        case acc do
          [] ->
            [small_group]

          [last_group | rest]
          when length(last_group) + length(small_group) <= target_batch_size ->
            [last_group ++ small_group | rest]

          _ ->
            [small_group | acc]
        end
      end)

    properly_sized ++ merged_undersized
  end

  defp add_batch_metadata(task_group) do
    repositories = Enum.map(task_group, & &1.repository) |> Enum.uniq()
    total_tasks = length(task_group)

    %{
      tasks: task_group,
      repositories: repositories,
      task_count: total_tasks,
      affinity_score: calculate_internal_affinity(task_group),
      estimated_time: estimate_batch_time(task_group),
      memory_estimate: estimate_batch_memory(task_group),
      container_reuse_potential: calculate_container_reuse_potential(task_group)
    }
  end

  defp calculate_internal_affinity(tasks) do
    if length(tasks) <= 1 do
      1.0
    else
      repositories = Enum.map(tasks, & &1.repository) |> Enum.uniq()

      # High affinity if tasks share repositories or have similar types
      repo_diversity = length(repositories) / length(tasks)
      type_similarity = calculate_type_similarity(tasks)

      (1.0 - repo_diversity) * 0.6 + type_similarity * 0.4
    end
  end

  defp calculate_type_similarity(tasks) do
    types = Enum.map(tasks, &Map.get(&1, :analysis_type, :unknown)) |> Enum.uniq()

    case length(types) do
      # All same type
      1 -> 1.0
      # Two types
      2 -> 0.7
      # Three types
      3 -> 0.5
      # Highly diverse
      _ -> 0.3
    end
  end

  defp estimate_batch_time(tasks) do
    # Estimate based on task types and repository complexity
    # 30 seconds per task baseline
    base_time_per_task = 30_000

    tasks
    |> Enum.map(&estimate_task_time/1)
    |> Enum.sum()
    # Minimum batch time
    |> max(base_time_per_task)
  end

  defp estimate_task_time(task) do
    # 30 seconds baseline
    base_time = 30_000
    complexity_multiplier = get_repository_complexity_multiplier(task.repository)
    analysis_multiplier = get_analysis_type_multiplier(Map.get(task, :analysis_type))

    round(base_time * complexity_multiplier * analysis_multiplier)
  end

  defp get_repository_complexity_multiplier(repository) do
    case repository do
      # More complex due to JS compilation
      "phoenix_live_view" -> 1.5
      # Complex due to message processing
      "broadway" -> 1.3
      # Database setup overhead
      "oban" -> 1.2
      # Multimedia processing complexity
      "membrane" -> 1.4
      # Standard complexity
      _ -> 1.0
    end
  end

  defp get_analysis_type_multiplier(analysis_type) do
    case analysis_type do
      # Dialyzer is slow
      :static_analysis -> 1.8
      # AST processing
      :pattern_analysis -> 1.2
      # Moderate processing
      :functional_analysis -> 1.1
      # Standard processing
      :otp_validation -> 1.0
      _ -> 1.0
    end
  end

  defp estimate_batch_memory(tasks) do
    # Estimate memory requirements for batch processing
    # 50MB per task baseline
    base_memory_per_task = 50 * 1024 * 1024

    tasks
    |> Enum.map(&estimate_task_memory/1)
    |> Enum.sum()
    |> max(base_memory_per_task)
  end

  defp estimate_task_memory(task) do
    # 50MB baseline
    base_memory = 50 * 1024 * 1024

    # Memory adjustments based on repository and analysis type
    repo_multiplier =
      case task.repository do
        # High memory for multimedia
        "membrane" -> 2.0
        # Numerical computing
        "nx" -> 1.8
        # Message buffering
        "broadway" -> 1.5
        # Asset compilation
        "phoenix_live_view" -> 1.3
        _ -> 1.0
      end

    analysis_multiplier =
      case Map.get(task, :analysis_type) do
        # PLT files and analysis
        :static_analysis -> 1.5
        # AST storage
        :pattern_analysis -> 1.2
        _ -> 1.0
      end

    round(base_memory * repo_multiplier * analysis_multiplier)
  end

  defp calculate_container_reuse_potential(tasks) do
    # Calculate how well tasks in this batch can reuse containers
    repositories = Enum.map(tasks, & &1.repository) |> Enum.uniq()

    if length(repositories) == 1 do
      # Perfect reuse - all same repository
      1.0
    else
      # Calculate based on shared dependencies and similar configurations
      shared_deps_score = calculate_shared_dependencies_score(tasks)
      config_similarity_score = calculate_config_similarity_score(tasks)

      shared_deps_score * 0.6 + config_similarity_score * 0.4
    end
  end

  defp dependency_is_shared?(dep, tasks) do
    sharing_tasks =
      Enum.count(tasks, fn task ->
        dep in get_task_dependencies(task)
      end)

    sharing_tasks > 1
  end

  defp calculate_shared_dependencies_score(tasks) do
    all_dependencies =
      tasks
      |> Enum.flat_map(&get_task_dependencies/1)
      |> Enum.uniq()

    if Enum.empty?(all_dependencies) do
      # No specific dependencies - moderate reuse potential
      0.5
    else
      # Calculate how many dependencies are shared across tasks
      shared_count =
        all_dependencies
        |> Enum.count(&dependency_is_shared?(&1, tasks))

      shared_count / length(all_dependencies)
    end
  end

  defp calculate_config_similarity_score(tasks) do
    # Simplified configuration similarity
    # In production, would compare actual repository configurations
    configs = Enum.map(tasks, &get_task_config_hash/1) |> Enum.uniq()

    case length(configs) do
      # All same config
      1 -> 1.0
      # Two configs
      2 -> 0.7
      # Three configs
      3 -> 0.5
      # High diversity
      _ -> 0.3
    end
  end

  defp get_task_config_hash(task) do
    # Simple hash of task configuration for similarity comparison
    config_data = [
      Map.get(task, :repository),
      Map.get(task, :analysis_type),
      Map.get(task, :specialized_requirements, [])
    ]

    :erlang.phash2(config_data)
  end

  defp batch_quality_score(batch) do
    # Calculate overall quality score for a batch
    affinity_weight = 0.4
    reuse_weight = 0.3
    time_efficiency_weight = 0.2
    memory_efficiency_weight = 0.1

    time_efficiency = calculate_time_efficiency(batch)
    memory_efficiency = calculate_memory_efficiency(batch)

    batch.affinity_score * affinity_weight +
      batch.container_reuse_potential * reuse_weight +
      time_efficiency * time_efficiency_weight +
      memory_efficiency * memory_efficiency_weight
  end

  defp calculate_time_efficiency(batch) do
    # Efficiency based on how well-sized the batch is
    # 5 minutes for 10 tasks
    optimal_time = @default_batch_size * 30_000
    actual_time = batch.estimated_time

    cond do
      actual_time <= optimal_time -> 1.0
      actual_time <= optimal_time * 1.5 -> 0.8
      actual_time <= optimal_time * 2.0 -> 0.6
      true -> 0.4
    end
  end

  defp calculate_memory_efficiency(batch) do
    # Efficiency based on memory usage vs available resources
    # 512MB optimal
    optimal_memory = 512 * 1024 * 1024
    actual_memory = batch.memory_estimate

    cond do
      actual_memory <= optimal_memory -> 1.0
      actual_memory <= optimal_memory * 1.5 -> 0.8
      actual_memory <= optimal_memory * 2.0 -> 0.6
      true -> 0.4
    end
  end

  defp balance_batch_sizes(batches, target_batch_size) do
    # Ensure batches are reasonably sized and balanced
    batches
    |> Enum.sort_by(& &1.affinity_score, :desc)
    |> redistribute_tasks_for_balance(target_batch_size)
  end

  defp redistribute_tasks_for_balance(batches, target_batch_size) do
    # Simplified redistribution - in production would be more sophisticated
    batches
    |> Enum.map(fn batch ->
      if batch.task_count > @max_batch_size do
        # Split large batches
        split_large_batch(batch, target_batch_size)
      else
        [batch]
      end
    end)
    |> List.flatten()
    |> merge_small_batches(target_batch_size)
  end

  defp split_large_batch(batch, target_batch_size) do
    batch.tasks
    |> Enum.chunk_every(target_batch_size)
    |> Enum.map(fn task_chunk ->
      %{
        batch
        | tasks: task_chunk,
          task_count: length(task_chunk),
          estimated_time: estimate_batch_time(task_chunk),
          memory_estimate: estimate_batch_memory(task_chunk)
      }
    end)
  end

  defp merge_small_batches(batches, target_batch_size) do
    {small_batches, normal_batches} = Enum.split_with(batches, &(&1.task_count < @min_batch_size))

    merged_small =
      small_batches
      |> Enum.reduce([], fn small_batch, acc ->
        case acc do
          [] ->
            [small_batch]

          [last_batch | rest]
          when last_batch.task_count + small_batch.task_count <= target_batch_size ->
            merged = merge_two_batches(last_batch, small_batch)
            [merged | rest]

          _ ->
            [small_batch | acc]
        end
      end)

    normal_batches ++ merged_small
  end

  defp merge_two_batches(batch1, batch2) do
    merged_tasks = batch1.tasks ++ batch2.tasks

    %{
      tasks: merged_tasks,
      repositories: Enum.uniq(batch1.repositories ++ batch2.repositories),
      task_count: batch1.task_count + batch2.task_count,
      affinity_score: (batch1.affinity_score + batch2.affinity_score) / 2,
      estimated_time: batch1.estimated_time + batch2.estimated_time,
      memory_estimate: batch1.memory_estimate + batch2.memory_estimate,
      container_reuse_potential:
        (batch1.container_reuse_potential + batch2.container_reuse_potential) / 2
    }
  end

  defp calculate_task_batch_affinity(task, batch) do
    # Calculate how well a task fits with an existing batch
    task_repo = task.repository
    batch_repos = batch.repositories

    # Check repository affinity
    repo_affinity =
      if task_repo in batch_repos do
        1.0
      else
        batch_repos
        |> Enum.map(&calculate_repo_pair_affinity(task_repo, &1))
        |> Enum.max(fn -> 0.0 end)
      end

    # Check task type compatibility
    task_type = Map.get(task, :analysis_type, :unknown)
    batch_types = Enum.map(batch.tasks, &Map.get(&1, :analysis_type, :unknown)) |> Enum.uniq()

    type_compatibility =
      if task_type in batch_types do
        1.0
      else
        # Different but potentially compatible
        0.6
      end

    # Weighted combination
    repo_affinity * 0.7 + type_compatibility * 0.3
  end

  defp recalculate_batch_metadata(batch) do
    add_batch_metadata(batch.tasks)
  end
end
