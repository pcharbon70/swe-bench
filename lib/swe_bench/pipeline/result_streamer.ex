defmodule SweBench.Pipeline.ResultStreamer do
  @moduledoc """
  Continuous result streaming without buffering for parallel evaluation pipeline.

  Streams evaluation results directly to database, implements partial result
  aggregation, provides real-time progress broadcasting, and handles
  out-of-order result arrival with deduplication.
  """

  use GenStage
  require Logger

  alias SweBench.Repo

  @producer_demand_min 5
  @producer_demand_max 20
  # 5 minutes
  @deduplication_window 300_000
  # 10 seconds
  @progress_broadcast_interval 10_000

  defstruct [
    :subscription,
    :result_buffer,
    :processed_count,
    :error_count,
    :start_time,
    :last_progress_broadcast,
    :deduplication_cache,
    :partial_aggregations,
    :subscribers
  ]

  # Public API

  @doc """
  Starts the result streamer as a consumer.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes to receive progress broadcasts.
  """
  def subscribe_to_progress(subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe_progress, subscriber_pid})
  end

  @doc """
  Gets current streaming statistics.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Manually triggers result aggregation and database flush.
  """
  def flush_results do
    GenServer.call(__MODULE__, :flush_results)
  end

  # GenStage callbacks

  @impl GenStage
  def init(opts) do
    upstream_producer = Keyword.get(opts, :subscribe_to, SweBench.Pipeline.ResultAnalyzer)

    state = %__MODULE__{
      subscription: nil,
      result_buffer: [],
      processed_count: 0,
      error_count: 0,
      start_time: DateTime.utc_now(),
      last_progress_broadcast: DateTime.utc_now(),
      deduplication_cache: %{},
      partial_aggregations: %{},
      subscribers: []
    }

    # Subscribe to upstream producer
    {:consumer, state,
     subscribe_to: [
       {upstream_producer, [min_demand: @producer_demand_min, max_demand: @producer_demand_max]}
     ]}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    Logger.debug("ResultStreamer received #{length(events)} evaluation results")

    # Process events in streaming fashion
    {processed_state, streaming_results} = process_events_streaming(events, state)

    # Stream results to database without buffering
    {:ok, _} = stream_results_to_database_batched(streaming_results)

    # Update partial aggregations
    updated_state = update_partial_aggregations(streaming_results, processed_state)

    # Broadcast progress if interval elapsed
    final_state = maybe_broadcast_progress(updated_state)

    {:noreply, [], final_state}
  end

  @impl GenStage
  def handle_call({:subscribe_progress, subscriber_pid}, _from, state) do
    Logger.debug("Adding progress subscriber: #{inspect(subscriber_pid)}")
    updated_subscribers = [subscriber_pid | state.subscribers]
    {:reply, :ok, [], %{state | subscribers: updated_subscribers}}
  end

  @impl GenStage
  def handle_call(:get_statistics, _from, state) do
    current_time = DateTime.utc_now()
    duration_seconds = DateTime.diff(current_time, state.start_time)

    stats = %{
      processed_count: state.processed_count,
      error_count: state.error_count,
      success_rate: calculate_success_rate(state),
      throughput_per_hour: calculate_throughput(state, duration_seconds),
      duration_seconds: duration_seconds,
      active_aggregations: map_size(state.partial_aggregations),
      subscriber_count: length(state.subscribers),
      deduplication_cache_size: map_size(state.deduplication_cache)
    }

    {:reply, stats, [], state}
  end

  @impl GenStage
  def handle_call(:flush_results, _from, state) do
    Logger.info("Manually flushing result buffer")

    # Force database write of any buffered results
    flush_result =
      if Enum.empty?(state.result_buffer) do
        {:ok, 0}
      else
        stream_results_to_database_batched(state.result_buffer)
      end

    # Clear buffer and update state
    updated_state = %{state | result_buffer: []}

    {:reply, flush_result, [], updated_state}
  end

  @impl GenStage
  def handle_info(:progress_broadcast_timer, state) do
    updated_state = broadcast_progress(state)
    schedule_progress_broadcast()
    {:noreply, [], updated_state}
  end

  @impl GenStage
  def handle_info(:cleanup_deduplication_cache, state) do
    cleaned_cache = cleanup_old_cache_entries(state.deduplication_cache)
    schedule_cache_cleanup()
    {:noreply, [], %{state | deduplication_cache: cleaned_cache}}
  end

  # Private implementation functions

  defp process_events_streaming(events, state) do
    {updated_state, processed_results} =
      Enum.reduce(events, {state, []}, fn event, {acc_state, acc_results} ->
        case process_single_event(event, acc_state) do
          {:ok, result, new_state} ->
            {new_state, [result | acc_results]}

          {:error, reason, new_state} ->
            Logger.warning("Failed to process event: #{inspect(reason)}")
            error_state = %{new_state | error_count: new_state.error_count + 1}
            {error_state, acc_results}

          {:duplicate, new_state} ->
            Logger.debug("Duplicate result detected and skipped")
            {new_state, acc_results}
        end
      end)

    {updated_state, Enum.reverse(processed_results)}
  end

  defp process_single_event(event, state) do
    # Check for duplicates using deduplication cache
    result_id = generate_result_id(event)

    if Map.has_key?(state.deduplication_cache, result_id) do
      {:duplicate, state}
    else
      # Process new result
      case transform_event_to_result(event) do
        {:ok, result} ->
          # Add to deduplication cache
          updated_cache = Map.put(state.deduplication_cache, result_id, DateTime.utc_now())

          updated_state = %{
            state
            | deduplication_cache: updated_cache,
              processed_count: state.processed_count + 1
          }

          {:ok, result, updated_state}

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  defp generate_result_id(event) do
    # Generate unique ID for result deduplication
    id_components = [
      Map.get(event, :task_id),
      Map.get(event, :repository),
      Map.get(event, :commit_hash),
      Map.get(event, :analysis_type)
    ]

    :erlang.phash2(id_components)
  end

  defp transform_event_to_result(event) do
    # Transform pipeline event into database-ready result
    result = %{
      task_id: Map.get(event, :task_id),
      repository: Map.get(event, :repository),
      commit_hash: Map.get(event, :commit_hash),
      analysis_type: Map.get(event, :analysis_type, :complete),
      evaluation_result: Map.get(event, :evaluation_result, %{}),
      metadata: %{
        processed_at: DateTime.utc_now(),
        pipeline_stage: "result_streamer",
        processing_time_ms: Map.get(event, :processing_time_ms, 0),
        memory_used_bytes: Map.get(event, :memory_used_bytes, 0)
      },
      scores: extract_scores_from_event(event),
      quality_metrics: extract_quality_metrics_from_event(event)
    }

    {:ok, result}
  rescue
    error ->
      {:error, {:transformation_failed, error}}
  end

  defp extract_scores_from_event(event) do
    evaluation_result = Map.get(event, :evaluation_result, %{})

    %{
      overall_score: get_in(evaluation_result, [:scores, :overall]) || 0.0,
      pattern_analysis_score: get_in(evaluation_result, [:scores, :pattern_analysis]) || 0.0,
      functional_analysis_score:
        get_in(evaluation_result, [:scores, :functional_analysis]) || 0.0,
      static_analysis_score: get_in(evaluation_result, [:scores, :static_analysis]) || 0.0,
      otp_compliance_score: get_in(evaluation_result, [:scores, :otp_compliance]) || 0.0,
      tier: calculate_score_tier(get_in(evaluation_result, [:scores, :overall]) || 0.0),
      percentage:
        calculate_score_percentage(get_in(evaluation_result, [:scores, :overall]) || 0.0)
    }
  end

  defp extract_quality_metrics_from_event(event) do
    evaluation_result = Map.get(event, :evaluation_result, %{})

    %{
      cyclomatic_complexity: get_in(evaluation_result, [:quality_metrics, :complexity]) || 0,
      test_coverage_percentage:
        get_in(evaluation_result, [:quality_metrics, :test_coverage]) || 0.0,
      documentation_coverage:
        get_in(evaluation_result, [:quality_metrics, :documentation]) || 0.0,
      warning_count: get_in(evaluation_result, [:quality_metrics, :warnings]) || 0,
      error_count: get_in(evaluation_result, [:quality_metrics, :errors]) || 0
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

  defp stream_results_to_database(results) do
    if Enum.empty?(results) do
      {:ok, 0}
    else
      # Insert results directly to database without buffering
      inserted_count =
        Repo.insert_all("evaluation_results", results,
          on_conflict: :replace_all,
          conflict_target: [:task_id, :repository, :commit_hash]
        )

      Logger.debug("Streamed #{length(results)} results to database")
      {:ok, inserted_count}
    end
  rescue
    error ->
      Logger.error("Failed to stream results to database: #{inspect(error)}")
      {:error, {:database_insert_failed, error}}
  end

  defp update_partial_aggregations(results, state) do
    # Update running aggregations without storing full result sets
    updated_aggregations =
      results
      |> Enum.reduce(state.partial_aggregations, fn result, acc ->
        repo = result.repository

        repo_agg = Map.get(acc, repo, create_empty_aggregation())
        updated_agg = update_repository_aggregation(repo_agg, result)

        Map.put(acc, repo, updated_agg)
      end)

    %{state | partial_aggregations: updated_aggregations}
  end

  defp create_empty_aggregation do
    %{
      total_tasks: 0,
      total_score: 0.0,
      score_distribution: %{tier_0: 0, tier_1: 0, tier_2: 0, tier_3: 0, tier_4: 0},
      processing_time_sum: 0,
      memory_usage_sum: 0,
      last_updated: DateTime.utc_now()
    }
  end

  defp update_repository_aggregation(aggregation, result) do
    tier_key = "tier_#{result.scores.tier}" |> String.to_atom()

    %{
      aggregation
      | total_tasks: aggregation.total_tasks + 1,
        total_score: aggregation.total_score + result.scores.overall_score,
        score_distribution: Map.update(aggregation.score_distribution, tier_key, 1, &(&1 + 1)),
        processing_time_sum:
          aggregation.processing_time_sum + (result.metadata.processing_time_ms || 0),
        memory_usage_sum: aggregation.memory_usage_sum + (result.metadata.memory_used_bytes || 0),
        last_updated: DateTime.utc_now()
    }
  end

  defp maybe_broadcast_progress(state) do
    current_time = DateTime.utc_now()
    time_since_last = DateTime.diff(current_time, state.last_progress_broadcast, :millisecond)

    if time_since_last >= @progress_broadcast_interval do
      broadcast_progress(state)
    else
      state
    end
  end

  defp send_progress_to_live_subscriber(subscriber_pid, progress_data) do
    if Process.alive?(subscriber_pid) do
      send(subscriber_pid, {:evaluation_progress, progress_data})
    end
  end

  defp broadcast_progress(state) do
    if not Enum.empty?(state.subscribers) do
      progress_data = create_progress_data(state)

      # Send progress to all subscribers
      Enum.each(state.subscribers, &send_progress_to_live_subscriber(&1, progress_data))

      Logger.debug("Broadcasted progress to #{length(state.subscribers)} subscribers")
    end

    %{state | last_progress_broadcast: DateTime.utc_now()}
  end

  defp create_progress_data(state) do
    current_time = DateTime.utc_now()
    duration_seconds = DateTime.diff(current_time, state.start_time)

    %{
      processed_count: state.processed_count,
      error_count: state.error_count,
      success_rate: calculate_success_rate(state),
      throughput_per_hour: calculate_throughput(state, duration_seconds),
      duration_seconds: duration_seconds,
      repository_summaries: create_repository_summaries(state.partial_aggregations),
      timestamp: current_time
    }
  end

  defp create_repository_summaries(partial_aggregations) do
    partial_aggregations
    |> Enum.map(fn {repository, aggregation} ->
      average_score =
        if aggregation.total_tasks > 0 do
          aggregation.total_score / aggregation.total_tasks
        else
          0.0
        end

      average_processing_time =
        if aggregation.total_tasks > 0 do
          aggregation.processing_time_sum / aggregation.total_tasks
        else
          0.0
        end

      {repository,
       %{
         total_tasks: aggregation.total_tasks,
         average_score: Float.round(average_score, 3),
         average_processing_time_ms: round(average_processing_time),
         score_distribution: aggregation.score_distribution,
         last_updated: aggregation.last_updated
       }}
    end)
    |> Map.new()
  end

  defp calculate_success_rate(state) do
    total_processed = state.processed_count + state.error_count

    if total_processed > 0 do
      state.processed_count / total_processed
    else
      1.0
    end
  end

  defp calculate_throughput(state, duration_seconds) do
    if duration_seconds > 0 do
      # Per hour
      state.processed_count / duration_seconds * 3600
    else
      0.0
    end
  end

  defp cleanup_old_cache_entries(deduplication_cache) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@deduplication_window, :millisecond)

    deduplication_cache
    |> Enum.reject(fn {_id, timestamp} ->
      DateTime.compare(timestamp, cutoff_time) == :lt
    end)
    |> Map.new()
  end

  defp schedule_progress_broadcast do
    Process.send_after(self(), :progress_broadcast_timer, @progress_broadcast_interval)
  end

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_deduplication_cache, @deduplication_window)
  end

  # Database streaming functions

  @doc """
  Streams results directly to the database in batches for efficiency.
  """
  defp stream_results_to_database_batched(results) when is_list(results) do
    if Enum.empty?(results) do
      {:ok, 0}
    else
      # Prepare results for database insertion
      db_records = Enum.map(results, &prepare_result_for_db/1)

      # Stream insert in chunks to avoid memory buildup
      chunk_size = 50

      total_inserted =
        db_records
        |> Enum.chunk_every(chunk_size)
        |> Enum.reduce(0, fn chunk, acc ->
          {inserted_count, _} =
            Repo.insert_all("evaluation_results", chunk,
              on_conflict: :replace_all,
              conflict_target: [:task_id, :repository, :commit_hash],
              # Don't return inserted records to save memory
              returning: false
            )

          acc + inserted_count
        end)

      Logger.debug("Streamed #{total_inserted} results to database")
      {:ok, total_inserted}
    end
  rescue
    error ->
      Logger.error("Database streaming failed: #{inspect(error)}")
      {:error, {:database_streaming_failed, error}}
  end

  defp prepare_result_for_db(result) do
    # Convert result to database-compatible format
    %{
      task_id: result.task_id,
      repository: result.repository,
      commit_hash: result.commit_hash,
      analysis_type: to_string(result.analysis_type),
      overall_score: result.scores.overall_score,
      pattern_analysis_score: result.scores.pattern_analysis_score,
      functional_analysis_score: result.scores.functional_analysis_score,
      static_analysis_score: result.scores.static_analysis_score,
      otp_compliance_score: result.scores.otp_compliance_score,
      tier: result.scores.tier,
      percentage: result.scores.percentage,
      processing_time_ms: result.metadata.processing_time_ms,
      memory_used_bytes: result.metadata.memory_used_bytes,
      quality_metrics: Jason.encode!(result.quality_metrics),
      evaluation_result: Jason.encode!(result.evaluation_result),
      processed_at: result.metadata.processed_at,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # Real-time aggregation functions

  @doc """
  Creates real-time aggregated views without storing full datasets.
  """
  def create_real_time_aggregation(repository, time_window_minutes \\ 60) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window_minutes * 60, :second)

    # Query database for recent results (streaming-friendly query)
    query = """
    SELECT
      repository,
      COUNT(*) as total_tasks,
      AVG(overall_score) as average_score,
      AVG(processing_time_ms) as average_processing_time,
      SUM(CASE WHEN tier = 0 THEN 1 ELSE 0 END) as tier_0_count,
      SUM(CASE WHEN tier = 1 THEN 1 ELSE 0 END) as tier_1_count,
      SUM(CASE WHEN tier = 2 THEN 1 ELSE 0 END) as tier_2_count,
      SUM(CASE WHEN tier = 3 THEN 1 ELSE 0 END) as tier_3_count,
      SUM(CASE WHEN tier = 4 THEN 1 ELSE 0 END) as tier_4_count
    FROM evaluation_results
    WHERE repository = $1 AND processed_at >= $2
    GROUP BY repository
    """

    case Repo.query(query, [repository, cutoff_time]) do
      {:ok, %{rows: []}} ->
        {:ok, create_empty_aggregation()}

      {:ok, %{rows: [row]}} ->
        aggregation = build_aggregation_from_row(row, time_window_minutes)
        {:ok, aggregation}

      {:error, reason} ->
        Logger.error("Failed to create real-time aggregation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_aggregation_from_row(row, time_window_minutes) do
    [_repo, total, avg_score, avg_time, t0, t1, t2, t3, t4] = row

    %{
      total_tasks: total || 0,
      average_score: Float.round(avg_score || 0.0, 3),
      average_processing_time_ms: round(avg_time || 0.0),
      score_distribution: %{
        tier_0: t0 || 0,
        tier_1: t1 || 0,
        tier_2: t2 || 0,
        tier_3: t3 || 0,
        tier_4: t4 || 0
      },
      time_window_minutes: time_window_minutes,
      last_updated: DateTime.utc_now()
    }
  end

  @doc """
  Handles out-of-order result arrival by maintaining insertion order timestamps.
  """
  def handle_out_of_order_result(result, expected_sequence_number) do
    actual_sequence = Map.get(result.metadata, :sequence_number)

    case actual_sequence do
      ^expected_sequence_number ->
        # In order - process normally
        {:ok, :in_order, result}

      seq when is_integer(seq) and seq < expected_sequence_number ->
        # Late arrival - check if already processed
        result_id = generate_result_id(result)

        case check_result_already_processed(result_id) do
          true ->
            Logger.debug("Late result already processed, skipping")
            {:ok, :duplicate, result}

          false ->
            Logger.debug("Processing late result with sequence #{seq}")
            {:ok, :late_arrival, result}
        end

      seq when is_integer(seq) and seq > expected_sequence_number ->
        # Early arrival - buffer for proper ordering
        Logger.debug("Early result arrival, sequence #{seq} > #{expected_sequence_number}")
        {:ok, :early_arrival, result}

      _ ->
        # No sequence number or invalid - process as normal
        {:ok, :no_sequence, result}
    end
  end

  defp check_result_already_processed(result_id) do
    # Check if result was already processed and stored
    query = "SELECT 1 FROM evaluation_results WHERE result_id = $1 LIMIT 1"

    case Repo.query(query, [result_id]) do
      {:ok, %{rows: []}} -> false
      {:ok, %{rows: [_]}} -> true
      # Assume not processed if query fails
      {:error, _} -> false
    end
  end
end
