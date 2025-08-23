defmodule SweBench.PatternAnalysis.OTP.ProcessMetrics do
  @moduledoc """
  Collects and analyzes process metrics for OTP applications.

  Monitors process spawning rates, message queue depths, supervisor restarts,
  process memory usage, and detects process leaks and zombie processes.
  """

  require Logger

  alias SweBench.PatternAnalysis.OTP.ValidationSchemas

  # 5 seconds
  @default_monitoring_duration 5_000
  # MB per process threshold for efficiency
  @memory_efficiency_threshold 10.0

  @doc """
  Collects comprehensive process metrics for a module/application.

  ## Parameters
    - module_info: Parsed module information (used for context)
    - opts: Collection options including duration and sampling rate

  ## Returns
    - {:ok, process_metrics()} - Successful metrics collection result
    - {:error, reason} - Collection error
  """
  def collect_process_metrics(_module_info, opts \\ []) do
    Logger.debug("Starting process metrics collection")

    monitoring_duration = Keyword.get(opts, :duration, @default_monitoring_duration)
    include_detailed_analysis = Keyword.get(opts, :detailed, true)

    metrics_result = ValidationSchemas.new_process_metrics()

    with {:ok, initial_snapshot} <- take_process_snapshot(),
         {:ok, monitored_metrics} <- monitor_process_activity(monitoring_duration),
         {:ok, final_snapshot} <- take_process_snapshot(),
         {:ok, analyzed_metrics} <-
           analyze_process_metrics(
             initial_snapshot,
             monitored_metrics,
             final_snapshot,
             include_detailed_analysis
           ) do
      efficiency_score = calculate_memory_efficiency_score(analyzed_metrics)

      final_result = %{
        metrics_result
        | spawn_rate: analyzed_metrics.spawn_rate,
          avg_message_queue_depth: analyzed_metrics.avg_message_queue_depth,
          restart_count: analyzed_metrics.restart_count,
          memory_efficiency_score: efficiency_score,
          process_count: analyzed_metrics.final_process_count,
          zombie_processes: analyzed_metrics.zombie_processes,
          memory_usage_mb: analyzed_metrics.total_memory_mb,
          collected_at: DateTime.utc_now()
      }

      Logger.debug(
        "Process metrics collection complete: #{analyzed_metrics.final_process_count} processes analyzed"
      )

      {:ok, final_result}
    else
      {:error, reason} ->
        Logger.warning("Process metrics collection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.2.4.1: Monitor process spawning rates
  defp take_process_snapshot do
    processes = Process.list()

    process_info =
      processes
      |> Enum.map(fn pid ->
        case Process.info(pid, [
               :registered_name,
               :message_queue_len,
               :memory,
               :status,
               :initial_call
             ]) do
          # Process died during collection
          nil ->
            nil

          info ->
            %{
              pid: pid,
              registered_name: Keyword.get(info, :registered_name),
              message_queue_len: Keyword.get(info, :message_queue_len, 0),
              memory: Keyword.get(info, :memory, 0),
              status: Keyword.get(info, :status, :unknown),
              initial_call: Keyword.get(info, :initial_call)
            }
        end
      end)
      |> Enum.reject(&is_nil/1)

    snapshot = %{
      timestamp: System.monotonic_time(:millisecond),
      process_count: length(process_info),
      processes: process_info,
      total_memory: Enum.sum(Enum.map(process_info, & &1.memory)),
      avg_message_queue_depth: calculate_average_queue_depth(process_info)
    }

    {:ok, snapshot}
  rescue
    error ->
      {:error, {:snapshot_failed, error}}
  end

  defp calculate_average_queue_depth(process_info) do
    if length(process_info) > 0 do
      total_queue_len = Enum.sum(Enum.map(process_info, & &1.message_queue_len))
      total_queue_len / length(process_info)
    else
      0.0
    end
  end

  defp monitor_process_activity(duration_ms) do
    Logger.debug("Monitoring process activity for #{duration_ms}ms")

    # Start monitoring
    start_time = System.monotonic_time(:millisecond)

    # Sample process activity over time
    # Sample every 1 second
    samples = collect_activity_samples(duration_ms, 1000)

    end_time = System.monotonic_time(:millisecond)
    actual_duration = end_time - start_time

    monitored_metrics = %{
      start_time: start_time,
      end_time: end_time,
      actual_duration_ms: actual_duration,
      samples: samples,
      spawn_events: count_spawn_events(samples),
      process_exits: count_process_exits(samples)
    }

    {:ok, monitored_metrics}
  end

  defp collect_activity_samples(total_duration_ms, sample_interval_ms) do
    sample_count = max(1, div(total_duration_ms, sample_interval_ms))

    1..sample_count
    |> Enum.map(fn sample_num ->
      :timer.sleep(sample_interval_ms)

      case take_process_snapshot() do
        {:ok, snapshot} ->
          %{
            sample_number: sample_num,
            timestamp: snapshot.timestamp,
            process_count: snapshot.process_count,
            total_memory: snapshot.total_memory,
            avg_queue_depth: snapshot.avg_message_queue_depth
          }

        {:error, _reason} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp count_spawn_events(samples) do
    # Calculate spawning rate from process count changes
    if length(samples) < 2 do
      0
    else
      process_counts = Enum.map(samples, & &1.process_count)

      increases =
        process_counts
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] -> max(0, curr - prev) end)
        |> Enum.sum()

      increases
    end
  end

  defp count_process_exits(samples) do
    # Calculate exit rate from process count decreases
    if length(samples) < 2 do
      0
    else
      process_counts = Enum.map(samples, & &1.process_count)

      decreases =
        process_counts
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] -> max(0, prev - curr) end)
        |> Enum.sum()

      decreases
    end
  end

  # Task 2.2.4.2: Track message queue depths
  # Task 2.2.4.3: Count supervisor restarts
  # Task 2.2.4.4: Measure process memory usage
  defp analyze_process_metrics(initial_snapshot, monitored_metrics, final_snapshot, detailed) do
    duration_seconds = monitored_metrics.actual_duration_ms / 1000.0

    # Calculate spawn rate (processes per second)
    spawn_rate =
      if duration_seconds > 0 do
        monitored_metrics.spawn_events / duration_seconds
      else
        0.0
      end

    # Calculate average message queue depth
    avg_message_queue_depth =
      if length(monitored_metrics.samples) > 0 do
        total_avg_depth = Enum.sum(Enum.map(monitored_metrics.samples, & &1.avg_queue_depth))
        total_avg_depth / length(monitored_metrics.samples)
      else
        final_snapshot.avg_message_queue_depth
      end

    # Detect potential zombie processes
    zombie_count = count_zombie_processes(final_snapshot.processes)

    # Calculate memory metrics
    # Convert to MB
    total_memory_mb = final_snapshot.total_memory / (1024 * 1024)

    analyzed_metrics = %{
      spawn_rate: spawn_rate,
      avg_message_queue_depth: avg_message_queue_depth,
      restart_count: estimate_restart_count(monitored_metrics),
      final_process_count: final_snapshot.process_count,
      zombie_processes: zombie_count,
      total_memory_mb: total_memory_mb,
      memory_per_process_mb: total_memory_mb / max(1, final_snapshot.process_count),
      process_count_delta: final_snapshot.process_count - initial_snapshot.process_count
    }

    if detailed do
      detailed_metrics =
        add_detailed_analysis(analyzed_metrics, monitored_metrics, final_snapshot)

      {:ok, detailed_metrics}
    else
      {:ok, analyzed_metrics}
    end
  end

  defp estimate_restart_count(monitored_metrics) do
    # Estimate restarts from spawn/exit patterns
    # This is a rough estimate - accurate restart counting would require supervisor monitoring
    spawn_exits_difference = abs(monitored_metrics.spawn_events - monitored_metrics.process_exits)

    # Assume restarts if there's significant spawn/exit activity
    if spawn_exits_difference > 5 do
      # Rough estimate
      div(spawn_exits_difference, 2)
    else
      0
    end
  end

  # Task 2.2.4.5: Detect process leaks and zombies
  defp count_zombie_processes(processes) do
    # Identify potential zombie processes - processes with high message queue or stuck status
    zombie_criteria = fn process ->
      # More than 50MB
      process.message_queue_len > 1000 or
        process.status == :waiting or
        process.memory > 50 * 1024 * 1024
    end

    Enum.count(processes, zombie_criteria)
  end

  defp add_detailed_analysis(base_metrics, monitored_metrics, final_snapshot) do
    detailed_info = %{
      memory_distribution: analyze_memory_distribution(final_snapshot.processes),
      queue_depth_distribution: analyze_queue_depth_distribution(final_snapshot.processes),
      process_types: categorize_process_types(final_snapshot.processes),
      monitoring_samples: length(monitored_metrics.samples),
      peak_memory_usage: calculate_peak_memory(monitored_metrics.samples),
      memory_trend: calculate_memory_trend(monitored_metrics.samples)
    }

    Map.merge(base_metrics, detailed_info)
  end

  defp analyze_memory_distribution(processes) do
    memory_mb = Enum.map(processes, fn p -> p.memory / (1024 * 1024) end)

    %{
      min: Enum.min(memory_mb, fn -> 0 end),
      max: Enum.max(memory_mb, fn -> 0 end),
      median: calculate_median(memory_mb),
      processes_over_threshold: Enum.count(memory_mb, &(&1 > @memory_efficiency_threshold))
    }
  end

  defp analyze_queue_depth_distribution(processes) do
    queue_depths = Enum.map(processes, & &1.message_queue_len)

    %{
      min: Enum.min(queue_depths, fn -> 0 end),
      max: Enum.max(queue_depths, fn -> 0 end),
      median: calculate_median(queue_depths),
      processes_with_backlog: Enum.count(queue_depths, &(&1 > 10))
    }
  end

  defp categorize_process_types(processes) do
    categories =
      processes
      |> Enum.group_by(fn process ->
        case process.initial_call do
          {:supervisor, :init, 1} -> :supervisor
          {:gen_server, :init_it, _} -> :gen_server
          {module, :start_link, _} when is_atom(module) -> :worker
          _ -> :other
        end
      end)

    Enum.into(categories, %{}, fn {category, procs} -> {category, length(procs)} end)
  end

  defp calculate_peak_memory(samples) do
    if length(samples) > 0 do
      Enum.max(Enum.map(samples, & &1.total_memory)) / (1024 * 1024)
    else
      0.0
    end
  end

  defp calculate_memory_trend(samples) do
    if length(samples) < 2 do
      :stable
    else
      first_memory = List.first(samples).total_memory
      last_memory = List.last(samples).total_memory

      change_percent = abs(last_memory - first_memory) / first_memory * 100

      cond do
        change_percent < 5 -> :stable
        last_memory > first_memory -> :increasing
        true -> :decreasing
      end
    end
  end

  defp calculate_median([]), do: 0

  defp calculate_median(values) do
    sorted = Enum.sort(values)
    length = length(sorted)

    if rem(length, 2) == 0 do
      # Even number of elements
      mid1 = Enum.at(sorted, div(length, 2) - 1)
      mid2 = Enum.at(sorted, div(length, 2))
      (mid1 + mid2) / 2
    else
      # Odd number of elements
      Enum.at(sorted, div(length, 2))
    end
  end

  defp calculate_memory_efficiency_score(metrics) do
    base_score = 100

    # Penalize high memory usage per process
    memory_penalty =
      if metrics.memory_per_process_mb > @memory_efficiency_threshold do
        min(30, (metrics.memory_per_process_mb - @memory_efficiency_threshold) * 2)
      else
        0
      end

    # Penalize zombie processes
    zombie_penalty = min(20, metrics.zombie_processes * 5)

    # Penalize high message queue depths
    queue_penalty =
      if metrics.avg_message_queue_depth > 50 do
        min(25, (metrics.avg_message_queue_depth - 50) / 10)
      else
        0
      end

    final_score = base_score - memory_penalty - zombie_penalty - queue_penalty
    max(0, round(final_score))
  end

  @doc """
  Generates detailed recommendations for process optimization.
  """
  def generate_recommendations(process_metrics) do
    recommendations = []

    # Memory efficiency recommendations
    recommendations =
      if process_metrics.memory_efficiency_score < 70 do
        [
          "Review process memory usage - current efficiency score: #{process_metrics.memory_efficiency_score}"
          | recommendations
        ]
      else
        recommendations
      end

    # Zombie process recommendations
    recommendations =
      if process_metrics.zombie_processes > 0 do
        [
          "Investigate #{process_metrics.zombie_processes} potential zombie processes"
          | recommendations
        ]
      else
        recommendations
      end

    # Message queue recommendations
    recommendations =
      if process_metrics.avg_message_queue_depth > 100 do
        [
          "High average message queue depth (#{process_metrics.avg_message_queue_depth}) - check for backpressure"
          | recommendations
        ]
      else
        recommendations
      end

    # Spawn rate recommendations
    recommendations =
      if process_metrics.spawn_rate > 50 do
        [
          "High process spawn rate (#{process_metrics.spawn_rate}/s) - consider process pooling"
          | recommendations
        ]
      else
        recommendations
      end

    # Restart count recommendations
    recommendations =
      if process_metrics.restart_count > 5 do
        [
          "High restart count (#{process_metrics.restart_count}) - investigate supervisor restart reasons"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Process metrics indicate healthy OTP application performance"]
    else
      recommendations
    end
  end

  @doc """
  Analyzes process health trends over time.
  """
  def analyze_health_trends(process_metrics) do
    health_indicators = %{
      memory_health: classify_memory_health(process_metrics),
      queue_health: classify_queue_health(process_metrics),
      spawn_health: classify_spawn_health(process_metrics),
      overall_health: :unknown
    }

    overall_health = determine_overall_health(health_indicators)

    %{health_indicators | overall_health: overall_health}
  end

  defp classify_memory_health(metrics) do
    cond do
      metrics.memory_efficiency_score >= 90 -> :excellent
      metrics.memory_efficiency_score >= 75 -> :good
      metrics.memory_efficiency_score >= 60 -> :fair
      metrics.memory_efficiency_score >= 40 -> :poor
      true -> :critical
    end
  end

  defp classify_queue_health(metrics) do
    cond do
      metrics.avg_message_queue_depth <= 10 -> :excellent
      metrics.avg_message_queue_depth <= 50 -> :good
      metrics.avg_message_queue_depth <= 100 -> :fair
      metrics.avg_message_queue_depth <= 500 -> :poor
      true -> :critical
    end
  end

  defp classify_spawn_health(metrics) do
    cond do
      metrics.spawn_rate <= 5 -> :excellent
      metrics.spawn_rate <= 20 -> :good
      metrics.spawn_rate <= 50 -> :fair
      metrics.spawn_rate <= 100 -> :poor
      true -> :critical
    end
  end

  defp determine_overall_health(health_indicators) do
    health_values = Map.values(health_indicators) |> Enum.reject(&(&1 == :unknown))

    cond do
      :critical in health_values -> :critical
      :poor in health_values -> :poor
      :fair in health_values -> :fair
      :good in health_values and :excellent not in health_values -> :good
      true -> :excellent
    end
  end
end
