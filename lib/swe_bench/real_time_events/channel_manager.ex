defmodule SweBench.RealTimeEvents.ChannelManager do
  @moduledoc """
  Manages individual PubSub channels with authentication and filtering.

  Handles channel-specific operations including event filtering,
  authentication checks, and channel health monitoring.
  """

  require Logger

  @doc """
  Creates a new event channel with specified configuration.
  """
  def create_channel(channel_name, config \\ %{}) do
    channel_config = build_channel_config(config)
    
    Logger.info("Creating event channel: #{channel_name}")
    
    # Register channel configuration
    :ets.insert(:event_channels, {channel_name, channel_config})
    
    {:ok, channel_config}
  end

  @doc """
  Validates if a user can access a specific channel.
  """
  def validate_channel_access(channel_name, auth_context) do
    case :ets.lookup(:event_channels, channel_name) do
      [{_channel, config}] ->
        if config.auth_required do
          validate_authentication(auth_context, config)
        else
          {:ok, :access_granted}
        end
      
      [] ->
        {:error, :channel_not_found}
    end
  end

  @doc """
  Filters events based on user permissions and channel configuration.
  """
  def filter_event_for_user(event, channel_name, auth_context) do
    case get_channel_config(channel_name) do
      {:ok, config} ->
        if should_deliver_event?(event, config, auth_context) do
          filtered_event = apply_event_filtering(event, config, auth_context)
          {:ok, filtered_event}
        else
          {:filtered, :no_delivery}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns channel statistics and health information.
  """
  def get_channel_health(channel_name) do
    case get_channel_config(channel_name) do
      {:ok, config} ->
        health_data = %{
          channel_name: channel_name,
          status: :healthy,  # Would perform actual health checks
          subscriber_count: get_subscriber_count(channel_name),
          event_rate: get_event_rate(channel_name),
          last_activity: DateTime.add(DateTime.utc_now(), -:rand.uniform(60), :second),
          config: config
        }
        
        {:ok, health_data}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Initializes the channel ETS table.
  """
  def initialize_channel_storage do
    case :ets.whereis(:event_channels) do
      :undefined ->
        :ets.new(:event_channels, [:set, :public, :named_table])
        Logger.info("Initialized event channels ETS table")
        
      _table ->
        Logger.debug("Event channels ETS table already exists")
    end
  end

  # Private functions

  defp build_channel_config(config) do
    default_config()
    |> Map.merge(config)
    |> Map.put(:created_at, DateTime.utc_now())
  end

  defp default_config do
    %{
      auth_required: false,
      rate_limit: 100,
      event_filtering_enabled: false,
      compression_enabled: true,
      persistence_enabled: true,
      max_subscribers: 1000
    }
  end

  defp validate_authentication(auth_context, config) do
    case auth_context do
      %{user: %{role: :admin}} when config.admin_required ->
        {:ok, :admin_access}
      
      %{user: %{id: _user_id}} ->
        {:ok, :user_access}
      
      nil when config.auth_required ->
        {:error, :authentication_required}
      
      _ ->
        {:ok, :public_access}
    end
  end

  defp should_deliver_event?(event, config, auth_context) do
    # Check if event should be delivered based on filters and auth
    event_type = Map.get(event, :type)
    
    # Check event type whitelist
    allowed_types = Map.get(config, :allowed_event_types, :all)
    type_allowed = case allowed_types do
      :all -> true
      types when is_list(types) -> event_type in types
      _ -> true
    end
    
    # Check authentication requirements
    auth_allowed = if config.auth_required do
      authenticated_user?(auth_context)
    else
      true
    end
    
    type_allowed and auth_allowed
  end

  defp apply_event_filtering(event, _config, auth_context) do
    # Apply any necessary event filtering based on user permissions
    case auth_context do
      %{user: %{role: :admin}} ->
        # Admin gets full event details
        event
      
      %{user: %{id: _user_id}} ->
        # Regular users get filtered events
        filter_sensitive_data(event)
      
      _ ->
        # Public users get minimal event data
        filter_for_public_access(event)
    end
  end

  defp filter_sensitive_data(event) do
    # Remove sensitive information for regular users
    event
    |> Map.update(:payload, %{}, fn payload ->
        Map.drop(payload, [:internal_details, :system_logs, :admin_metadata])
    end)
  end

  defp filter_for_public_access(event) do
    # Minimal event data for public users
    %{
      id: event.id,
      type: event.type,
      payload: Map.take(event.payload, [:evaluation_id, :score, :status, :repository]),
      metadata: Map.take(event.metadata, [:timestamp])
    }
  end

  defp authenticated_user?(%{user: %{id: _}}), do: true
  defp authenticated_user?(_), do: false

  defp get_channel_config(channel_name) do
    case :ets.lookup(:event_channels, channel_name) do
      [{_channel, config}] -> {:ok, config}
      [] -> {:error, :channel_not_found}
    end
  end

  defp get_subscriber_count(_channel_name) do
    # Mock subscriber count - would integrate with actual PubSub metrics
    :rand.uniform(100)
  end

  defp get_event_rate(_channel_name) do
    # Mock event rate - would track actual event throughput
    :rand.uniform(50)
  end
end