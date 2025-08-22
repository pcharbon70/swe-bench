defmodule SweBench.Pipeline.Supervisor do
  @moduledoc """
  Pipeline supervisor with restart strategies and circuit breakers.

  Manages GenStage pipeline supervision tree with health monitoring,
  graceful shutdown, and fault tolerance.
  """

  use Supervisor
  require Logger

  alias SweBench.Pipeline.{ContainerEvaluator, PatchFetcher, ResultAnalyzer, TaskProducer}

  @doc """
  Starts the pipeline supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets pipeline health status.
  """
  def get_pipeline_health do
    children = Supervisor.which_children(__MODULE__)

    health_status =
      Enum.map(children, fn {id, pid, _type, _modules} ->
        if Process.alive?(pid) do
          {id, :healthy}
        else
          {id, :unhealthy}
        end
      end)

    %{
      pipeline_stages: health_status,
      total_stages: length(children),
      healthy_stages: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Initiates graceful pipeline shutdown.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful pipeline shutdown")

    # Stop stages in reverse order
    stages = [ResultAnalyzer, ContainerEvaluator, PatchFetcher, TaskProducer]

    Enum.each(stages, fn stage ->
      try do
        GenStage.stop(stage, :shutdown)
        Logger.debug("Gracefully stopped #{stage}")
      catch
        _, reason ->
          Logger.warning("Failed to gracefully stop #{stage}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Restarts a specific pipeline stage.
  """
  def restart_stage(stage_id) do
    Logger.info("Restarting pipeline stage: #{stage_id}")

    case Supervisor.terminate_child(__MODULE__, stage_id) do
      :ok ->
        case Supervisor.restart_child(__MODULE__, stage_id) do
          {:ok, _pid} ->
            Logger.info("Successfully restarted #{stage_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to restart #{stage_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to terminate #{stage_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Supervisor callbacks

  @impl Supervisor
  def init(opts) do
    # Pipeline configuration
    batch_size = Keyword.get(opts, :batch_size, 10)
    max_workers = Keyword.get(opts, :max_workers, 5)
    max_evaluations = Keyword.get(opts, :max_concurrent_evaluations, 12)
    parallel_analyzers = Keyword.get(opts, :parallel_analyzers, 6)

    children = [
      # Task Producer (starts the pipeline)
      {TaskProducer, [batch_size: batch_size, repository_grouping: true]},

      # Patch Fetcher workers (ProducerConsumer)
      {PatchFetcher,
       [
         name: :patch_fetcher_1,
         max_workers: max_workers,
         cache_enabled: true,
         subscribe_to: [TaskProducer]
       ]},

      # Container Evaluator workers (ConsumerProducer)
      {ContainerEvaluator,
       [
         name: :container_evaluator_1,
         max_concurrent_evaluations: max_evaluations,
         evaluation_timeout: 300_000,
         subscribe_to: [:patch_fetcher_1]
       ]},

      # Result Analyzer (Consumer)
      {ResultAnalyzer,
       [
         name: :result_analyzer_1,
         parallel_workers: parallel_analyzers,
         enable_notifications: true,
         subscribe_to: [:container_evaluator_1]
       ]}
    ]

    # Configure supervision strategy
    opts = [
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 60
    ]

    Logger.info("Starting pipeline with #{length(children)} stages")

    Supervisor.init(children, opts)
  end
end
