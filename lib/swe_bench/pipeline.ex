defmodule SweBench.Pipeline do
  @moduledoc """
  Main interface for GenStage evaluation pipeline.

  Coordinates high-throughput task evaluation with backpressure control,
  fault tolerance, and performance monitoring.
  """

  require Logger

  alias SweBench.Pipeline.{
    ContainerEvaluator,
    PatchFetcher,
    ResultAnalyzer,
    Supervisor,
    TaskProducer
  }

  @doc """
  Starts the complete evaluation pipeline.
  """
  def start_pipeline(opts \\ []) do
    Logger.info("Starting SWE-bench evaluation pipeline")

    case Supervisor.start_link(opts) do
      {:ok, supervisor_pid} ->
        Logger.info("Pipeline started successfully")
        {:ok, supervisor_pid}

      {:error, reason} ->
        Logger.error("Failed to start pipeline: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops the evaluation pipeline gracefully.
  """
  def stop_pipeline do
    Logger.info("Stopping evaluation pipeline")

    Supervisor.graceful_shutdown()
  end

  @doc """
  Gets comprehensive pipeline status and performance metrics.
  """
  def get_pipeline_status do
    Logger.debug("Collecting pipeline status")

    with {:ok, health} <- safe_get_health(),
         {:ok, producer_stats} <- safe_get_stats(TaskProducer),
         {:ok, fetcher_stats} <- safe_get_stats(PatchFetcher),
         {:ok, evaluator_stats} <- safe_get_stats(ContainerEvaluator),
         {:ok, analyzer_stats} <- safe_get_stats(ResultAnalyzer) do
      status = %{
        pipeline_health: health,
        throughput_metrics: calculate_throughput_metrics(producer_stats, evaluator_stats),
        stage_statistics: %{
          task_producer: producer_stats,
          patch_fetcher: fetcher_stats,
          container_evaluator: evaluator_stats,
          result_analyzer: analyzer_stats
        },
        overall_status: determine_overall_status(health),
        status_timestamp: DateTime.utc_now()
      }

      {:ok, status}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Monitors pipeline performance and alerts on issues.
  """
  def monitor_pipeline_performance(opts \\ []) do
    interval = Keyword.get(opts, :interval, 30_000)

    Logger.info("Starting pipeline performance monitoring (interval: #{interval}ms)")

    monitor_ref =
      spawn(fn ->
        monitor_loop(interval)
      end)

    {:ok, monitor_ref}
  end

  @doc """
  Gets current pipeline throughput metrics.
  """
  def get_throughput_metrics do
    case get_pipeline_status() do
      {:ok, status} -> {:ok, status.throughput_metrics}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Triggers pipeline health check and recovery if needed.
  """
  def health_check_and_recover do
    Logger.debug("Performing pipeline health check")

    case Supervisor.get_pipeline_health() do
      %{healthy_stages: healthy, total_stages: total} when healthy < total ->
        Logger.warning("Pipeline health issue: #{healthy}/#{total} stages healthy")
        attempt_pipeline_recovery()

      %{healthy_stages: healthy, total_stages: total} ->
        Logger.debug("Pipeline healthy: #{healthy}/#{total} stages running")
        {:ok, :healthy}
    end
  end

  # Private helper functions

  defp safe_get_health do
    health = Supervisor.get_pipeline_health()
    {:ok, health}
  catch
    _, reason ->
      Logger.error("Failed to get pipeline health: #{inspect(reason)}")
      {:error, {:health_check_failed, reason}}
  end

  defp safe_get_stats(stage_module) do
    stats = stage_module.get_stats()
    {:ok, stats}
  catch
    _, reason ->
      Logger.warning("Failed to get stats for #{stage_module}: #{inspect(reason)}")
      {:ok, %{error: reason, stage: stage_module}}
  end

  defp calculate_throughput_metrics(producer_stats, evaluator_stats) do
    # Calculate throughput based on producer and evaluator statistics
    %{
      tasks_pending: producer_stats.buffered_tasks || 0,
      evaluations_active: evaluator_stats.active_evaluations || 0,
      available_capacity: evaluator_stats.available_capacity || 0,
      estimated_throughput_per_hour: estimate_hourly_throughput(evaluator_stats),
      bottleneck_stage: identify_bottleneck_stage(producer_stats, evaluator_stats)
    }
  end

  defp estimate_hourly_throughput(evaluator_stats) do
    active = evaluator_stats.active_evaluations || 0
    max_concurrent = evaluator_stats.max_concurrent || 12

    # Assume 2 minutes average per evaluation
    estimated_evaluations_per_hour = max_concurrent * 30

    if active > 0 do
      estimated_evaluations_per_hour
    else
      0
    end
  end

  defp identify_bottleneck_stage(producer_stats, evaluator_stats) do
    cond do
      producer_stats.buffered_tasks == 0 -> :task_producer
      evaluator_stats.available_capacity == 0 -> :container_evaluator
      true -> :none
    end
  end

  defp determine_overall_status(health) do
    healthy_ratio = health.healthy_stages / health.total_stages

    cond do
      healthy_ratio == 1.0 -> :healthy
      healthy_ratio >= 0.75 -> :degraded
      true -> :unhealthy
    end
  end

  defp monitor_loop(interval) do
    case get_pipeline_status() do
      {:ok, status} ->
        log_performance_metrics(status)
        check_performance_thresholds(status)

      {:error, reason} ->
        Logger.error("Pipeline monitoring failed: #{inspect(reason)}")
    end

    :timer.sleep(interval)
    monitor_loop(interval)
  end

  defp log_performance_metrics(status) do
    metrics = status.throughput_metrics

    Logger.info([
      "Pipeline Performance: ",
      "throughput=#{metrics.estimated_throughput_per_hour}/hour, ",
      "active=#{metrics.evaluations_active}, ",
      "pending=#{metrics.tasks_pending}, ",
      "status=#{status.overall_status}"
    ])
  end

  defp check_performance_thresholds(status) do
    metrics = status.throughput_metrics

    # Alert on performance issues
    cond do
      metrics.estimated_throughput_per_hour < 100 ->
        Logger.warning("Low throughput detected: #{metrics.estimated_throughput_per_hour}/hour")

      metrics.tasks_pending > 100 ->
        Logger.warning("High task backlog: #{metrics.tasks_pending} pending")

      status.overall_status == :unhealthy ->
        Logger.error("Pipeline unhealthy - initiating recovery")
        health_check_and_recover()

      true ->
        :ok
    end
  end

  defp attempt_pipeline_recovery do
    Logger.info("Attempting pipeline recovery")

    # Get detailed health information
    health = Supervisor.get_pipeline_health()

    # Restart unhealthy stages
    unhealthy_stages =
      Enum.filter(health.pipeline_stages, fn {_id, status} ->
        status == :unhealthy
      end)

    Enum.each(unhealthy_stages, fn {stage_id, _status} ->
      Logger.info("Restarting unhealthy stage: #{stage_id}")
      Supervisor.restart_stage(stage_id)
    end)

    {:ok, :recovery_attempted}
  end
end
