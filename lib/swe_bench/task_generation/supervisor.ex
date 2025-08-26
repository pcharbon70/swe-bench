defmodule SweBench.TaskGeneration.Supervisor do
  @moduledoc """
  OTP supervision tree for task instance generation infrastructure.

  Manages generation coordinators, workers, enrichment processors, and dataset
  packaging with proper fault tolerance and resource management.
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
      # Generation coordination
      {SweBench.TaskGeneration.Coordinator, [max_workers: max_workers]},

      # Dynamic supervisor for generation workers
      {DynamicSupervisor, name: SweBench.TaskGeneration.WorkerSupervisor, strategy: :one_for_one},

      # Core generation components
      {SweBench.TaskGeneration.Generator, []},
      {SweBench.TaskGeneration.Enricher, []},
      {SweBench.TaskGeneration.ComplexityAnalyzer, []},

      # Format compliance and quality validation
      {SweBench.TaskGeneration.Formatter, []},
      {SweBench.TaskGeneration.QualityValidator, []},

      # Dataset packaging and release management
      {SweBench.TaskGeneration.Packager, []},

      # Result aggregation and reporting
      {SweBench.TaskGeneration.ResultAggregator, []},

      # Caching for generation results
      {SweBench.TaskGeneration.GenerationCache, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.TaskGeneration.Monitor, []} | children]
      else
        children
      end

    Logger.info(
      "Starting task instance generation infrastructure with #{max_workers} max workers"
    )

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets task generation infrastructure health status.
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
      generation_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Gracefully shuts down task generation operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful task generation infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.TaskGeneration.Coordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active generation workers
    DynamicSupervisor.which_children(SweBench.TaskGeneration.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.TaskGeneration.WorkerSupervisor, pid)
    end)

    Logger.info("Task generation infrastructure shutdown complete")
    :ok
  end
end
