defmodule SweBench.Monitoring.MetricsCollector do
  @moduledoc """
  Comprehensive metrics collection and aggregation system.

  Extends existing Phoenix Telemetry with custom business metrics,
  evaluation pipeline monitoring, and production observability.
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :metric_registry,
    :aggregation_data,
    :collection_stats
  ]

  @custom_metrics [
    # Evaluation pipeline metrics
    :evaluations_submitted_total,
    :evaluations_completed_total,
    :evaluations_failed_total,
    :evaluation_duration_seconds,
    :evaluation_queue_depth,

    # Model performance metrics
    :model_evaluation_score,
    :model_evaluation_count,
    :repository_evaluation_count,
    :complexity_distribution,

    # System resource metrics
    :container_pool_size,
    :container_utilization_percent,
    :memory_usage_bytes,
    :cpu_usage_percent,

    # User activity metrics
    :active_sessions_count,
    :user_actions_total,
    :admin_actions_total,
    :public_views_total,

    # Real-time event metrics
    :pubsub_events_published_total,
    :pubsub_events_delivered_total,
    :websocket_connections_active,
    :websocket_messages_sent_total
  ]

  @doc """
  Starts the metrics collector with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Records a custom metric event.
  """
  def record_metric(metric_name, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_metric, metric_name, value, metadata})
  end

  @doc """
  Increments a counter metric.
  """
  def increment_counter(metric_name, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:increment_counter, metric_name, metadata})
  end

  @doc """
  Records an evaluation event metric.
  """
  def record_evaluation_metric(event_type, evaluation_data) do
    GenServer.cast(__MODULE__, {:record_evaluation_metric, event_type, evaluation_data})
  end

  @doc """
  Records system resource metrics.
  """
  def record_system_metrics(resource_data) do
    GenServer.cast(__MODULE__, {:record_system_metrics, resource_data})
  end

  @doc """
  Returns current metrics summary.
  """
  def get_metrics_summary do
    GenServer.call(__MODULE__, :get_metrics_summary)
  end

  @doc """
  Returns metrics for Prometheus export.
  """
  def get_prometheus_metrics do
    GenServer.call(__MODULE__, :get_prometheus_metrics)
  end

  @impl true
  def init(config) do
    metrics_config = build_metrics_config(config)

    # Initialize telemetry handlers
    setup_telemetry_handlers()

    state = %__MODULE__{
      config: metrics_config,
      metric_registry: initialize_metric_registry(),
      aggregation_data: %{},
      collection_stats: initialize_collection_stats()
    }

    # Schedule periodic metric collection
    schedule_metric_collection()

    Logger.info("Monitoring.MetricsCollector initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_metric, metric_name, value, metadata}, state) do
    # Record custom metric
    updated_registry = update_metric_registry(state.metric_registry, metric_name, value, metadata)

    # Emit telemetry event for external collectors
    :telemetry.execute([:swe_bench, :monitoring, :custom_metric], %{value: value}, %{
      metric_name: metric_name,
      metadata: metadata
    })

    new_state = %{state | metric_registry: updated_registry}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:increment_counter, metric_name, metadata}, state) do
    # Increment counter metric
    updated_registry = increment_metric_counter(state.metric_registry, metric_name, metadata)

    # Emit telemetry event
    :telemetry.execute([:swe_bench, :monitoring, :counter], %{count: 1}, %{
      metric_name: metric_name,
      metadata: metadata
    })

    new_state = %{state | metric_registry: updated_registry}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_evaluation_metric, event_type, evaluation_data}, state) do
    # Record evaluation-specific metrics
    metrics_to_record =
      case event_type do
        :evaluation_submitted ->
          [
            {:evaluations_submitted_total, 1,
             %{model: evaluation_data.model, repository: evaluation_data.repository}},
            {:evaluation_queue_depth, get_current_queue_depth(), %{}}
          ]

        :evaluation_completed ->
          [
            {:evaluations_completed_total, 1,
             %{model: evaluation_data.model, repository: evaluation_data.repository}},
            {:model_evaluation_score, evaluation_data.score, %{model: evaluation_data.model}},
            {:evaluation_duration_seconds, evaluation_data.duration,
             %{repository: evaluation_data.repository}}
          ]

        :evaluation_failed ->
          [
            {:evaluations_failed_total, 1,
             %{model: evaluation_data.model, error_type: evaluation_data.error_type}}
          ]

        _ ->
          []
      end

    # Record all metrics for this event
    updated_registry =
      Enum.reduce(metrics_to_record, state.metric_registry, fn {name, value, metadata},
                                                               registry ->
        update_metric_registry(registry, name, value, metadata)
      end)

    new_state = %{state | metric_registry: updated_registry}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_system_metrics, resource_data}, state) do
    # Record system resource metrics
    system_metrics = [
      {:memory_usage_bytes, Map.get(resource_data, :memory_bytes, 0), %{}},
      {:cpu_usage_percent, Map.get(resource_data, :cpu_percent, 0), %{}},
      {:container_pool_size, Map.get(resource_data, :pool_size, 0), %{}},
      {:container_utilization_percent, Map.get(resource_data, :utilization, 0), %{}}
    ]

    updated_registry =
      Enum.reduce(system_metrics, state.metric_registry, fn {name, value, metadata}, registry ->
        update_metric_registry(registry, name, value, metadata)
      end)

    new_state = %{state | metric_registry: updated_registry}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_metrics_summary, _from, state) do
    summary = generate_metrics_summary(state.metric_registry)
    {:reply, summary, state}
  end

  @impl true
  def handle_call(:get_prometheus_metrics, _from, state) do
    prometheus_data = format_for_prometheus(state.metric_registry)
    {:reply, prometheus_data, state}
  end

  @impl true
  def handle_info(:collect_periodic_metrics, state) do
    # Collect system metrics periodically
    system_metrics = collect_system_metrics()

    updated_registry =
      Enum.reduce(system_metrics, state.metric_registry, fn {name, value, metadata}, registry ->
        update_metric_registry(registry, name, value, metadata)
      end)

    # Schedule next collection
    schedule_metric_collection()

    new_state = %{state | metric_registry: updated_registry}
    {:noreply, new_state}
  end

  # Private functions

  defp build_metrics_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      collection_interval_ms: 10_000,
      prometheus_enabled: true,
      custom_metrics_enabled: true,
      aggregation_enabled: true,
      retention_hours: 24
    }
  end

  defp setup_telemetry_handlers do
    # Set up telemetry handlers for automatic metric collection
    events = [
      [:swe_bench, :evaluation, :submitted],
      [:swe_bench, :evaluation, :completed],
      [:swe_bench, :evaluation, :failed],
      [:swe_bench, :pipeline, :stage_completed],
      [:swe_bench, :real_time_events, :published],
      [:phoenix, :endpoint, :stop],
      [:phoenix, :router_dispatch, :stop]
    ]

    :telemetry.attach_many(
      "swe-bench-metrics-collector",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end

  defp handle_telemetry_event(
         [:swe_bench, :evaluation, event_type],
         measurements,
         metadata,
         _config
       ) do
    # Handle evaluation telemetry events
    record_evaluation_metric(event_type, Map.merge(measurements, metadata))
  end

  defp handle_telemetry_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    # Handle Phoenix endpoint metrics
    record_metric(:phoenix_request_duration, measurements.duration, metadata)
  end

  defp handle_telemetry_event(
         [:phoenix, :router_dispatch, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Handle Phoenix router metrics
    record_metric(:phoenix_route_duration, measurements.duration, Map.take(metadata, [:route]))
  end

  defp handle_telemetry_event(_event, _measurements, _metadata, _config) do
    # Ignore other events
    :ok
  end

  defp initialize_metric_registry do
    @custom_metrics
    |> Enum.map(fn metric_name ->
      {metric_name,
       %{
         type: determine_metric_type(metric_name),
         values: [],
         metadata: %{},
         last_updated: DateTime.utc_now()
       }}
    end)
    |> Enum.into(%{})
  end

  defp determine_metric_type(metric_name) do
    metric_str = to_string(metric_name)

    cond do
      String.ends_with?(metric_str, "_total") -> :counter
      String.ends_with?(metric_str, "_count") -> :gauge
      String.ends_with?(metric_str, "_percent") -> :gauge
      String.ends_with?(metric_str, "_seconds") -> :histogram
      String.ends_with?(metric_str, "_bytes") -> :gauge
      true -> :gauge
    end
  end

  defp update_metric_registry(registry, metric_name, value, metadata) do
    case Map.get(registry, metric_name) do
      nil ->
        # Create new metric
        new_metric = %{
          type: determine_metric_type(metric_name),
          values: [value],
          metadata: metadata,
          last_updated: DateTime.utc_now()
        }

        Map.put(registry, metric_name, new_metric)

      existing_metric ->
        # Update existing metric
        updated_metric = %{
          existing_metric
          | # Keep last 100 values
            values: [value | existing_metric.values] |> Enum.take(100),
            metadata: Map.merge(existing_metric.metadata, metadata),
            last_updated: DateTime.utc_now()
        }

        Map.put(registry, metric_name, updated_metric)
    end
  end

  defp increment_metric_counter(registry, metric_name, metadata) do
    current_value =
      case Map.get(registry, metric_name) do
        nil -> 0
        metric -> List.first(metric.values) || 0
      end

    update_metric_registry(registry, metric_name, current_value + 1, metadata)
  end

  defp collect_system_metrics do
    [
      {:memory_usage_bytes, :erlang.memory(:total), %{}},
      {:active_sessions_count, get_active_session_count(), %{}},
      {:websocket_connections_active, get_active_websocket_count(), %{}},
      {:container_pool_size, get_container_pool_size(), %{}}
    ]
  end

  defp get_current_queue_depth do
    # Mock queue depth - would integrate with actual evaluation queue
    :rand.uniform(10)
  end

  defp get_active_session_count do
    # Mock session count - would integrate with session manager
    :rand.uniform(50) + 10
  end

  defp get_active_websocket_count do
    # Mock websocket count - would integrate with Phoenix channels
    :rand.uniform(100) + 20
  end

  defp get_container_pool_size do
    # Mock container pool size - would integrate with container manager
    :rand.uniform(20) + 5
  end

  defp generate_metrics_summary(registry) do
    %{
      total_metrics: map_size(registry),
      metrics_by_type: count_metrics_by_type(registry),
      latest_values: get_latest_metric_values(registry),
      collection_health: assess_collection_health(registry)
    }
  end

  defp count_metrics_by_type(registry) do
    registry
    |> Enum.group_by(fn {_name, metric} -> metric.type end)
    |> Enum.map(fn {type, metrics} -> {type, length(metrics)} end)
    |> Enum.into(%{})
  end

  defp get_latest_metric_values(registry) do
    registry
    |> Enum.map(fn {name, metric} ->
      latest_value = List.first(metric.values) || 0
      {name, latest_value}
    end)
    |> Enum.into(%{})
  end

  defp assess_collection_health(registry) do
    # 5 minutes
    stale_threshold = DateTime.add(DateTime.utc_now(), -300, :second)

    stale_metrics =
      registry
      |> Enum.count(fn {_name, metric} ->
        DateTime.compare(metric.last_updated, stale_threshold) == :lt
      end)

    %{
      total_metrics: map_size(registry),
      stale_metrics: stale_metrics,
      health_score: max(0, 100 - stale_metrics / map_size(registry) * 100)
    }
  end

  defp format_for_prometheus(registry) do
    registry
    |> Enum.map_join("\n", fn {name, metric} ->
      format_prometheus_metric(name, metric)
    end)
  end

  defp format_prometheus_metric(name, metric) do
    metric_name = format_prometheus_name(name)
    latest_value = List.first(metric.values) || 0

    "# TYPE #{metric_name} #{prometheus_type(metric.type)}\n" <>
      "#{metric_name} #{latest_value}"
  end

  defp format_prometheus_name(name) do
    name
    |> to_string()
    |> String.replace("_", "_")
  end

  defp prometheus_type(:counter), do: "counter"
  defp prometheus_type(:gauge), do: "gauge"
  defp prometheus_type(:histogram), do: "histogram"
  defp prometheus_type(_), do: "gauge"

  defp initialize_collection_stats do
    %{
      metrics_collected: 0,
      collection_errors: 0,
      last_collection: DateTime.utc_now(),
      collection_duration_ms: 0
    }
  end

  defp schedule_metric_collection do
    # 10 seconds
    Process.send_after(self(), :collect_periodic_metrics, 10_000)
  end
end
