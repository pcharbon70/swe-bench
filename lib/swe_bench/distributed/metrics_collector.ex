defmodule SweBench.Distributed.MetricsCollector do
  @moduledoc """
  Collects distributed system metrics across cluster nodes.

  Monitors inter-node communication, cluster performance, and distributed
  test execution metrics with integration to existing telemetry infrastructure.
  """

  use GenServer
  require Logger

  defstruct [
    :cluster_metrics,
    :node_metrics,
    :performance_history,
    :collection_config
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cluster-wide performance metrics.
  """
  def get_cluster_metrics(cluster_id \\ nil) do
    GenServer.call(__MODULE__, {:get_cluster_metrics, cluster_id})
  end

  @doc """
  Records a distributed system event for metrics collection.
  """
  def record_distributed_event(event_type, measurements, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_event, event_type, measurements, metadata})
  end

  @doc """
  Gets distributed performance statistics.
  """
  def get_performance_stats do
    GenServer.call(__MODULE__, :get_performance_stats)
  end

  @impl true
  def init(opts) do
    # Attach to distributed telemetry events
    setup_telemetry_handlers()

    state = %__MODULE__{
      cluster_metrics: %{},
      node_metrics: %{},
      performance_history: [],
      collection_config: build_collection_config(opts)
    }

    # Start periodic metrics collection
    schedule_metrics_collection()

    Logger.info("Distributed metrics collector started")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_cluster_metrics, cluster_id}, _from, state) do
    cluster_metrics =
      case cluster_id do
        nil -> aggregate_all_cluster_metrics(state.cluster_metrics)
        id -> Map.get(state.cluster_metrics, id, %{})
      end

    {:reply, cluster_metrics, state}
  end

  @impl true
  def handle_call(:get_performance_stats, _from, state) do
    stats = %{
      cluster_metrics: state.cluster_metrics,
      node_metrics: state.node_metrics,
      performance_summary: summarize_performance_history(state.performance_history),
      collection_health: assess_collection_health(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_event, event_type, measurements, metadata}, state) do
    event_record = %{
      type: event_type,
      measurements: measurements,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      node: Node.self()
    }

    # Update metrics based on event type
    updated_state = update_metrics_for_event(state, event_record)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    Logger.debug("Collecting distributed system metrics")

    # Collect current metrics from all nodes
    current_metrics = collect_cluster_wide_metrics()

    updated_state = %{
      state
      | cluster_metrics: merge_cluster_metrics(state.cluster_metrics, current_metrics),
        performance_history: [current_metrics | Enum.take(state.performance_history, 99)]
    }

    schedule_metrics_collection()
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp setup_telemetry_handlers do
    events = [
      [:swe_bench, :distributed, :message_sent],
      [:swe_bench, :distributed, :message_received],
      [:swe_bench, :distributed, :node_connected],
      [:swe_bench, :distributed, :node_disconnected],
      [:swe_bench, :distributed, :test_coordinated],
      [:swe_bench, :distributed, :barrier_synchronized]
    ]

    :telemetry.attach_many(
      "distributed-metrics-collector",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end

  def handle_telemetry_event(
        [:swe_bench, :distributed, :message_sent],
        measurements,
        metadata,
        _config
      ) do
    record_distributed_event(:message_sent, measurements, metadata)
  end

  def handle_telemetry_event(
        [:swe_bench, :distributed, :test_coordinated],
        measurements,
        metadata,
        _config
      ) do
    record_distributed_event(:test_coordinated, measurements, metadata)
  end

  def handle_telemetry_event(_event, _measurements, _metadata, _config) do
    # Handle other telemetry events as needed
    :ok
  end

  defp build_collection_config(opts) do
    %{
      collection_interval_ms: Keyword.get(opts, :collection_interval, 30_000),
      metrics_retention_count: Keyword.get(opts, :retention_count, 100),
      cluster_monitoring: Keyword.get(opts, :cluster_monitoring, true),
      performance_tracking: Keyword.get(opts, :performance_tracking, true)
    }
  end

  defp collect_cluster_wide_metrics do
    # Collect metrics from local node and all connected nodes
    local_metrics = collect_local_node_metrics()

    cluster_metrics =
      Node.list()
      |> Enum.map(&collect_remote_node_metrics/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, metrics} -> metrics end)

    %{
      timestamp: DateTime.utc_now(),
      local_node: local_metrics,
      cluster_nodes: cluster_metrics,
      cluster_summary: summarize_cluster_metrics(local_metrics, cluster_metrics)
    }
  end

  defp collect_local_node_metrics do
    %{
      node: Node.self(),
      memory_usage: :erlang.memory(:total),
      process_count: length(Process.list()),
      message_queue_lengths: get_message_queue_stats(),
      erlang_distribution_stats: get_distribution_stats()
    }
  end

  defp collect_remote_node_metrics(node) do
    remote_metrics = :rpc.call(node, __MODULE__, :collect_local_node_metrics, [], 5000)
    {:ok, remote_metrics}
  catch
    :exit, {:timeout, _} ->
      Logger.warning("Timeout collecting metrics from node: #{node}")
      {:error, :timeout}

    :exit, {:nodedown, _} ->
      Logger.warning("Node down while collecting metrics: #{node}")
      {:error, :nodedown}
  end

  defp get_message_queue_stats do
    # Placeholder for message queue statistics
    %{avg_queue_length: 0, max_queue_length: 0}
  end

  defp get_distribution_stats do
    # Placeholder for Erlang distribution statistics
    %{connections: length(Node.list()), distribution_active: true}
  end

  defp merge_cluster_metrics(existing_metrics, new_metrics) do
    cluster_id = Map.get(new_metrics, :cluster_id, :default)
    Map.put(existing_metrics, cluster_id, new_metrics)
  end

  defp summarize_cluster_metrics(local_metrics, cluster_metrics) do
    all_metrics = [local_metrics | cluster_metrics]

    %{
      total_nodes: length(all_metrics),
      total_memory_mb: calculate_total_memory(all_metrics),
      total_processes: calculate_total_processes(all_metrics),
      avg_message_queue_length: calculate_avg_queue_length(all_metrics)
    }
  end

  defp calculate_total_memory(metrics_list) do
    metrics_list
    |> Enum.map(&Map.get(&1, :memory_usage, 0))
    |> Enum.sum()
    # Convert to MB
    |> Kernel./(1024 * 1024)
  end

  defp calculate_total_processes(metrics_list) do
    metrics_list
    |> Enum.map(&Map.get(&1, :process_count, 0))
    |> Enum.sum()
  end

  defp calculate_avg_queue_length(metrics_list) do
    queue_lengths =
      metrics_list
      |> Enum.map(&get_in(&1, [:message_queue_lengths, :avg_queue_length]))
      |> Enum.filter(&(&1 != nil))

    if Enum.empty?(queue_lengths) do
      0.0
    else
      Enum.sum(queue_lengths) / length(queue_lengths)
    end
  end

  defp summarize_performance_history(history) do
    if Enum.empty?(history) do
      %{no_data: true}
    else
      recent_metrics = Enum.take(history, 10)

      %{
        data_points: length(recent_metrics),
        avg_cluster_size: calculate_avg_cluster_size(recent_metrics),
        memory_trend: calculate_memory_trend(recent_metrics),
        # Placeholder
        performance_trend: :stable
      }
    end
  end

  defp calculate_avg_cluster_size(metrics_history) do
    metrics_history
    |> Enum.map(&get_in(&1, [:cluster_summary, :total_nodes]))
    |> Enum.filter(&(&1 != nil))
    |> case do
      [] -> 1.0
      sizes -> Enum.sum(sizes) / length(sizes)
    end
  end

  defp calculate_memory_trend(metrics_history) do
    memory_values =
      metrics_history
      |> Enum.map(&get_in(&1, [:cluster_summary, :total_memory_mb]))
      |> Enum.filter(&(&1 != nil))

    case memory_values do
      [_single] -> :stable
      [latest, previous | _] when latest > previous * 1.1 -> :increasing
      [latest, previous | _] when latest < previous * 0.9 -> :decreasing
      _ -> :stable
    end
  end

  defp aggregate_all_cluster_metrics(cluster_metrics_map) do
    cluster_metrics_map
    |> Map.values()
    |> Enum.reduce(%{}, &merge_metric_maps/2)
  end

  defp merge_metric_maps(metrics1, metrics2) do
    Map.merge(metrics1, metrics2, fn _key, _val1, val2 ->
      # Simple merge strategy - could be enhanced
      val2
    end)
  end

  defp update_metrics_for_event(state, event_record) do
    # Update relevant metrics based on event type
    case event_record.type do
      :message_sent ->
        update_communication_metrics(state, event_record)

      :test_coordinated ->
        update_test_coordination_metrics(state, event_record)

      _ ->
        state
    end
  end

  defp update_communication_metrics(state, _event_record) do
    # Placeholder for communication metrics update
    state
  end

  defp update_test_coordination_metrics(state, _event_record) do
    # Placeholder for test coordination metrics update
    state
  end

  defp assess_collection_health(state) do
    recent_collections = Enum.take(state.performance_history, 5)

    %{
      collection_active: length(recent_collections) > 0,
      collection_frequency: calculate_collection_frequency(recent_collections),
      data_freshness: calculate_data_freshness(recent_collections)
    }
  end

  defp calculate_collection_frequency(collections) do
    if length(collections) < 2 do
      :insufficient_data
    else
      # Calculate average time between collections
      # Placeholder
      :normal
    end
  end

  defp calculate_data_freshness(collections) do
    case List.first(collections) do
      nil ->
        :no_data

      latest ->
        age_seconds = DateTime.diff(DateTime.utc_now(), latest.timestamp)
        if age_seconds < 60, do: :fresh, else: :stale
    end
  end

  defp schedule_metrics_collection do
    # Collect metrics every 30 seconds
    Process.send_after(self(), :collect_metrics, 30_000)
  end
end
