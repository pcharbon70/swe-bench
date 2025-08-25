defmodule SweBench.Pipeline.AnalysisParallelizer do
  @moduledoc """
  Coordinates parallel execution of all Phase 2 analysis components.

  Parallelizes pattern matching analysis, OTP behavior validation, static analysis,
  and functional programming scoring while efficiently aggregating results and
  handling analysis conflicts and merging.
  """

  require Logger
  use Task

  alias SweBench.FunctionalAnalysis
  alias SweBench.PatternAnalysis
  alias SweBench.PatternAnalysis.OTPValidator
  alias SweBench.StaticAnalysis
  alias SweBench.Pipeline.{AdaptiveThrottle, IntelligentCache, PipelineMetrics}

  # 30 seconds per analysis
  @analysis_timeout 30_000
  # Maximum concurrent analyses per task
  @max_parallel_analyses 4
  # 5 seconds to merge results
  @result_merge_timeout 5_000

  @doc """
  Executes all Phase 2 analyses in parallel for a given code sample.

  ## Parameters
    - repository: Repository identifier
    - commit_hash: Commit hash for caching
    - source_code: Elixir source code to analyze
    - opts: Analysis options and configuration

  ## Returns
    - {:ok, aggregated_results} with all analysis results combined
    - {:error, reason} if analysis fails

  ## Examples
      iex> AnalysisParallelizer.analyze_code_parallel("elixir", "abc123", source_code)
      {:ok, %{
        overall_score: 0.85,
        pattern_analysis: %{...},
        functional_analysis: %{...},
        static_analysis: %{...},
        otp_validation: %{...},
        performance_metrics: %{...}
      }}
  """
  def analyze_code_parallel(repository, commit_hash, source_code, opts \\ []) do
    Logger.debug(
      "Starting parallel analysis for #{repository}:#{String.slice(commit_hash, 0, 8)}"
    )

    analysis_start_time = System.monotonic_time(:millisecond)

    # Check cache first
    case check_analysis_cache(repository, commit_hash, source_code) do
      {:hit, cached_results} ->
        Logger.debug("Cache hit for #{repository}:#{String.slice(commit_hash, 0, 8)}")
        PipelineMetrics.record_stage_completion(:analysis_parallelizer, 1, cache_hit: true)
        {:ok, cached_results}

      :miss ->
        # Perform parallel analysis
        case execute_parallel_analyses(repository, commit_hash, source_code, opts) do
          {:ok, results} ->
            analysis_time = System.monotonic_time(:millisecond) - analysis_start_time

            # Cache the results
            cache_analysis_results(repository, commit_hash, results)

            # Record performance metrics
            PipelineMetrics.record_stage_completion(:analysis_parallelizer, analysis_time)

            Logger.debug("Parallel analysis completed for #{repository} in #{analysis_time}ms")
            {:ok, results}

          {:error, reason} ->
            analysis_time = System.monotonic_time(:millisecond) - analysis_start_time

            PipelineMetrics.record_stage_completion(:analysis_parallelizer, analysis_time,
              error: true
            )

            Logger.error("Parallel analysis failed for #{repository}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Executes parallel analysis with custom analysis configuration.
  """
  def analyze_with_config(repository, commit_hash, source_code, analysis_config) do
    enabled_analyses =
      Map.get(analysis_config, :enabled_analyses, [:pattern, :functional, :static, :otp])

    concurrency_limit = Map.get(analysis_config, :concurrency_limit, @max_parallel_analyses)
    custom_timeouts = Map.get(analysis_config, :timeouts, %{})

    # Filter analyses based on configuration
    analysis_tasks =
      enabled_analyses
      |> Enum.map(
        &create_analysis_task(&1, repository, commit_hash, source_code, custom_timeouts)
      )
      |> Enum.reject(&is_nil/1)

    # Execute with configured concurrency
    execute_analysis_tasks_parallel(analysis_tasks, concurrency_limit)
  end

  @doc """
  Gets current parallelization statistics and performance metrics.
  """
  def get_parallelization_stats do
    %{
      active_analyses: count_active_analyses(),
      average_parallelization_factor: calculate_avg_parallelization_factor(),
      analysis_queue_depth: get_analysis_queue_depth(),
      cache_hit_rate: get_analysis_cache_hit_rate(),
      throughput_improvement: calculate_throughput_improvement()
    }
  end

  # Private implementation functions

  defp create_analysis_task_ref(analysis_task) do
    task_ref =
      Task.async(fn ->
        try do
          analysis_task.function.()
        rescue
          error ->
            {:error, {:task_exception, error}}
        end
      end)

    {task_ref, analysis_task}
  end

  defp shutdown_all_tasks(pending_tasks) do
    Enum.each(pending_tasks, fn {task_ref, _analysis_task} ->
      Task.shutdown(task_ref, :brutal_kill)
    end)
  end

  defp process_single_yielded_result({task_ref, task_result}, {acc_completed, acc_pending}) do
    case task_result do
      {:ok, analysis_result} ->
        # Find the analysis task info
        {_ref, analysis_task} = Enum.find(acc_pending, fn {ref, _} -> ref == task_ref end)

        completed_analysis = %{
          analysis_type: analysis_task.analysis_type,
          result: analysis_result,
          priority: analysis_task.priority
        }

        updated_completed = [completed_analysis | acc_completed]
        updated_pending = Enum.reject(acc_pending, fn {ref, _} -> ref == task_ref end)

        {updated_completed, updated_pending}

      {:error, reason} ->
        Logger.warning("Analysis task failed: #{inspect(reason)}")
        # Remove failed task from pending but don't add to completed
        updated_pending = Enum.reject(acc_pending, fn {ref, _} -> ref == task_ref end)
        {acc_completed, updated_pending}

      nil ->
        # Task still running
        {acc_completed, acc_pending}
    end
  end

  defp execute_parallel_analyses(repository, commit_hash, source_code, opts) do
    # Check concurrency availability
    case AdaptiveThrottle.request_concurrency_slot() do
      {:ok, :proceed} ->
        result = do_parallel_analyses(repository, commit_hash, source_code, opts)
        AdaptiveThrottle.release_concurrency_slot()
        result

      {:error, :throttled} ->
        Logger.warning("Analysis throttled due to resource constraints")
        {:error, :throttled}
    end
  rescue
    error ->
      AdaptiveThrottle.release_concurrency_slot()
      {:error, {:analysis_exception, error}}
  end

  defp do_parallel_analyses(repository, commit_hash, source_code, opts) do
    _timeout = Keyword.get(opts, :timeout, @analysis_timeout)

    # Create analysis tasks
    analysis_tasks = [
      create_pattern_analysis_task(repository, commit_hash, source_code),
      create_functional_analysis_task(repository, commit_hash, source_code),
      create_static_analysis_task(repository, commit_hash, source_code),
      create_otp_validation_task(repository, commit_hash, source_code)
    ]

    # Execute analyses in parallel
    case execute_analysis_tasks_parallel(analysis_tasks, @max_parallel_analyses) do
      {:ok, analysis_results} ->
        # Aggregate and merge results
        case aggregate_analysis_results(analysis_results, repository, commit_hash) do
          {:ok, aggregated_results} ->
            {:ok, aggregated_results}

          {:error, reason} ->
            {:error, {:aggregation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:parallel_execution_failed, reason}}
    end
  end

  defp create_pattern_analysis_task(repository, commit_hash, source_code) do
    %{
      analysis_type: :pattern_analysis,
      function: fn ->
        start_time = System.monotonic_time(:millisecond)

        result =
          case PatternAnalysis.analyze_patterns(source_code) do
            {:ok, analysis_result} ->
              end_time = System.monotonic_time(:millisecond)
              processing_time = end_time - start_time

              {:ok,
               %{
                 analysis_type: :pattern_analysis,
                 repository: repository,
                 commit_hash: commit_hash,
                 result: analysis_result,
                 processing_time_ms: processing_time,
                 timestamp: DateTime.utc_now()
               }}

            {:error, reason} ->
              {:error, {:pattern_analysis_failed, reason}}
          end

        PipelineMetrics.record_stage_completion(
          :pattern_analysis,
          System.monotonic_time(:millisecond) - start_time
        )

        result
      end,
      priority: :normal,
      timeout: @analysis_timeout
    }
  end

  defp create_functional_analysis_task(repository, commit_hash, source_code) do
    %{
      analysis_type: :functional_analysis,
      function: fn ->
        start_time = System.monotonic_time(:millisecond)

        result =
          case FunctionalAnalysis.analyze_code(source_code) do
            {:ok, analysis_result} ->
              end_time = System.monotonic_time(:millisecond)
              processing_time = end_time - start_time

              {:ok,
               %{
                 analysis_type: :functional_analysis,
                 repository: repository,
                 commit_hash: commit_hash,
                 result: analysis_result,
                 processing_time_ms: processing_time,
                 timestamp: DateTime.utc_now()
               }}

            {:error, reason} ->
              {:error, {:functional_analysis_failed, reason}}
          end

        PipelineMetrics.record_stage_completion(
          :functional_analysis,
          System.monotonic_time(:millisecond) - start_time
        )

        result
      end,
      priority: :normal,
      timeout: @analysis_timeout
    }
  end

  defp create_static_analysis_task(repository, commit_hash, source_code) do
    %{
      analysis_type: :static_analysis,
      function: fn ->
        start_time = System.monotonic_time(:millisecond)

        result =
          case StaticAnalysis.analyze_code(source_code) do
            {:ok, analysis_result} ->
              end_time = System.monotonic_time(:millisecond)
              processing_time = end_time - start_time

              {:ok,
               %{
                 analysis_type: :static_analysis,
                 repository: repository,
                 commit_hash: commit_hash,
                 result: analysis_result,
                 processing_time_ms: processing_time,
                 timestamp: DateTime.utc_now()
               }}

            {:error, reason} ->
              {:error, {:static_analysis_failed, reason}}
          end

        PipelineMetrics.record_stage_completion(
          :static_analysis,
          System.monotonic_time(:millisecond) - start_time
        )

        result
      end,
      # Static analysis often takes longest
      priority: :high,
      # Allow more time for Dialyzer
      timeout: @analysis_timeout * 2
    }
  end

  defp create_otp_validation_task(repository, commit_hash, source_code) do
    %{
      analysis_type: :otp_validation,
      function: fn ->
        start_time = System.monotonic_time(:millisecond)

        result =
          case OTPValidator.validate_otp_behaviors(source_code) do
            {:ok, analysis_result} ->
              end_time = System.monotonic_time(:millisecond)
              processing_time = end_time - start_time

              {:ok,
               %{
                 analysis_type: :otp_validation,
                 repository: repository,
                 commit_hash: commit_hash,
                 result: analysis_result,
                 processing_time_ms: processing_time,
                 timestamp: DateTime.utc_now()
               }}

            {:error, reason} ->
              {:error, {:otp_validation_failed, reason}}
          end

        PipelineMetrics.record_stage_completion(
          :otp_validation,
          System.monotonic_time(:millisecond) - start_time
        )

        result
      end,
      priority: :normal,
      timeout: @analysis_timeout
    }
  end

  defp create_analysis_task(analysis_type, repository, commit_hash, source_code, custom_timeouts) do
    timeout = Map.get(custom_timeouts, analysis_type, @analysis_timeout)

    case analysis_type do
      :pattern -> create_pattern_analysis_task(repository, commit_hash, source_code)
      :functional -> create_functional_analysis_task(repository, commit_hash, source_code)
      :static -> create_static_analysis_task(repository, commit_hash, source_code)
      :otp -> create_otp_validation_task(repository, commit_hash, source_code)
      _ -> nil
    end
    |> case do
      nil -> nil
      task -> %{task | timeout: timeout}
    end
  end

  defp execute_analysis_tasks_parallel(analysis_tasks, concurrency_limit) do
    if Enum.empty?(analysis_tasks) do
      {:ok, []}
    else
      # Execute tasks with controlled concurrency
      task_refs =
        analysis_tasks
        |> Enum.take(concurrency_limit)
        |> Enum.map(&create_analysis_task_ref/1)

      # Collect results with timeout handling
      collect_analysis_results(task_refs, [])
    end
  end

  defp collect_analysis_results([], completed_results) do
    {:ok, completed_results}
  end

  defp collect_analysis_results(pending_tasks, completed_results) do
    case Task.yield_many(Enum.map(pending_tasks, &elem(&1, 0)), @result_merge_timeout) do
      [] ->
        # All tasks still running - wait and retry
        case Task.yield_many(Enum.map(pending_tasks, &elem(&1, 0)), @analysis_timeout) do
          yielded_results when yielded_results != [] ->
            process_yielded_results(yielded_results, pending_tasks, completed_results)

          [] ->
            # Tasks timed out - shut them down
            shutdown_all_tasks(pending_tasks)
            {:error, :analysis_timeout}
        end

      yielded_results ->
        process_yielded_results(yielded_results, pending_tasks, completed_results)
    end
  end

  defp process_yielded_results(yielded_results, pending_tasks, completed_results) do
    # Process completed tasks
    {new_completed, still_pending} =
      Enum.reduce(
        yielded_results,
        {completed_results, pending_tasks},
        &process_single_yielded_result/2
      )

    # Continue with remaining pending tasks
    if Enum.empty?(still_pending) do
      {:ok, new_completed}
    else
      collect_analysis_results(still_pending, new_completed)
    end
  end

  defp aggregate_analysis_results(analysis_results, repository, commit_hash) do
    Logger.debug("Aggregating #{length(analysis_results)} analysis results")

    # Extract individual analysis results
    pattern_result = find_analysis_result(analysis_results, :pattern_analysis)
    functional_result = find_analysis_result(analysis_results, :functional_analysis)
    static_result = find_analysis_result(analysis_results, :static_analysis)
    otp_result = find_analysis_result(analysis_results, :otp_validation)

    # Calculate combined metrics
    combined_scores =
      calculate_combined_scores(pattern_result, functional_result, static_result, otp_result)

    # Detect and resolve analysis conflicts
    conflict_resolution =
      resolve_analysis_conflicts([pattern_result, functional_result, static_result, otp_result])

    # Create aggregated result
    aggregated_result = %{
      repository: repository,
      commit_hash: commit_hash,
      overall_score: combined_scores.overall_score,
      tier: calculate_score_tier(combined_scores.overall_score),
      percentage: calculate_score_percentage(combined_scores.overall_score),
      individual_analyses: %{
        pattern_analysis: extract_analysis_data(pattern_result),
        functional_analysis: extract_analysis_data(functional_result),
        static_analysis: extract_analysis_data(static_result),
        otp_validation: extract_analysis_data(otp_result)
      },
      combined_scores: combined_scores,
      conflict_resolution: conflict_resolution,
      performance_metrics: calculate_performance_metrics(analysis_results),
      metadata: %{
        processed_at: DateTime.utc_now(),
        analysis_version: "2.8.0",
        parallelization_enabled: true,
        # Will be updated if cached
        cache_used: false
      }
    }

    {:ok, aggregated_result}
  end

  defp find_analysis_result(analysis_results, analysis_type) do
    Enum.find(analysis_results, fn analysis ->
      analysis.analysis_type == analysis_type
    end)
  end

  defp extract_analysis_data(nil), do: %{error: :analysis_not_completed}

  defp extract_analysis_data(analysis) do
    case analysis.result do
      {:ok, data} -> data
      {:error, reason} -> %{error: reason}
    end
  end

  defp calculate_combined_scores(pattern_result, functional_result, static_result, otp_result) do
    # Extract individual scores
    pattern_score = extract_score(pattern_result, :overall_score, 0.0)
    functional_score = extract_score(functional_result, :overall_score, 0.0)
    static_score = extract_score(static_result, :overall_score, 0.0)
    otp_score = extract_score(otp_result, :compliance_score, 0.0)

    # Calculate weighted overall score
    # Emphasize functional programming and pattern matching for Elixir
    overall_score =
      pattern_score * 0.3 +
        functional_score * 0.35 +
        static_score * 0.25 +
        otp_score * 0.1

    %{
      overall_score: overall_score,
      pattern_analysis_score: pattern_score,
      functional_analysis_score: functional_score,
      static_analysis_score: static_score,
      otp_compliance_score: otp_score,
      score_confidence:
        calculate_score_confidence([pattern_result, functional_result, static_result, otp_result])
    }
  end

  defp extract_score(nil, _score_key, default), do: default

  defp extract_score(analysis, score_key, default) do
    case analysis.result do
      {:ok, data} -> Map.get(data, score_key, default)
      {:error, _} -> default
    end
  end

  defp calculate_score_confidence(analysis_results) do
    # Calculate confidence based on how many analyses completed successfully
    successful_analyses =
      Enum.count(analysis_results, fn analysis ->
        analysis != nil and match?({:ok, _}, analysis.result)
      end)

    total_analyses = length(Enum.reject(analysis_results, &is_nil/1))

    if total_analyses > 0 do
      successful_analyses / total_analyses
    else
      0.0
    end
  end

  defp resolve_analysis_conflicts(analysis_results) do
    # Detect conflicts between different analysis results
    conflicts = detect_analysis_conflicts(analysis_results)

    # Apply conflict resolution strategies
    resolutions = Enum.map(conflicts, &apply_conflict_resolution/1)

    %{
      conflicts_detected: length(conflicts),
      conflicts: conflicts,
      resolutions: resolutions,
      resolution_strategy: :weighted_consensus
    }
  end

  defp detect_analysis_conflicts(analysis_results) do
    # Check for score inconsistencies
    score_conflicts = detect_score_inconsistencies(analysis_results)

    # Check for analysis-specific conflicts
    pattern_conflicts = check_pattern_analysis_conflicts(analysis_results)
    functional_conflicts = check_functional_analysis_conflicts(analysis_results)

    score_conflicts ++ pattern_conflicts ++ functional_conflicts
  end

  defp detect_score_inconsistencies(analysis_results) do
    scores = extract_valid_scores(analysis_results)
    score_variance = calculate_score_variance(scores)

    if score_variance > 0.3 do
      [%{type: :score_inconsistency, variance: score_variance, scores: scores}]
    else
      []
    end
  end

  defp extract_valid_scores(analysis_results) do
    analysis_results
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&extract_score(&1, :overall_score, 0.0))
    |> Enum.reject(&(&1 == 0.0))
  end

  defp calculate_score_variance(scores) do
    if length(scores) > 1 do
      mean_score = Enum.sum(scores) / length(scores)

      variance =
        scores
        |> Enum.map(&((&1 - mean_score) * (&1 - mean_score)))
        |> Enum.sum()
        |> Kernel./(length(scores))

      :math.sqrt(variance)
    else
      0.0
    end
  end

  defp check_pattern_analysis_conflicts(analysis_results) do
    pattern_result = find_analysis_result(analysis_results, :pattern_analysis)
    functional_result = find_analysis_result(analysis_results, :functional_analysis)

    if pattern_result && functional_result do
      check_pattern_functional_disagreement(pattern_result, functional_result)
    else
      []
    end
  end

  defp check_pattern_functional_disagreement(pattern_result, functional_result) do
    pattern_score = extract_score(pattern_result, :overall_score, 0.0)
    functional_score = extract_score(functional_result, :overall_score, 0.0)

    if abs(pattern_score - functional_score) > 0.4 do
      [
        %{
          type: :pattern_functional_disagreement,
          pattern_score: pattern_score,
          functional_score: functional_score,
          difference: abs(pattern_score - functional_score)
        }
      ]
    else
      []
    end
  end

  defp check_functional_analysis_conflicts(analysis_results) do
    functional_result = find_analysis_result(analysis_results, :functional_analysis)

    case functional_result && functional_result.result do
      {:ok, scores} when is_map(scores) ->
        check_functional_score_consistency(scores, functional_result)

      _ ->
        []
    end
  end

  defp check_functional_score_consistency(
         %{immutability_score: immut, pipeline_score: pipe, purity_score: purity},
         functional_result
       )
       when is_number(immut) and is_number(pipe) and is_number(purity) do
    purity_conflicts = check_purity_immutability_conflict(purity, immut)
    pipeline_conflicts = check_pipeline_overall_conflict(pipe, functional_result)

    purity_conflicts ++ pipeline_conflicts
  end

  defp check_functional_score_consistency(_, _), do: []

  defp check_purity_immutability_conflict(purity, immut) do
    if purity > 0.8 and immut < 0.5 do
      [
        %{
          type: :purity_immutability_conflict,
          purity_score: purity,
          immutability_score: immut
        }
      ]
    else
      []
    end
  end

  defp check_pipeline_overall_conflict(pipe, functional_result) do
    overall_functional = extract_score(functional_result, :overall_score, 0.0)

    if pipe > 0.8 and overall_functional < 0.5 do
      [
        %{
          type: :pipeline_overall_conflict,
          pipeline_score: pipe,
          overall_functional_score: overall_functional
        }
      ]
    else
      []
    end
  end

  defp apply_conflict_resolution(conflict) do
    case conflict.type do
      :score_inconsistency ->
        # Use median score as resolution
        median_score = conflict.scores |> Enum.sort() |> Enum.at(div(length(conflict.scores), 2))

        %{
          conflict_type: conflict.type,
          resolution: :use_median,
          resolved_score: median_score,
          confidence: 0.7
        }

      :pattern_functional_disagreement ->
        # Weight functional analysis slightly higher for Elixir
        resolved_score = conflict.pattern_score * 0.4 + conflict.functional_score * 0.6

        %{
          conflict_type: conflict.type,
          resolution: :weighted_average,
          resolved_score: resolved_score,
          confidence: 0.8
        }

      _ ->
        %{
          conflict_type: conflict.type,
          resolution: :no_resolution,
          confidence: 0.5
        }
    end
  end

  defp calculate_performance_metrics(analysis_results) do
    processing_times =
      analysis_results
      |> Enum.map(fn analysis ->
        case analysis.result do
          {:ok, data} -> data.processing_time_ms || 0
          {:error, _} -> 0
        end
      end)

    total_time = Enum.sum(processing_times)
    max_time = Enum.max(processing_times, fn -> 0 end)

    avg_time =
      if Enum.empty?(processing_times) do
        0.0
      else
        total_time / length(processing_times)
      end

    # Calculate parallelization efficiency
    # Perfect parallelization would have total_time ≈ max_time
    parallelization_efficiency =
      if max_time > 0 do
        max_time / total_time
      else
        0.0
      end

    %{
      total_processing_time_ms: total_time,
      max_processing_time_ms: max_time,
      average_processing_time_ms: round(avg_time),
      parallelization_efficiency: Float.round(parallelization_efficiency, 3),
      analyses_completed: length(processing_times),
      speedup_factor: if(max_time > 0, do: Float.round(total_time / max_time, 2), else: 1.0)
    }
  end

  defp calculate_score_tier(overall_score) do
    case overall_score do
      # 100%
      score when score >= 0.9 -> 4
      # 75%
      score when score >= 0.75 -> 3
      # 50%
      score when score >= 0.5 -> 2
      # 25%
      score when score >= 0.25 -> 1
      # 0%
      _ -> 0
    end
  end

  defp calculate_score_percentage(overall_score) do
    case calculate_score_tier(overall_score) do
      4 -> 100
      3 -> 75
      2 -> 50
      1 -> 25
      0 -> 0
    end
  end

  # Cache integration functions

  defp check_analysis_cache(repository, commit_hash, source_code) do
    # Create cache key based on source code hash for accuracy
    source_hash = :crypto.hash(:sha256, source_code) |> Base.encode16(case: :lower)
    _cache_key = {repository, commit_hash, :complete_analysis, source_hash}

    case IntelligentCache.get_ast_analysis(repository, commit_hash, :complete_analysis) do
      {:ok, cached_data} ->
        # Verify cache validity with source hash
        if Map.get(cached_data, :source_hash) == source_hash do
          {:hit, cached_data}
        else
          # Source changed, cache invalid
          :miss
        end

      {:error, :not_found} ->
        :miss

      {:error, _reason} ->
        :miss
    end
  end

  defp cache_analysis_results(repository, commit_hash, results) do
    # Add source hash for cache validation
    source_hash = Map.get(results.metadata, :source_hash, "unknown")
    cacheable_results = Map.put(results, :source_hash, source_hash)

    # Cache with extended TTL for complete analysis
    # 2 hours
    cache_opts = [ttl_seconds: 7200, cache_levels: [:memory, :disk]]

    case IntelligentCache.put_ast_analysis(
           repository,
           commit_hash,
           :complete_analysis,
           cacheable_results,
           cache_opts
         ) do
      {:ok} ->
        Logger.debug(
          "Cached analysis results for #{repository}:#{String.slice(commit_hash, 0, 8)}"
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to cache analysis results: #{inspect(reason)}")
        :error
    end
  end

  # Statistics and monitoring functions

  defp count_active_analyses do
    # Count currently running analysis tasks
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {SweBench.Pipeline.AnalysisParallelizer, _, _}] -> true
        [current_function: {SweBench.PatternAnalysis, _, _}] -> true
        [current_function: {SweBench.FunctionalAnalysis, _, _}] -> true
        [current_function: {SweBench.StaticAnalysis, _, _}] -> true
        _ -> false
      end
    end)
  end

  defp calculate_avg_parallelization_factor do
    # Calculate average parallelization factor from recent metrics
    case PipelineMetrics.get_current_metrics() do
      {:ok, metrics} ->
        stage_metrics = Map.get(metrics, :stage_metrics, %{})

        analysis_stages = [
          :pattern_analysis,
          :functional_analysis,
          :static_analysis,
          :otp_validation
        ]

        active_stages =
          analysis_stages
          |> Enum.count(fn stage -> Map.has_key?(stage_metrics, stage) end)

        if active_stages > 0 do
          # Parallelization factor
          Float.round(active_stages / 1.0, 2)
        else
          1.0
        end

      _ ->
        1.0
    end
  end

  defp get_analysis_queue_depth do
    # Get current analysis queue depth
    case GenServer.call(SweBench.Pipeline.TaskProducer, :get_analysis_queue_size, 1000) do
      {:ok, queue_size} -> queue_size
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp get_analysis_cache_hit_rate do
    case IntelligentCache.get_cache_statistics() do
      {:ok, stats} -> Map.get(stats, :hit_rates, %{}) |> Map.get(:overall, 0.0)
      _ -> 0.0
    end
  end

  defp calculate_throughput_improvement do
    # Calculate improvement over sequential processing
    # This would be measured against baseline sequential performance
    case PipelineMetrics.get_current_metrics() do
      {:ok, metrics} ->
        current_throughput = get_in(metrics, [:performance_summary, :overall_throughput]) || 0.0
        # 50 tasks/hour sequential baseline
        baseline_throughput = 50.0

        if baseline_throughput > 0 do
          Float.round(current_throughput / baseline_throughput, 2)
        else
          1.0
        end

      _ ->
        1.0
    end
  end

  # Utility functions for external integration

  @doc """
  Analyzes code with specific analysis subset for focused evaluation.
  """
  def analyze_code_subset(repository, commit_hash, source_code, analysis_types, _opts \\ []) do
    if Enum.empty?(analysis_types) do
      {:error, :no_analyses_specified}
    else
      # Create tasks only for specified analysis types
      analysis_tasks =
        analysis_types
        |> Enum.map(&create_analysis_task(&1, repository, commit_hash, source_code, %{}))
        |> Enum.reject(&is_nil/1)

      concurrency = min(length(analysis_tasks), @max_parallel_analyses)

      case execute_analysis_tasks_parallel(analysis_tasks, concurrency) do
        {:ok, results} ->
          aggregate_analysis_results(results, repository, commit_hash)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Provides real-time analysis progress for long-running evaluations.
  """
  def get_analysis_progress(repository, commit_hash) do
    # Check for in-progress analysis tasks
    active_analyses = count_active_analyses()

    # Estimate completion based on average processing times
    estimated_completion = estimate_analysis_completion(repository)

    %{
      repository: repository,
      commit_hash: String.slice(commit_hash, 0, 8),
      active_analyses: active_analyses,
      estimated_completion_seconds: estimated_completion,
      current_stage: determine_current_analysis_stage(),
      progress_percentage: calculate_analysis_progress_percentage(repository, commit_hash)
    }
  end

  defp estimate_analysis_completion(repository) do
    # Estimate based on repository complexity and historical data
    # 30 seconds baseline
    base_time = 30

    complexity_multiplier =
      case repository do
        "phoenix_live_view" -> 1.5
        "broadway" -> 1.3
        "oban" -> 1.2
        "membrane" -> 1.4
        _ -> 1.0
      end

    round(base_time * complexity_multiplier)
  end

  defp determine_current_analysis_stage do
    # Determine which analysis stage is currently running
    active_stages = []

    if count_active_pattern_analyses() > 0,
      do: active_stages = [:pattern_analysis | active_stages]

    if count_active_functional_analyses() > 0,
      do: active_stages = [:functional_analysis | active_stages]

    if count_active_static_analyses() > 0, do: active_stages = [:static_analysis | active_stages]
    if count_active_otp_analyses() > 0, do: active_stages = [:otp_validation | active_stages]

    case active_stages do
      [] -> :idle
      [single_stage] -> single_stage
      multiple_stages -> {:parallel, multiple_stages}
    end
  end

  defp count_active_pattern_analyses do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {SweBench.PatternAnalysis, _, _}] -> true
        _ -> false
      end
    end)
  end

  defp count_active_functional_analyses do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {SweBench.FunctionalAnalysis, _, _}] -> true
        _ -> false
      end
    end)
  end

  defp count_active_static_analyses do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {SweBench.StaticAnalysis, _, _}] -> true
        _ -> false
      end
    end)
  end

  defp count_active_otp_analyses do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {SweBench.PatternAnalysis.OTPValidator, _, _}] -> true
        _ -> false
      end
    end)
  end

  defp calculate_analysis_progress_percentage(_repository, _commit_hash) do
    # Simplified progress calculation
    # In production, would track actual analysis stages and completion
    active_analyses = count_active_analyses()

    case active_analyses do
      # No active analyses, assume complete
      0 -> 100
      # Single analysis running, likely near completion
      1 -> 75
      # Multiple analyses, mid-progress
      2 -> 50
      # Most analyses still running
      3 -> 25
      # All analyses running, just started
      _ -> 10
    end
  end
end
