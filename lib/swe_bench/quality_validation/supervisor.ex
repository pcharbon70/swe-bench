defmodule SweBench.QualityValidation.Supervisor do
  @moduledoc """
  OTP supervision tree for quality validation infrastructure.

  Manages quality validation coordinators, statistical analyzers, deduplication
  systems, review managers, and monitoring with proper fault tolerance.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online())
    enable_monitoring = Keyword.get(opts, :monitoring, true)

    children = [
      # Quality validation coordination
      {SweBench.QualityValidation.Coordinator, [max_workers: max_workers]},

      # Dynamic supervisor for validation workers
      {DynamicSupervisor,
       name: SweBench.QualityValidation.WorkerSupervisor, strategy: :one_for_one},

      # Core validation components
      {SweBench.QualityValidation.AutomatedValidator, []},
      {SweBench.QualityValidation.StatisticalAnalyzer, []},
      {SweBench.QualityValidation.DeduplicationSystem, []},

      # Human review management
      {SweBench.QualityValidation.ReviewManager, []},

      # Quality metrics and monitoring
      {SweBench.QualityValidation.QualityMetrics, []},
      {SweBench.QualityValidation.QualityCache, []},

      # Result aggregation and reporting
      {SweBench.QualityValidation.ResultAggregator, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.QualityValidation.Monitor, []} | children]
      else
        children
      end

    Logger.info("Starting quality validation infrastructure with #{max_workers} max workers")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets quality validation infrastructure health status.
  """
  def health_check do
    children = Supervisor.which_children(__MODULE__)

    health_status =
      Enum.map(children, fn {id, pid, _type, _modules} ->
        case Process.alive?(pid) do
          true -> {id, :healthy}
          false -> {id, :unhealthy}
        end
      end)

    %{
      quality_validation_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Gracefully shuts down quality validation operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful quality validation infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.QualityValidation.Coordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active validation workers
    DynamicSupervisor.which_children(SweBench.QualityValidation.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.QualityValidation.WorkerSupervisor, pid)
    end)

    Logger.info("Quality validation infrastructure shutdown complete")
    :ok
  end
end
