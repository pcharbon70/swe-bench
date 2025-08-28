defmodule SweBench.RealTimeEvents.EventCoordinator do
  @moduledoc """
  Central coordinator for real-time event streaming across SWE-bench system.

  Manages Phoenix.PubSub-based event distribution with proper channel management,
  event filtering, and connection lifecycle coordination.
  """

  use GenServer
  require Logger

  alias SweBench.RealTimeEvents.EventStore

  defstruct [
    :config,
    :active_channels,
    :subscription_registry,
    :event_statistics,
    :connection_pool
  ]

  @pubsub_instance SweBench.PubSub

  @channel_structure %{
    # Evaluation lifecycle events
    "evaluations:submissions" => %{
      auth_required: false,
      rate_limit: 100,
      event_types: [:evaluation_submitted, :evaluation_queued]
    },
    "evaluations:progress" => %{
      auth_required: false,
      rate_limit: 1000,
      event_types: [:progress_update, :stage_completed, :test_executed]
    },
    "evaluations:results" => %{
      auth_required: false,
      rate_limit: 500,
      event_types: [:evaluation_completed, :results_available, :analysis_finished]
    },
    "evaluations:admin" => %{
      auth_required: true,
      rate_limit: 200,
      event_types: [:admin_submission, :system_logs, :performance_metrics]
    },

    # Dataset and repository events
    "datasets:updates" => %{
      auth_required: false,
      rate_limit: 50,
      event_types: [:task_instance_added, :repository_updated, :validation_completed]
    },
    "datasets:releases" => %{
      auth_required: false,
      rate_limit: 10,
      event_types: [:dataset_version_released, :repository_added, :statistics_updated]
    },

    # System health and monitoring
    "system:health" => %{
      auth_required: true,
      rate_limit: 100,
      event_types: [:health_check, :resource_usage, :performance_alert]
    },
    "system:public" => %{
      auth_required: false,
      rate_limit: 50,
      event_types: [:system_status, :maintenance_notice, :uptime_report]
    }
  }

  @doc """
  Starts the event coordinator with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Broadcasts an event to the appropriate channels.
  """
  def broadcast_event(event_type, payload, options \\ []) do
    GenServer.cast(__MODULE__, {:broadcast_event, event_type, payload, options})
  end

  @doc """
  Subscribes a process to specific event channels.
  """
  def subscribe_to_channel(channel_name, subscriber_pid \\ nil, auth_context \\ nil) do
    GenServer.call(__MODULE__, {:subscribe_to_channel, channel_name, subscriber_pid || self(), auth_context})
  end

  @doc """
  Unsubscribes from event channels.
  """
  def unsubscribe_from_channel(channel_name, subscriber_pid \\ nil) do
    GenServer.cast(__MODULE__, {:unsubscribe_from_channel, channel_name, subscriber_pid || self()})
  end

  @doc """
  Returns current event streaming statistics.
  """
  def get_event_statistics do
    GenServer.call(__MODULE__, :get_event_statistics)
  end

  @doc """
  Returns active channel information.
  """
  def get_active_channels do
    GenServer.call(__MODULE__, :get_active_channels)
  end

  @impl true
  def init(config) do
    event_config = build_event_config(config)
    
    state = %__MODULE__{
      config: event_config,
      active_channels: initialize_channels(),
      subscription_registry: %{},
      event_statistics: initialize_statistics(),
      connection_pool: %{}
    }

    # Initialize channel monitoring
    schedule_channel_monitoring()

    Logger.info("RealTimeEvents.EventCoordinator initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast({:broadcast_event, event_type, payload, options}, state) do
    # Determine target channels for this event type
    target_channels = determine_target_channels(event_type, state.config)
    
    # Create event with metadata
    event = create_event(event_type, payload, options)
    
    # Broadcast to all target channels
    broadcast_results = Enum.map(target_channels, fn channel_name ->
      broadcast_to_channel(channel_name, event, state)
    end)
    
    # Update statistics
    new_statistics = update_event_statistics(state.event_statistics, event, broadcast_results)
    
    # Store event for replay if configured
    if state.config.event_store_enabled do
      EventStore.store_event(event)
    end

    new_state = %{state | event_statistics: new_statistics}
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:subscribe_to_channel, channel_name, subscriber_pid, auth_context}, _from, state) do
    case validate_channel_subscription(channel_name, auth_context, state) do
      {:ok, validated_context} ->
        # Subscribe to Phoenix.PubSub
        case Phoenix.PubSub.subscribe(@pubsub_instance, channel_name, subscriber_pid) do
          :ok ->
            # Register subscription
            new_registry = register_subscription(state.subscription_registry, channel_name, subscriber_pid, validated_context)
            
            # Send initial state if available
            maybe_send_initial_state(channel_name, subscriber_pid, state)
            
            new_state = %{state | subscription_registry: new_registry}
            {:reply, {:ok, :subscribed}, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe_from_channel, channel_name, subscriber_pid}, _from, state) do
    # Unsubscribe from Phoenix.PubSub
    Phoenix.PubSub.unsubscribe(@pubsub_instance, channel_name)
    
    # Update registry
    new_registry = unregister_subscription(state.subscription_registry, channel_name, subscriber_pid)
    
    new_state = %{state | subscription_registry: new_registry}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_event_statistics, _from, state) do
    {:reply, state.event_statistics, state}
  end

  @impl true
  def handle_call(:get_active_channels, _from, state) do
    channel_info = state.active_channels
    |> Enum.map(fn {channel_name, channel_data} ->
        subscriber_count = get_subscriber_count(channel_name, state.subscription_registry)
        Map.put(channel_data, :subscriber_count, subscriber_count)
    end)

    {:reply, channel_info, state}
  end

  @impl true
  def handle_info(:channel_monitoring, state) do
    # Perform channel health monitoring
    updated_channels = monitor_channel_health(state.active_channels)
    
    # Reschedule monitoring
    schedule_channel_monitoring()
    
    new_state = %{state | active_channels: updated_channels}
    {:noreply, new_state}
  end

  # Private functions

  defp build_event_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      event_store_enabled: true,
      channel_monitoring_interval: 30_000,  # 30 seconds
      max_subscribers_per_channel: 1000,
      event_replay_enabled: true,
      connection_timeout: 60_000,
      bandwidth_optimization: true
    }
  end

  defp initialize_channels do
    @channel_structure
    |> Enum.map(fn {channel_name, config} ->
        {channel_name, Map.merge(config, %{
          created_at: DateTime.utc_now(),
          status: :active,
          event_count: 0
        })}
    end)
    |> Enum.into(%{})
  end

  defp initialize_statistics do
    %{
      total_events_broadcast: 0,
      events_per_channel: %{},
      average_delivery_time_ms: 0.0,
      failed_deliveries: 0,
      active_subscribers: 0,
      peak_concurrent_connections: 0,
      started_at: DateTime.utc_now()
    }
  end

  defp determine_target_channels(event_type, _config) do
    # Map event types to appropriate channels
    case event_type do
      type when type in [:evaluation_submitted, :evaluation_queued] ->
        ["evaluations:submissions"]
      
      type when type in [:progress_update, :stage_completed, :test_executed] ->
        ["evaluations:progress"]
      
      type when type in [:evaluation_completed, :results_available] ->
        ["evaluations:results"]
      
      type when type in [:admin_action, :system_logs] ->
        ["evaluations:admin"]
      
      type when type in [:task_instance_added, :repository_updated] ->
        ["datasets:updates"]
      
      type when type in [:dataset_released, :statistics_updated] ->
        ["datasets:releases"]
      
      type when type in [:health_check, :performance_alert] ->
        ["system:health"]
      
      type when type in [:system_status, :maintenance_notice] ->
        ["system:public"]
      
      _ ->
        ["system:public"]  # Default channel for unknown events
    end
  end

  defp create_event(event_type, payload, options) do
    %{
      id: generate_event_id(),
      type: event_type,
      payload: payload,
      metadata: %{
        timestamp: DateTime.utc_now(),
        source: Keyword.get(options, :source, :system),
        version: "1.0",
        correlation_id: Keyword.get(options, :correlation_id)
      }
    }
  end

  defp broadcast_to_channel(channel_name, event, state) do
    case Map.get(state.active_channels, channel_name) do
      nil ->
        {:error, :channel_not_found}
      
      channel_config ->
        # Check rate limits
        case check_rate_limit(channel_name, channel_config) do
          :ok ->
            # Broadcast via Phoenix.PubSub
            Phoenix.PubSub.broadcast(@pubsub_instance, channel_name, {:event, event})
            {:ok, :broadcast_successful}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp validate_channel_subscription(channel_name, auth_context, state) do
    case Map.get(state.active_channels, channel_name) do
      nil ->
        {:error, :channel_not_found}
      
      channel_config ->
        if channel_config.auth_required and not authenticated?(auth_context) do
          {:error, :authentication_required}
        else
          {:ok, auth_context}
        end
    end
  end

  defp authenticated?(nil), do: false
  defp authenticated?(%{user: %{role: _role}}), do: true
  defp authenticated?(_), do: false

  defp register_subscription(registry, channel_name, subscriber_pid, auth_context) do
    channel_subscribers = Map.get(registry, channel_name, [])
    
    subscription_data = %{
      pid: subscriber_pid,
      auth_context: auth_context,
      subscribed_at: DateTime.utc_now(),
      last_event_received: nil
    }
    
    updated_subscribers = [subscription_data | channel_subscribers]
    Map.put(registry, channel_name, updated_subscribers)
  end

  defp unregister_subscription(registry, channel_name, subscriber_pid) do
    case Map.get(registry, channel_name) do
      nil -> registry
      subscribers ->
        updated_subscribers = Enum.reject(subscribers, fn sub ->
          sub.pid == subscriber_pid
        end)
        Map.put(registry, channel_name, updated_subscribers)
    end
  end

  defp get_subscriber_count(channel_name, registry) do
    case Map.get(registry, channel_name) do
      nil -> 0
      subscribers -> length(subscribers)
    end
  end

  defp maybe_send_initial_state(channel_name, subscriber_pid, state) do
    # Send recent events for immediate context
    if state.config.event_replay_enabled do
      recent_events = EventStore.get_recent_events(channel_name, 5)
      
      Enum.each(recent_events, fn event ->
        send(subscriber_pid, {:event, event})
      end)
    end
  end

  defp check_rate_limit(_channel_name, channel_config) do
    # Simple rate limiting - would be enhanced with actual rate limiter
    rate_limit = Map.get(channel_config, :rate_limit, 100)
    current_rate = Map.get(channel_config, :current_rate, 0)
    
    if current_rate < rate_limit do
      :ok
    else
      {:error, :rate_limit_exceeded}
    end
  end

  defp update_event_statistics(statistics, event, broadcast_results) do
    successful_broadcasts = broadcast_results
    |> Enum.count(fn result -> elem(result, 0) == :ok end)
    
    %{statistics |
      total_events_broadcast: statistics.total_events_broadcast + 1,
      events_per_channel: update_channel_stats(statistics.events_per_channel, event),
      failed_deliveries: statistics.failed_deliveries + (length(broadcast_results) - successful_broadcasts)
    }
  end

  defp update_channel_stats(channel_stats, _event) do
    # Would determine actual channel from event routing
    primary_channel = "evaluations:progress"  # Example
    Map.update(channel_stats, primary_channel, 1, &(&1 + 1))
  end

  defp monitor_channel_health(channels) do
    channels
    |> Enum.map(fn {channel_name, channel_data} ->
        # Perform health check on channel
        health_status = check_channel_health(channel_name, channel_data)
        updated_data = Map.put(channel_data, :health_status, health_status)
        {channel_name, updated_data}
    end)
    |> Enum.into(%{})
  end

  defp check_channel_health(_channel_name, _channel_data) do
    # Mock health checking - would perform actual health validation
    %{
      status: :healthy,
      last_event: DateTime.add(DateTime.utc_now(), -:rand.uniform(60), :second),
      subscriber_count: :rand.uniform(50),
      event_rate_per_minute: :rand.uniform(100)
    }
  end

  defp schedule_channel_monitoring do
    Process.send_after(self(), :channel_monitoring, 30_000)
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end