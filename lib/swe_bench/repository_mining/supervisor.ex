defmodule SweBench.RepositoryMining.Supervisor do
  @moduledoc """
  OTP supervision tree for repository mining infrastructure.

  Manages the mining coordinator, workers, rate limiters, and result aggregation
  with proper fault tolerance and recovery strategies.
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
      # Rate limiters for external APIs
      {SweBench.RepositoryMining.HexRateLimiter, []},
      {SweBench.RepositoryMining.GitHubRateLimiter, []},

      # Mining coordination
      {SweBench.RepositoryMining.Coordinator, [max_workers: max_workers]},

      # Dynamic supervisor for mining workers
      {DynamicSupervisor,
       name: SweBench.RepositoryMining.WorkerSupervisor, strategy: :one_for_one},

      # Result aggregation and quality processing
      {SweBench.RepositoryMining.ResultAggregator, []},

      # Quality scoring pipeline
      {SweBench.RepositoryMining.QualityPipeline, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.RepositoryMining.Monitor, []} | children]
      else
        children
      end

    Logger.info("Starting repository mining infrastructure with #{max_workers} max workers")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets mining infrastructure health status.
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
      mining_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Gracefully shuts down mining operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful mining infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.RepositoryMining.Coordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active workers
    DynamicSupervisor.which_children(SweBench.RepositoryMining.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.RepositoryMining.WorkerSupervisor, pid)
    end)

    Logger.info("Mining infrastructure shutdown complete")
    :ok
  end
end
