defmodule SweBench.RealTimeEvents.EventStore do
  @moduledoc """
  Event store for event sourcing and replay capabilities.

  Provides persistent storage of events with replay functionality,
  event ordering, and historical event access for system analysis.
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :event_buffer,
    :event_index,
    :storage_stats
  ]

  @doc """
  Starts the event store with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Stores an event for future replay and analysis.
  """
  def store_event(event) do
    GenServer.cast(__MODULE__, {:store_event, event})
  end

  @doc """
  Retrieves recent events for a specific channel.
  """
  def get_recent_events(channel_name, count \\ 10) do
    GenServer.call(__MODULE__, {:get_recent_events, channel_name, count})
  end

  @doc """
  Retrieves events for a specific evaluation.
  """
  def get_evaluation_events(evaluation_id) do
    GenServer.call(__MODULE__, {:get_evaluation_events, evaluation_id})
  end

  @doc """
  Returns event storage statistics.
  """
  def get_storage_statistics do
    GenServer.call(__MODULE__, :get_storage_statistics)
  end

  @impl true
  def init(config) do
    store_config = build_store_config(config)
    
    state = %__MODULE__{
      config: store_config,
      event_buffer: [],
      event_index: %{},
      storage_stats: initialize_storage_stats()
    }

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("RealTimeEvents.EventStore initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast({:store_event, event}, state) do
    # Add event to buffer with index
    indexed_event = add_event_index(event)
    
    # Update buffer (keep last N events in memory)
    new_buffer = [indexed_event | state.event_buffer]
    |> Enum.take(state.config.memory_buffer_size)
    
    # Update index for fast lookups
    new_index = update_event_index(state.event_index, indexed_event)
    
    # Update storage statistics
    new_stats = update_storage_stats(state.storage_stats, indexed_event)
    
    # Persist to storage if configured
    if state.config.persistent_storage_enabled do
      persist_event(indexed_event)
    end

    new_state = %{state |
      event_buffer: new_buffer,
      event_index: new_index,
      storage_stats: new_stats
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_recent_events, channel_name, count}, _from, state) do
    recent_events = state.event_buffer
    |> Enum.filter(fn event ->
        matches_channel?(event, channel_name)
    end)
    |> Enum.take(count)
    |> Enum.reverse()  # Return in chronological order

    {:reply, recent_events, state}
  end

  @impl true
  def handle_call({:get_evaluation_events, evaluation_id}, _from, state) do
    evaluation_events = state.event_buffer
    |> Enum.filter(fn event ->
        get_in(event, [:metadata, :correlation_id]) == evaluation_id
    end)
    |> Enum.reverse()  # Chronological order

    {:reply, evaluation_events, state}
  end

  @impl true
  def handle_call(:get_storage_statistics, _from, state) do
    {:reply, state.storage_stats, state}
  end

  @impl true
  def handle_info(:cleanup_old_events, state) do
    # Clean up old events from memory buffer
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.config.retention_hours * 3600, :second)
    
    cleaned_buffer = state.event_buffer
    |> Enum.filter(fn event ->
        event_time = get_in(event, [:metadata, :timestamp])
        DateTime.compare(event_time, cutoff_time) == :gt
    end)

    cleaned_index = rebuild_event_index(cleaned_buffer)
    
    # Schedule next cleanup
    schedule_cleanup()
    
    new_state = %{state |
      event_buffer: cleaned_buffer,
      event_index: cleaned_index
    }

    Logger.debug("Cleaned up old events, buffer size: #{length(cleaned_buffer)}")
    {:noreply, new_state}
  end

  # Private functions

  defp build_store_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      memory_buffer_size: 1000,
      retention_hours: 24,
      persistent_storage_enabled: false,  # Would integrate with database
      cleanup_interval_minutes: 60,
      compression_enabled: false
    }
  end

  defp initialize_storage_stats do
    %{
      total_events_stored: 0,
      events_by_type: %{},
      average_event_size_bytes: 0,
      storage_efficiency_percent: 100.0,
      oldest_event_timestamp: DateTime.utc_now(),
      newest_event_timestamp: DateTime.utc_now()
    }
  end

  defp add_event_index(event) do
    Map.put(event, :stored_at, DateTime.utc_now())
  end

  defp update_event_index(index, event) do
    event_type = Map.get(event, :type)
    correlation_id = get_in(event, [:metadata, :correlation_id])
    
    # Index by event type
    type_index = Map.get(index, :by_type, %{})
    updated_type_index = Map.update(type_index, event_type, [event], fn events ->
      [event | events] |> Enum.take(100)  # Keep latest 100 per type
    end)
    
    # Index by correlation ID if present
    correlation_index = if correlation_id do
      Map.get(index, :by_correlation, %{})
      |> Map.update(correlation_id, [event], fn events ->
          [event | events] |> Enum.take(50)  # Keep latest 50 per correlation
      end)
    else
      Map.get(index, :by_correlation, %{})
    end
    
    %{
      by_type: updated_type_index,
      by_correlation: correlation_index
    }
  end

  defp update_storage_stats(stats, event) do
    event_type = Map.get(event, :type)
    event_size = estimate_event_size(event)
    
    %{stats |
      total_events_stored: stats.total_events_stored + 1,
      events_by_type: Map.update(stats.events_by_type, event_type, 1, &(&1 + 1)),
      average_event_size_bytes: calculate_average_size(stats, event_size),
      newest_event_timestamp: get_in(event, [:metadata, :timestamp])
    }
  end

  defp calculate_average_size(stats, new_event_size) do
    total_events = stats.total_events_stored + 1
    current_total = stats.average_event_size_bytes * stats.total_events_stored
    (current_total + new_event_size) / total_events
  end

  defp estimate_event_size(event) do
    # Simple size estimation - would use actual byte calculation
    event
    |> inspect()
    |> String.length()
  end

  defp matches_channel?(event, channel_name) do
    # Determine if event belongs to specific channel
    event_type = Map.get(event, :type)
    
    case {channel_name, event_type} do
      {"evaluations:submissions", type} when type in [:evaluation_submitted, :evaluation_queued] -> true
      {"evaluations:progress", type} when type in [:progress_update, :stage_completed, :test_executed] -> true
      {"evaluations:results", type} when type in [:evaluation_completed, :results_available] -> true
      {"datasets:updates", type} when type in [:task_instance_added, :repository_updated] -> true
      {"datasets:releases", type} when type in [:dataset_version_released] -> true
      {"system:health", type} when type in [:health_check, :performance_alert] -> true
      {"system:public", type} when type in [:system_status, :maintenance_notice] -> true
      _ -> false
    end
  end

  defp persist_event(event) do
    # Mock persistence - would integrate with actual database
    Logger.debug("Persisting event: #{event.id}")
    :ok
  end

  defp rebuild_event_index(events) do
    Enum.reduce(events, %{by_type: %{}, by_correlation: %{}}, fn event, index ->
      update_event_index(index, event)
    end)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_events, 3_600_000)  # 1 hour
  end
end