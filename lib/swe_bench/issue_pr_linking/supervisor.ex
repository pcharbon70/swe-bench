defmodule SweBench.IssuePrLinking.Supervisor do
  @moduledoc """
  OTP supervision tree for Issue-PR linking infrastructure.

  Manages correlation coordinators, analysis workers, validation pipeline,
  and result aggregation with proper fault tolerance and recovery.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online() * 2)
    enable_monitoring = Keyword.get(opts, :monitoring, true)

    children = [
      # Reuse existing GitHub rate limiter from Phase 3.1
      # SweBench.RepositoryMining.GitHubRateLimiter is already running

      # Issue-PR correlation coordination
      {SweBench.IssuePrLinking.Coordinator, [max_workers: max_workers]},

      # Dynamic supervisor for correlation workers
      {DynamicSupervisor,
       name: SweBench.IssuePrLinking.WorkerSupervisor, strategy: :one_for_one},

      # Analysis pipeline components
      {SweBench.IssuePrLinking.AnalysisPipeline, []},

      # Validation and quality assurance
      {SweBench.IssuePrLinking.ValidationPipeline, []},

      # Result aggregation and reporting
      {SweBench.IssuePrLinking.ResultAggregator, []},

      # Caching for correlation results
      {SweBench.IssuePrLinking.Cache, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.IssuePrLinking.Monitor, []} | children]
      else
        children
      end

    Logger.info("Starting Issue-PR linking infrastructure with #{max_workers} max workers")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets Issue-PR linking infrastructure health status.
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
      linking_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Gracefully shuts down Issue-PR linking operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful Issue-PR linking infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.IssuePrLinking.Coordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active workers
    DynamicSupervisor.which_children(SweBench.IssuePrLinking.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.IssuePrLinking.WorkerSupervisor, pid)
    end)

    Logger.info("Issue-PR linking infrastructure shutdown complete")
    :ok
  end
end