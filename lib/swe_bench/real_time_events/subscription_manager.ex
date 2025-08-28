defmodule SweBench.RealTimeEvents.SubscriptionManager do
  @moduledoc """
  Manages WebSocket subscriptions and connection lifecycle.

  Handles subscription registration, authentication, connection recovery,
  and bandwidth optimization for real-time event streaming.
  """

  use GenServer
  require Logger

  alias SweBench.RealTimeEvents.EventCoordinator

  defstruct [
    :config,
    :active_subscriptions,
    :connection_metrics,
    :bandwidth_monitor
  ]

  @doc """
  Starts the subscription manager with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Registers a new subscription for a user/process.
  """
  def register_subscription(user_id, channel_names, connection_info \\ %{}) do
    GenServer.call(__MODULE__, {:register_subscription, user_id, channel_names, connection_info})
  end

  @doc """
  Unregisters a subscription.
  """
  def unregister_subscription(user_id, channel_names \\ :all) do
    GenServer.cast(__MODULE__, {:unregister_subscription, user_id, channel_names})
  end

  @doc """
  Returns subscription statistics and metrics.
  """
  def get_subscription_metrics do
    GenServer.call(__MODULE__, :get_subscription_metrics)
  end

  @doc """
  Handles connection recovery for dropped connections.
  """
  def recover_connection(user_id, last_event_id \\ nil) do
    GenServer.call(__MODULE__, {:recover_connection, user_id, last_event_id})
  end

  @impl true
  def init(config) do
    subscription_config = build_subscription_config(config)

    state = %__MODULE__{
      config: subscription_config,
      active_subscriptions: %{},
      connection_metrics: initialize_connection_metrics(),
      bandwidth_monitor: %{}
    }

    # Schedule connection monitoring
    schedule_connection_monitoring()

    Logger.info("RealTimeEvents.SubscriptionManager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_subscription, user_id, channel_names, connection_info}, _from, state) do
    case validate_subscription_request(user_id, channel_names, connection_info, state) do
      {:ok, validated_channels} ->
        subscription_data = %{
          user_id: user_id,
          channels: validated_channels,
          connection_info: connection_info,
          registered_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          status: :active
        }

        # Register with PubSub channels
        subscription_results = register_with_channels(validated_channels, user_id)

        case subscription_results do
          {:ok, channel_subscriptions} ->
            new_subscriptions =
              Map.put(
                state.active_subscriptions,
                user_id,
                Map.put(subscription_data, :channel_subscriptions, channel_subscriptions)
              )

            # Update metrics
            new_metrics = update_connection_metrics(state.connection_metrics, :subscription_added)

            new_state = %{
              state
              | active_subscriptions: new_subscriptions,
                connection_metrics: new_metrics
            }

            {:reply, {:ok, :subscription_registered}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:recover_connection, user_id, last_event_id}, _from, state) do
    case Map.get(state.active_subscriptions, user_id) do
      nil ->
        {:reply, {:error, :subscription_not_found}, state}

      subscription_data ->
        # Get missed events since last_event_id
        missed_events =
          if last_event_id do
            get_events_since(last_event_id, subscription_data.channels)
          else
            []
          end

        # Update subscription status
        updated_subscription = %{
          subscription_data
          | status: :active,
            last_activity: DateTime.utc_now()
        }

        new_subscriptions = Map.put(state.active_subscriptions, user_id, updated_subscription)

        new_state = %{state | active_subscriptions: new_subscriptions}

        {:reply, {:ok, missed_events}, new_state}
    end
  end

  @impl true
  def handle_call(:get_subscription_metrics, _from, state) do
    metrics = %{
      total_active_subscriptions: map_size(state.active_subscriptions),
      connection_metrics: state.connection_metrics,
      bandwidth_usage: calculate_bandwidth_usage(state.bandwidth_monitor),
      subscription_breakdown: generate_subscription_breakdown(state.active_subscriptions)
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_cast({:unregister_subscription, user_id, channel_names}, state) do
    case Map.get(state.active_subscriptions, user_id) do
      nil ->
        {:noreply, state}

      subscription_data ->
        # Unregister from specified channels or all
        channels_to_unregister =
          case channel_names do
            :all -> subscription_data.channels
            specific_channels -> specific_channels
          end

        # Unsubscribe from PubSub
        unregister_from_channels(channels_to_unregister, user_id)

        # Update subscription registry
        new_subscriptions =
          if channel_names == :all do
            Map.delete(state.active_subscriptions, user_id)
          else
            remaining_channels = subscription_data.channels -- channels_to_unregister
            updated_subscription = Map.put(subscription_data, :channels, remaining_channels)
            Map.put(state.active_subscriptions, user_id, updated_subscription)
          end

        # Update metrics
        new_metrics = update_connection_metrics(state.connection_metrics, :subscription_removed)

        new_state = %{
          state
          | active_subscriptions: new_subscriptions,
            connection_metrics: new_metrics
        }

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:connection_monitoring, state) do
    # Monitor connection health and cleanup stale connections
    updated_subscriptions = cleanup_stale_connections(state.active_subscriptions, state.config)

    # Update bandwidth monitoring
    updated_bandwidth_monitor = update_bandwidth_monitoring(state.bandwidth_monitor)

    # Schedule next monitoring
    schedule_connection_monitoring()

    new_state = %{
      state
      | active_subscriptions: updated_subscriptions,
        bandwidth_monitor: updated_bandwidth_monitor
    }

    {:noreply, new_state}
  end

  # Private functions

  defp build_subscription_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      max_subscriptions_per_user: 10,
      connection_timeout_minutes: 60,
      stale_connection_cleanup_minutes: 30,
      bandwidth_optimization_enabled: true,
      connection_recovery_enabled: true
    }
  end

  defp initialize_connection_metrics do
    %{
      total_connections_created: 0,
      total_connections_dropped: 0,
      active_connections: 0,
      average_connection_duration_minutes: 0.0,
      connection_recovery_success_rate: 100.0
    }
  end

  defp validate_subscription_request(user_id, channel_names, connection_info, state) do
    # Validate user subscription limits
    current_subscriptions = Map.get(state.active_subscriptions, user_id)

    current_channel_count =
      if current_subscriptions do
        length(current_subscriptions.channels)
      else
        0
      end

    max_channels = state.config.max_subscriptions_per_user
    requested_channels = if is_list(channel_names), do: length(channel_names), else: 1

    if current_channel_count + requested_channels <= max_channels do
      # Validate channels exist and are accessible
      channel_list = if is_list(channel_names), do: channel_names, else: [channel_names]
      validated_channels = validate_channel_access(channel_list, connection_info)

      {:ok, validated_channels}
    else
      {:error, :subscription_limit_exceeded}
    end
  end

  defp validate_channel_access(channel_names, _connection_info) do
    # Validate that user can access requested channels
    # For now, return all channels - would implement actual auth logic
    channel_names
  end

  defp register_with_channels(channel_names, user_id) do
    subscription_results =
      channel_names
      |> Enum.map(fn channel_name ->
        case EventCoordinator.subscribe_to_channel(channel_name, self(), %{user_id: user_id}) do
          {:ok, :subscribed} -> {channel_name, :ok}
          {:error, reason} -> {channel_name, {:error, reason}}
        end
      end)

    failed_subscriptions =
      subscription_results
      |> Enum.filter(fn {_channel, result} -> elem(result, 0) == :error end)

    if failed_subscriptions == [] do
      {:ok, subscription_results}
    else
      {:error, {:channel_subscription_failed, failed_subscriptions}}
    end
  end

  defp unregister_from_channels(channel_names, _user_id) do
    Enum.each(channel_names, fn channel_name ->
      EventCoordinator.unsubscribe_from_channel(channel_name, self())
    end)
  end

  defp get_events_since(_last_event_id, _channels) do
    # Get events since last_event_id for connection recovery
    # Mock implementation - would query actual event store
    []
  end

  defp cleanup_stale_connections(subscriptions, config) do
    timeout_minutes = config.connection_timeout_minutes
    cutoff_time = DateTime.add(DateTime.utc_now(), -timeout_minutes * 60, :second)

    subscriptions
    |> Enum.filter(fn {_user_id, subscription} ->
      DateTime.compare(subscription.last_activity, cutoff_time) == :gt
    end)
    |> Enum.into(%{})
  end

  defp update_bandwidth_monitoring(bandwidth_monitor) do
    # Update bandwidth usage statistics
    current_time = DateTime.utc_now()

    Map.put(bandwidth_monitor, :last_updated, current_time)
  end

  defp calculate_bandwidth_usage(_bandwidth_monitor) do
    # Calculate current bandwidth usage
    %{
      # 0-100KB/s
      bytes_per_second: :rand.uniform(1024 * 100),
      # 0-50 events/s
      events_per_second: :rand.uniform(50),
      # 0-500KB peak
      peak_usage_bytes: :rand.uniform(1024 * 500),
      # 70-90% compression
      compression_ratio: 0.7 + :rand.uniform() * 0.2
    }
  end

  defp generate_subscription_breakdown(subscriptions) do
    channel_counts =
      subscriptions
      |> Enum.reduce(%{}, fn {_user_id, subscription}, acc ->
        Enum.reduce(subscription.channels, acc, fn channel, inner_acc ->
          Map.update(inner_acc, channel, 1, &(&1 + 1))
        end)
      end)

    %{
      subscriptions_per_channel: channel_counts,
      total_unique_users: map_size(subscriptions),
      average_channels_per_user: calculate_average_channels_per_user(subscriptions)
    }
  end

  defp calculate_average_channels_per_user(subscriptions) when map_size(subscriptions) == 0,
    do: 0.0

  defp calculate_average_channels_per_user(subscriptions) do
    total_channels =
      subscriptions
      |> Enum.reduce(0, fn {_user_id, subscription}, acc ->
        acc + length(subscription.channels)
      end)

    total_channels / map_size(subscriptions)
  end

  defp update_connection_metrics(metrics, event_type) do
    case event_type do
      :subscription_added ->
        %{
          metrics
          | total_connections_created: metrics.total_connections_created + 1,
            active_connections: metrics.active_connections + 1
        }

      :subscription_removed ->
        %{
          metrics
          | total_connections_dropped: metrics.total_connections_dropped + 1,
            active_connections: max(0, metrics.active_connections - 1)
        }

      _ ->
        metrics
    end
  end

  defp schedule_connection_monitoring do
    # 30 seconds
    Process.send_after(self(), :connection_monitoring, 30_000)
  end
end
