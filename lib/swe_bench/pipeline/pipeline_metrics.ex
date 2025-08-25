defmodule SweBench.Pipeline.PipelineMetrics do
  @moduledoc """
  Comprehensive metrics collection and performance monitoring for the parallel evaluation pipeline.

  Tracks stage processing times, monitors queue depths and backpressure,
  calculates throughput per repository, measures resource efficiency,
  and generates detailed performance reports.
  """

  use GenServer
  require Logger

  # 5 seconds
  @metrics_collection_interval 5_000
  # 1 minute
  @performance_report_interval 60_000
  # Keep 24 hours of metrics
  @metrics_retention_hours 24
  # Warn if queue > 100 items
  @queue_depth_warning_threshold 100

  defstruct [
    :start_time,
    :stage_metrics,
    :throughput_metrics,
    :resource_metrics,
    :performance_history,
    :subscribers,
    :collection_timer,
    :report_timer
  ]

  @type stage_metrics :: %{
          stage_name: atom(),
          processing_times: [non_neg_integer()],
          queue_depth: non_neg_integer(),
          backpressure_events: non_neg_integer(),
          throughput_per_minute: float(),
          error_count: non_neg_integer(),
          last_updated: DateTime.t()
        }

  @type throughput_metrics :: %{
          repository: String.t(),
          tasks_completed: non_neg_integer(),
          tasks_per_hour: float(),
          average_processing_time: float(),
          success_rate: float(),
          last_task_completed: DateTime.t()
        }

  # Public API

  @doc """
  Starts the pipeline metrics collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records metrics for a pipeline stage completion.
  """
  def record_stage_completion(stage_name, processing_time_ms, opts \\ []) do
    GenServer.cast(__MODULE__, {:stage_completion, stage_name, processing_time_ms, opts})
  end

  @doc """
  Records queue depth for a pipeline stage.
  """
  def record_queue_depth(stage_name, queue_depth) do
    GenServer.cast(__MODULE__, {:queue_depth, stage_name, queue_depth})
  end

  @doc """
  Records a backpressure event.
  """
  def record_backpressure_event(stage_name, severity \\ :normal) do
    GenServer.cast(__MODULE__, {:backpressure, stage_name, severity})
  end

  @doc """
  Records repository evaluation completion.
  """
  def record_repository_completion(repository, processing_time_ms, success?, opts \\ []) do
    GenServer.cast(
      __MODULE__,
      {:repository_completion, repository, processing_time_ms, success?, opts}
    )
  end

  @doc """
  Gets current pipeline metrics summary.
  """
  def get_current_metrics do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  @doc """
  Gets detailed performance report.
  """
  def get_performance_report(time_window_minutes \\ 60) do
    GenServer.call(__MODULE__, {:get_performance_report, time_window_minutes})
  end

  @doc """
  Subscribes to receive periodic performance reports.
  """
  def subscribe_to_reports(subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe_reports, subscriber_pid})
  end

  @doc """
  Resets all metrics (useful for testing or fresh evaluation runs).
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      start_time: DateTime.utc_now(),
      stage_metrics: %{},
      throughput_metrics: %{},
      resource_metrics: %{},
      performance_history: [],
      subscribers: [],
      collection_timer: nil,
      report_timer: nil
    }

    # Start periodic metrics collection
    collection_timer = schedule_metrics_collection()
    report_timer = schedule_performance_report()

    updated_state = %{state | collection_timer: collection_timer, report_timer: report_timer}

    Logger.info(
      "PipelineMetrics started with collection interval: #{@metrics_collection_interval}ms"
    )

    {:ok, updated_state}
  end

  @impl GenServer
  def handle_cast({:stage_completion, stage_name, processing_time_ms, opts}, state) do
    updated_metrics =
      update_stage_metrics(state.stage_metrics, stage_name, processing_time_ms, opts)

    {:noreply, %{state | stage_metrics: updated_metrics}}
  end

  @impl GenServer
  def handle_cast({:queue_depth, stage_name, queue_depth}, state) do
    updated_metrics = update_queue_depth_metrics(state.stage_metrics, stage_name, queue_depth)

    # Check for queue depth warnings
    if queue_depth > @queue_depth_warning_threshold do
      Logger.warning("High queue depth detected: #{stage_name} = #{queue_depth}")
    end

    {:noreply, %{state | stage_metrics: updated_metrics}}
  end

  @impl GenServer
  def handle_cast({:backpressure, stage_name, severity}, state) do
    updated_metrics = record_backpressure_event(state.stage_metrics, stage_name, severity)

    Logger.debug("Backpressure event recorded: #{stage_name} (#{severity})")
    {:noreply, %{state | stage_metrics: updated_metrics}}
  end

  @impl GenServer
  def handle_cast({:repository_completion, repository, processing_time_ms, success?, opts}, state) do
    updated_throughput =
      update_repository_throughput(
        state.throughput_metrics,
        repository,
        processing_time_ms,
        success?,
        opts
      )

    {:noreply, %{state | throughput_metrics: updated_throughput}}
  end

  @impl GenServer
  def handle_call(:get_current_metrics, _from, state) do
    metrics = compile_current_metrics(state)
    {:reply, metrics, state}
  end

  @impl GenServer
  def handle_call({:get_performance_report, time_window_minutes}, _from, state) do
    report = generate_performance_report(state, time_window_minutes)
    {:reply, report, state}
  end

  @impl GenServer
  def handle_call({:subscribe_reports, subscriber_pid}, _from, state) do
    updated_subscribers = [subscriber_pid | state.subscribers]
    Logger.debug("Added performance report subscriber: #{inspect(subscriber_pid)}")
    {:reply, :ok, %{state | subscribers: updated_subscribers}}
  end

  @impl GenServer
  def handle_call(:reset_metrics, _from, state) do
    reset_state = %{
      state
      | start_time: DateTime.utc_now(),
        stage_metrics: %{},
        throughput_metrics: %{},
        resource_metrics: %{},
        performance_history: []
    }

    Logger.info("Pipeline metrics reset")
    {:reply, :ok, reset_state}
  end

  @impl GenServer
  def handle_info(:collect_metrics, state) do
    updated_state = collect_system_metrics(state)
    schedule_metrics_collection()
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info(:generate_report, state) do
    updated_state = generate_and_broadcast_report(state)
    schedule_performance_report()
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp update_stage_metrics(stage_metrics, stage_name, processing_time_ms, opts) do
    current_time = DateTime.utc_now()

    stage_data =
      Map.get(stage_metrics, stage_name, %{
        stage_name: stage_name,
        processing_times: [],
        queue_depth: 0,
        backpressure_events: 0,
        throughput_per_minute: 0.0,
        error_count: 0,
        last_updated: current_time
      })

    # Update processing times (keep last 100 for rolling average)
    updated_times =
      [processing_time_ms | stage_data.processing_times]
      |> Enum.take(100)

    # Calculate throughput per minute
    # 1 minute
    time_window_ms = 60_000

    recent_times =
      Enum.filter(updated_times, fn time ->
        # Simplified recent check - in production would use actual timestamps
        # Approximate 1 minute of data
        length(updated_times) <= 60
      end)

    throughput = length(recent_times)

    # Handle errors if specified
    error_count =
      if Keyword.get(opts, :error, false) do
        stage_data.error_count + 1
      else
        stage_data.error_count
      end

    updated_stage_data = %{
      stage_data
      | processing_times: updated_times,
        throughput_per_minute: throughput,
        error_count: error_count,
        last_updated: current_time
    }

    Map.put(stage_metrics, stage_name, updated_stage_data)
  end

  defp update_queue_depth_metrics(stage_metrics, stage_name, queue_depth) do
    current_time = DateTime.utc_now()

    stage_data =
      Map.get(stage_metrics, stage_name, %{
        stage_name: stage_name,
        processing_times: [],
        queue_depth: 0,
        backpressure_events: 0,
        throughput_per_minute: 0.0,
        error_count: 0,
        last_updated: current_time
      })

    updated_stage_data = %{stage_data | queue_depth: queue_depth, last_updated: current_time}

    Map.put(stage_metrics, stage_name, updated_stage_data)
  end

  defp record_backpressure_event(stage_metrics, stage_name, severity) do
    current_time = DateTime.utc_now()

    stage_data =
      Map.get(stage_metrics, stage_name, %{
        stage_name: stage_name,
        processing_times: [],
        queue_depth: 0,
        backpressure_events: 0,
        throughput_per_minute: 0.0,
        error_count: 0,
        last_updated: current_time
      })

    # Weight backpressure events by severity
    event_weight =
      case severity do
        :critical -> 3
        :high -> 2
        :normal -> 1
        :low -> 0.5
      end

    updated_stage_data = %{
      stage_data
      | backpressure_events: stage_data.backpressure_events + event_weight,
        last_updated: current_time
    }

    Map.put(stage_metrics, stage_name, updated_stage_data)
  end

  defp update_repository_throughput(
         throughput_metrics,
         repository,
         processing_time_ms,
         success?,
         opts
       ) do
    current_time = DateTime.utc_now()

    repo_data =
      Map.get(throughput_metrics, repository, %{
        repository: repository,
        tasks_completed: 0,
        tasks_per_hour: 0.0,
        average_processing_time: 0.0,
        success_rate: 1.0,
        successful_tasks: 0,
        total_tasks: 0,
        processing_time_sum: 0,
        last_task_completed: current_time
      })

    # Update counters
    updated_repo_data = %{
      repo_data
      | tasks_completed: repo_data.tasks_completed + 1,
        total_tasks: repo_data.total_tasks + 1,
        successful_tasks:
          if(success?, do: repo_data.successful_tasks + 1, else: repo_data.successful_tasks),
        processing_time_sum: repo_data.processing_time_sum + processing_time_ms,
        last_task_completed: current_time
    }

    # Recalculate derived metrics
    final_repo_data = %{
      updated_repo_data
      | success_rate: updated_repo_data.successful_tasks / updated_repo_data.total_tasks,
        average_processing_time:
          updated_repo_data.processing_time_sum / updated_repo_data.total_tasks,
        tasks_per_hour: calculate_tasks_per_hour(updated_repo_data, current_time)
    }

    Map.put(throughput_metrics, repository, final_repo_data)
  end

  defp calculate_tasks_per_hour(repo_data, current_time) do
    # Calculate tasks per hour based on recent completion rate
    if repo_data.total_tasks > 0 and repo_data.average_processing_time > 0 do
      # Simple calculation: 3600 seconds / average processing time in seconds
      # Convert ms to seconds
      tasks_per_second = 1000 / repo_data.average_processing_time
      tasks_per_second * 3600
    else
      0.0
    end
  end

  defp collect_system_metrics(state) do
    current_time = DateTime.utc_now()

    # Collect comprehensive system metrics
    system_metrics = %{
      memory: collect_memory_metrics(),
      cpu: collect_cpu_metrics(),
      processes: collect_process_metrics(),
      pipeline: collect_pipeline_specific_metrics(),
      timestamp: current_time
    }

    # Update resource metrics with latest data
    updated_state = %{state | resource_metrics: system_metrics}

    # Check for performance alerts
    check_performance_alerts(system_metrics)

    updated_state
  end

  defp collect_memory_metrics do
    erlang_memory = :erlang.memory()
    system_memory = get_system_memory_info()

    %{
      erlang: %{
        total: erlang_memory[:total],
        processes: erlang_memory[:processes],
        atom: erlang_memory[:atom],
        binary: erlang_memory[:binary],
        ets: erlang_memory[:ets]
      },
      system: %{
        total: system_memory.total,
        used: system_memory.used,
        available: system_memory.total - system_memory.used,
        pressure: system_memory.used / system_memory.total
      }
    }
  end

  defp collect_cpu_metrics do
    schedulers = :erlang.system_info(:schedulers)
    scheduler_usage = get_scheduler_utilization()

    %{
      schedulers: schedulers,
      utilization: scheduler_usage,
      run_queue: :erlang.statistics(:run_queue),
      context_switches: :erlang.statistics(:context_switches),
      reductions: :erlang.statistics(:reductions)
    }
  end

  defp collect_process_metrics do
    %{
      total: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit),
      evaluation_processes: count_evaluation_processes(),
      pipeline_processes: count_pipeline_processes()
    }
  end

  defp collect_pipeline_specific_metrics do
    # Collect metrics specific to our evaluation pipeline
    %{
      active_batches: count_active_batches(),
      pending_tasks: count_pending_tasks(),
      container_pool_utilization: get_container_pool_utilization(),
      analysis_parallelization_factor: calculate_analysis_parallelization()
    }
  end

  defp get_system_memory_info do
    case :os.type() do
      {:unix, _} ->
        {output, 0} = System.cmd("free", ["-b"])
        parse_free_output(output)

      _ ->
        %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
    end
  rescue
    _ -> %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
  end

  defp parse_free_output(output) do
    lines = String.split(output, "\n")

    case Enum.find(lines, &String.starts_with?(&1, "Mem:")) do
      nil ->
        %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}

      mem_line ->
        parts = String.split(mem_line) |> Enum.drop(1)

        case parts do
          [total_str, used_str | _] ->
            %{
              total: String.to_integer(total_str),
              used: String.to_integer(used_str)
            }

          _ ->
            %{total: 8 * 1024 * 1024 * 1024, used: 4 * 1024 * 1024 * 1024}
        end
    end
  end

  defp get_scheduler_utilization do
    :erlang.system_flag(:scheduler_wall_time, true)
    # Short sample period for frequent collection
    Process.sleep(50)
    scheduler_usage = :erlang.statistics(:scheduler_wall_time)

    if is_list(scheduler_usage) and not Enum.empty?(scheduler_usage) do
      calculate_scheduler_utilization_average(scheduler_usage)
    else
      0.0
    end
  rescue
    _ -> 0.0
  end

  defp calculate_scheduler_utilization_average(scheduler_usage) do
    total_schedulers = length(scheduler_usage)

    total_utilization =
      scheduler_usage
      |> Enum.map(&calculate_scheduler_utilization_ratio/1)
      |> Enum.sum()

    total_utilization / total_schedulers
  end

  defp calculate_scheduler_utilization_ratio({_id, active, total}) do
    if total > 0, do: active / total, else: 0.0
  end

  defp count_evaluation_processes do
    # Count processes actively performing evaluation work
    processes = Process.list()

    Enum.count(processes, fn pid ->
      case Process.info(pid, [:current_function, :dictionary]) do
        [current_function: {module, _func, _arity}]
        when module in [
               SweBench.PatternAnalysis,
               SweBench.FunctionalAnalysis,
               SweBench.StaticAnalysis,
               SweBench.PatternAnalysis.AstParser,
               SweBench.StaticAnalysis.CredoAnalyzer,
               SweBench.StaticAnalysis.DialyzerIntegration
             ] ->
          true

        _ ->
          false
      end
    end)
  end

  defp count_pipeline_processes do
    # Count GenStage pipeline processes
    processes = Process.list()

    Enum.count(processes, fn pid ->
      case Process.info(pid, [:current_function]) do
        [current_function: {module, _func, _arity}]
        when module in [
               SweBench.Pipeline.TaskProducer,
               SweBench.Pipeline.ContainerEvaluator,
               SweBench.Pipeline.ResultAnalyzer,
               SweBench.Pipeline.ResultStreamer,
               SweBench.Pipeline.BatchOptimizer
             ] ->
          true

        _ ->
          false
      end
    end)
  end

  defp count_active_batches do
    # Count currently processing batches
    # In production, would track actual batch state
    case GenServer.call(SweBench.Pipeline.BatchOptimizer, :get_active_batches, 1000) do
      {:ok, batches} when is_list(batches) -> length(batches)
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp count_pending_tasks do
    # Count tasks waiting in pipeline queues
    case GenServer.call(SweBench.Pipeline.TaskProducer, :get_queue_size, 1000) do
      {:ok, queue_size} when is_integer(queue_size) -> queue_size
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp get_container_pool_utilization do
    # Get container pool utilization metrics
    case GenServer.call(SweBench.Container.Pool, :get_utilization, 1000) do
      {:ok, utilization} when is_number(utilization) -> utilization
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  defp calculate_analysis_parallelization do
    # Calculate current analysis parallelization factor
    evaluation_processes = count_evaluation_processes()
    pipeline_processes = count_pipeline_processes()

    if pipeline_processes > 0 do
      evaluation_processes / pipeline_processes
    else
      1.0
    end
  end

  defp compile_current_metrics(state) do
    current_time = DateTime.utc_now()
    duration_seconds = DateTime.diff(current_time, state.start_time)

    %{
      uptime_seconds: duration_seconds,
      stage_metrics: state.stage_metrics,
      throughput_metrics: state.throughput_metrics,
      resource_metrics: state.resource_metrics,
      performance_summary: %{
        total_stages: map_size(state.stage_metrics),
        total_repositories: map_size(state.throughput_metrics),
        overall_throughput: calculate_overall_throughput(state),
        average_processing_time: calculate_average_processing_time(state),
        success_rate: calculate_overall_success_rate(state)
      },
      timestamp: current_time
    }
  end

  defp calculate_overall_throughput(state) do
    if map_size(state.throughput_metrics) > 0 do
      total_tasks =
        state.throughput_metrics
        |> Map.values()
        |> Enum.map(& &1.tasks_completed)
        |> Enum.sum()

      duration_hours = DateTime.diff(DateTime.utc_now(), state.start_time) / 3600

      if duration_hours > 0 do
        total_tasks / duration_hours
      else
        0.0
      end
    else
      0.0
    end
  end

  defp calculate_average_processing_time(state) do
    if map_size(state.throughput_metrics) > 0 do
      processing_times =
        state.throughput_metrics
        |> Map.values()
        |> Enum.map(& &1.average_processing_time)
        |> Enum.filter(&(&1 > 0))

      if Enum.empty?(processing_times) do
        0.0
      else
        Enum.sum(processing_times) / length(processing_times)
      end
    else
      0.0
    end
  end

  defp calculate_overall_success_rate(state) do
    if map_size(state.throughput_metrics) > 0 do
      success_rates =
        state.throughput_metrics
        |> Map.values()
        |> Enum.map(& &1.success_rate)

      if Enum.empty?(success_rates) do
        1.0
      else
        Enum.sum(success_rates) / length(success_rates)
      end
    else
      1.0
    end
  end

  defp generate_performance_report(state, time_window_minutes) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window_minutes * 60, :second)

    # Filter metrics to time window
    filtered_history =
      Enum.filter(state.performance_history, fn entry ->
        DateTime.compare(entry.timestamp, cutoff_time) != :lt
      end)

    current_metrics = compile_current_metrics(state)

    %{
      report_type: :performance_report,
      time_window_minutes: time_window_minutes,
      generated_at: DateTime.utc_now(),
      current_metrics: current_metrics,
      historical_trends: analyze_historical_trends(filtered_history),
      performance_alerts: generate_performance_alerts(current_metrics),
      recommendations: generate_performance_recommendations(current_metrics)
    }
  end

  defp analyze_historical_trends(historical_data) do
    if length(historical_data) < 2 do
      %{insufficient_data: true}
    else
      # Analyze trends in throughput, processing time, success rate
      throughputs = Enum.map(historical_data, & &1.performance_summary.overall_throughput)

      processing_times =
        Enum.map(historical_data, & &1.performance_summary.average_processing_time)

      success_rates = Enum.map(historical_data, & &1.performance_summary.success_rate)

      %{
        throughput_trend: calculate_trend(throughputs),
        processing_time_trend: calculate_trend(processing_times),
        success_rate_trend: calculate_trend(success_rates),
        data_points: length(historical_data)
      }
    end
  end

  defp calculate_trend(values) when length(values) < 2, do: :stable

  defp calculate_trend(values) do
    first_half = Enum.take(values, div(length(values), 2))
    second_half = Enum.drop(values, div(length(values), 2))

    first_avg = Enum.sum(first_half) / length(first_half)
    second_avg = Enum.sum(second_half) / length(second_half)

    change_rate = (second_avg - first_avg) / first_avg

    cond do
      change_rate > 0.1 -> :improving
      change_rate < -0.1 -> :declining
      true -> :stable
    end
  end

  defp generate_performance_alerts(metrics) do
    alerts = []

    # Memory pressure alert
    memory_pressure = get_in(metrics, [:resource_metrics, :memory, :system, :pressure]) || 0.0

    alerts =
      if memory_pressure > 0.9 do
        [
          %{
            type: :memory_critical,
            message: "Critical memory pressure: #{Float.round(memory_pressure * 100, 1)}%"
          }
          | alerts
        ]
      else
        alerts
      end

    # CPU utilization alert
    cpu_utilization = get_in(metrics, [:resource_metrics, :cpu, :utilization]) || 0.0

    alerts =
      if cpu_utilization > 0.95 do
        [
          %{
            type: :cpu_critical,
            message: "Critical CPU utilization: #{Float.round(cpu_utilization * 100, 1)}%"
          }
          | alerts
        ]
      else
        alerts
      end

    # Queue depth alerts
    stage_alerts =
      metrics.stage_metrics
      |> Enum.filter(fn {_stage, data} -> data.queue_depth > @queue_depth_warning_threshold end)
      |> Enum.map(fn {stage, data} ->
        %{type: :queue_depth_high, message: "High queue depth in #{stage}: #{data.queue_depth}"}
      end)

    alerts ++ stage_alerts
  end

  defp generate_performance_recommendations(metrics) do
    throughput_recs = generate_throughput_recommendations(metrics)
    memory_recs = generate_memory_recommendations(metrics)
    reliability_recs = generate_reliability_recommendations(metrics)

    throughput_recs ++ memory_recs ++ reliability_recs
  end

  defp generate_throughput_recommendations(metrics) do
    overall_throughput = metrics.performance_summary.overall_throughput

    # Below 100 tasks/hour
    if overall_throughput < 100 do
      [
        %{
          type: :throughput_low,
          recommendation: "Consider increasing concurrency or optimizing bottleneck stages"
        }
      ]
    else
      []
    end
  end

  defp generate_memory_recommendations(metrics) do
    memory_pressure = get_in(metrics, [:resource_metrics, :memory, :system, :pressure]) || 0.0

    if memory_pressure > 0.8 do
      [
        %{
          type: :memory_optimization,
          recommendation:
            "Consider reducing batch sizes or enabling aggressive garbage collection"
        }
      ]
    else
      []
    end
  end

  defp generate_reliability_recommendations(metrics) do
    success_rate = metrics.performance_summary.success_rate

    if success_rate < 0.9 do
      [
        %{
          type: :reliability_improvement,
          recommendation: "Investigate error patterns and improve error handling"
        }
      ]
    else
      []
    end
  end

  defp broadcast_to_live_subscribers(subscribers, report) do
    Enum.each(subscribers, fn subscriber_pid ->
      if Process.alive?(subscriber_pid) do
        send(subscriber_pid, {:performance_report, report})
      end
    end)
  end

  defp generate_and_broadcast_report(state) do
    # 1 hour window
    report = generate_performance_report(state, 60)

    # Add to performance history
    updated_history =
      [report | state.performance_history]
      # Keep 144 reports (24 hours worth)
      |> Enum.take(144)

    # Broadcast to subscribers
    if Enum.empty?(state.subscribers) do
      :ok
    else
      broadcast_to_live_subscribers(state.subscribers, report)
      Logger.debug("Broadcasted performance report to #{length(state.subscribers)} subscribers")
    end

    %{state | performance_history: updated_history}
  end

  defp check_performance_alerts(metrics) do
    alerts = generate_performance_alerts(metrics)

    if not Enum.empty?(alerts) do
      Enum.each(alerts, fn alert ->
        Logger.warning("Performance Alert [#{alert.type}]: #{alert.message}")
      end)
    end
  end

  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, @metrics_collection_interval)
  end

  defp schedule_performance_report do
    Process.send_after(self(), :generate_report, @performance_report_interval)
  end

  # Utility functions for external integration

  @doc """
  Calculates real-time throughput for a specific time window.
  """
  def calculate_real_time_throughput(repository, time_window_minutes \\ 10) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -time_window_minutes * 60, :second)

    # Query recent completions from database
    query = """
    SELECT COUNT(*) as task_count
    FROM evaluation_results
    WHERE repository = $1 AND processed_at >= $2
    """

    case SweBench.Repo.query(query, [repository, cutoff_time]) do
      {:ok, %{rows: [[task_count]]}} ->
        tasks_per_hour = task_count / time_window_minutes * 60
        {:ok, tasks_per_hour}

      {:error, reason} ->
        Logger.error("Failed to calculate real-time throughput: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets resource efficiency metrics for current pipeline operation.
  """
  def get_resource_efficiency_metrics do
    GenServer.call(__MODULE__, :get_resource_efficiency)
  end

  @impl GenServer
  def handle_call(:get_resource_efficiency, _from, state) do
    current_metrics = state.resource_metrics

    efficiency_metrics = %{
      memory_efficiency: calculate_memory_efficiency(current_metrics),
      cpu_efficiency: calculate_cpu_efficiency(current_metrics),
      process_efficiency: calculate_process_efficiency(current_metrics),
      pipeline_efficiency: calculate_pipeline_efficiency(state),
      # Will be calculated
      overall_efficiency: 0.0
    }

    # Calculate overall efficiency as weighted average
    overall =
      efficiency_metrics.memory_efficiency * 0.3 +
        efficiency_metrics.cpu_efficiency * 0.3 +
        efficiency_metrics.process_efficiency * 0.2 +
        efficiency_metrics.pipeline_efficiency * 0.2

    final_metrics = %{efficiency_metrics | overall_efficiency: overall}

    {:reply, final_metrics, state}
  end

  defp calculate_memory_efficiency(metrics) do
    memory_pressure = get_in(metrics, [:memory, :system, :pressure]) || 0.0

    # Efficient range is 50-80% memory utilization
    cond do
      memory_pressure >= 0.5 and memory_pressure <= 0.8 -> 1.0
      # Underutilized
      memory_pressure < 0.5 -> 0.8
      # High but manageable
      memory_pressure <= 0.9 -> 0.7
      # Critical - inefficient
      true -> 0.3
    end
  end

  defp calculate_cpu_efficiency(metrics) do
    cpu_utilization = get_in(metrics, [:cpu, :utilization]) || 0.0

    # Efficient range is 60-90% CPU utilization
    cond do
      cpu_utilization >= 0.6 and cpu_utilization <= 0.9 -> 1.0
      # Underutilized
      cpu_utilization < 0.6 -> 0.8
      # High but manageable
      cpu_utilization <= 0.95 -> 0.7
      # Critical - inefficient
      true -> 0.4
    end
  end

  defp calculate_process_efficiency(metrics) do
    total_processes = get_in(metrics, [:processes, :total]) || 0
    evaluation_processes = get_in(metrics, [:processes, :evaluation_processes]) || 0

    if total_processes > 0 and evaluation_processes > 0 do
      efficiency_ratio = evaluation_processes / total_processes
      calculate_efficiency_from_ratio(efficiency_ratio)
    else
      # Unknown efficiency
      0.5
    end
  end

  defp calculate_efficiency_from_ratio(efficiency_ratio) do
    cond do
      # Good efficiency
      efficiency_ratio >= 0.1 and efficiency_ratio <= 0.5 -> 1.0
      # Underutilized
      efficiency_ratio < 0.1 -> 0.6
      # High utilization
      efficiency_ratio <= 0.7 -> 0.8
      # Too many evaluation processes
      true -> 0.5
    end
  end

  defp calculate_pipeline_efficiency(state) do
    # Calculate pipeline-specific efficiency metrics
    if map_size(state.stage_metrics) > 0 do
      stage_efficiencies =
        state.stage_metrics
        |> Map.values()
        |> Enum.map(&calculate_stage_efficiency/1)

      if Enum.empty?(stage_efficiencies) do
        0.5
      else
        Enum.sum(stage_efficiencies) / length(stage_efficiencies)
      end
    else
      0.5
    end
  end

  defp calculate_stage_efficiency(stage_data) do
    # Calculate efficiency for individual pipeline stage
    # 10 tasks/min = 100% efficiency
    throughput_score = min(stage_data.throughput_per_minute / 10.0, 1.0)
    queue_score = if stage_data.queue_depth < 50, do: 1.0, else: 0.5

    error_score =
      if stage_data.error_count == 0, do: 1.0, else: max(0.3, 1.0 - stage_data.error_count * 0.1)

    throughput_score * 0.5 + queue_score * 0.3 + error_score * 0.2
  end
end
