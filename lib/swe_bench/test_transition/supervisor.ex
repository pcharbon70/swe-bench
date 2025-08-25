defmodule SweBench.TestTransition.Supervisor do
  @moduledoc """
  OTP supervision tree for test transition validation infrastructure.

  Manages validation coordinators, workers, transition analyzers, and result
  aggregation with proper fault tolerance and container resource management.
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
      # Validation coordination
      {SweBench.TestTransition.Coordinator, [max_workers: max_workers]},

      # Dynamic supervisor for validation workers
      {DynamicSupervisor,
       name: SweBench.TestTransition.WorkerSupervisor, strategy: :one_for_one},

      # Core validation components
      {SweBench.TestTransition.TransitionAnalyzer, []},
      {SweBench.TestTransition.DeterminismChecker, []},
      {SweBench.TestTransition.QualityAssessor, []},

      # Result aggregation and reporting
      {SweBench.TestTransition.ResultAggregator, []},
      {SweBench.TestTransition.ValidationReporter, []},

      # Caching for validation results
      {SweBench.TestTransition.ValidationCache, []}
    ]

    # Add monitoring if enabled
    children =
      if enable_monitoring do
        [{SweBench.TestTransition.Monitor, []} | children]
      else
        children
      end

    Logger.info("Starting test transition validation infrastructure with #{max_workers} max workers")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Gets test transition validation infrastructure health status.
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
      validation_components: health_status,
      total_components: length(children),
      healthy_components: Enum.count(health_status, fn {_id, status} -> status == :healthy end)
    }
  end

  @doc """
  Gracefully shuts down test transition validation operations.
  """
  def graceful_shutdown do
    Logger.info("Initiating graceful test transition validation infrastructure shutdown")

    # Stop coordinators first to prevent new work
    case GenServer.whereis(SweBench.TestTransition.Coordinator) do
      pid when is_pid(pid) ->
        GenServer.stop(pid, :shutdown, 10_000)

      nil ->
        :ok
    end

    # Stop any active validation workers
    DynamicSupervisor.which_children(SweBench.TestTransition.WorkerSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(SweBench.TestTransition.WorkerSupervisor, pid)
    end)

    Logger.info("Test transition validation infrastructure shutdown complete")
    :ok
  end
end