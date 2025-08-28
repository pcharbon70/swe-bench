defmodule SweBench.Accounts.UsageLimiter do
  @moduledoc """
  Tier-based usage limiting and quota management.

  Implements sliding window evaluation tracking with real-time usage
  indicators and quota enforcement for fair resource allocation.
  """

  use GenServer
  require Logger

  alias SweBench.Accounts.{Authorization, AuditLogger}

  defstruct [
    :config,
    :usage_tracking,
    :quota_enforcement,
    :sliding_windows
  ]

  @usage_tiers %{
    public: %{
      evaluations_per_hour: 0,
      evaluations_per_day: 0,
      evaluations_per_month: 0,
      concurrent_evaluations: 0
    },
    researcher: %{
      evaluations_per_hour: 2,
      evaluations_per_day: 10,
      evaluations_per_month: 50,
      concurrent_evaluations: 1
    },
    admin: %{
      evaluations_per_hour: :unlimited,
      evaluations_per_day: :unlimited,
      evaluations_per_month: :unlimited,
      concurrent_evaluations: :unlimited
    }
  }

  @doc """
  Starts the usage limiter with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Checks if user can submit an evaluation based on quota limits.
  """
  def can_submit_evaluation?(user) do
    GenServer.call(__MODULE__, {:can_submit_evaluation, user})
  end

  @doc """
  Records an evaluation submission for usage tracking.
  """
  def record_evaluation_submitted(user, evaluation_id) do
    GenServer.cast(__MODULE__, {:record_evaluation_submitted, user, evaluation_id})
  end

  @doc """
  Records an evaluation completion for usage tracking.
  """
  def record_evaluation_completed(user, evaluation_id) do
    GenServer.cast(__MODULE__, {:record_evaluation_completed, user, evaluation_id})
  end

  @doc """
  Gets current usage statistics for a user.
  """
  def get_user_usage(user) do
    GenServer.call(__MODULE__, {:get_user_usage, user})
  end

  @doc """
  Gets system-wide usage statistics.
  """
  def get_system_usage_statistics do
    GenServer.call(__MODULE__, :get_system_usage_statistics)
  end

  @doc """
  Returns quota information for a user's tier.
  """
  def get_user_quota(user) do
    user_role = Authorization.get_user_role(user)
    Map.get(@usage_tiers, user_role, @usage_tiers.public)
  end

  @impl true
  def init(config) do
    usage_config = build_usage_config(config)
    
    state = %__MODULE__{
      config: usage_config,
      usage_tracking: %{},
      quota_enforcement: initialize_quota_enforcement(),
      sliding_windows: %{}
    }

    # Schedule cleanup of old usage data
    schedule_usage_cleanup()

    Logger.info("Accounts.UsageLimiter initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:can_submit_evaluation, user}, _from, state) do
    user_id = get_user_id(user)
    user_role = Authorization.get_user_role(user)
    
    # Check if user has permission
    case Authorization.can_submit_evaluation?(user) do
      false ->
        {:reply, {:error, :permission_denied}, state}
      
      true ->
        # Check quota limits
        quota_check = check_user_quota(user_id, user_role, state)
        {:reply, quota_check, state}
    end
  end

  @impl true
  def handle_call({:get_user_usage, user}, _from, state) do
    user_id = get_user_id(user)
    user_usage = get_current_user_usage(user_id, state)
    
    {:reply, user_usage, state}
  end

  @impl true
  def handle_call(:get_system_usage_statistics, _from, state) do
    statistics = generate_system_statistics(state.usage_tracking, state.sliding_windows)
    {:reply, statistics, state}
  end

  @impl true
  def handle_cast({:record_evaluation_submitted, user, evaluation_id}, state) do
    user_id = get_user_id(user)
    
    # Record submission in usage tracking
    usage_entry = %{
      user_id: user_id,
      evaluation_id: evaluation_id,
      action: :submitted,
      timestamp: DateTime.utc_now()
    }
    
    new_usage_tracking = record_usage_entry(state.usage_tracking, usage_entry)
    
    # Update sliding windows
    new_sliding_windows = update_sliding_windows(state.sliding_windows, user_id, :submitted)
    
    # Log for audit
    AuditLogger.log_admin_action(:evaluation_submitted, user_id, %{
      evaluation_id: evaluation_id
    })

    new_state = %{state |
      usage_tracking: new_usage_tracking,
      sliding_windows: new_sliding_windows
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_evaluation_completed, user, evaluation_id}, state) do
    user_id = get_user_id(user)
    
    # Record completion in usage tracking
    usage_entry = %{
      user_id: user_id,
      evaluation_id: evaluation_id,
      action: :completed,
      timestamp: DateTime.utc_now()
    }
    
    new_usage_tracking = record_usage_entry(state.usage_tracking, usage_entry)
    
    # Update sliding windows
    new_sliding_windows = update_sliding_windows(state.sliding_windows, user_id, :completed)

    new_state = %{state |
      usage_tracking: new_usage_tracking,
      sliding_windows: new_sliding_windows
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_usage_data, state) do
    # Clean up old usage tracking data
    cutoff_time = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)  # 30 days
    
    cleaned_usage = clean_old_usage_data(state.usage_tracking, cutoff_time)
    cleaned_windows = clean_old_sliding_windows(state.sliding_windows, cutoff_time)
    
    # Schedule next cleanup
    schedule_usage_cleanup()
    
    new_state = %{state |
      usage_tracking: cleaned_usage,
      sliding_windows: cleaned_windows
    }

    {:noreply, new_state}
  end

  # Private functions

  defp build_usage_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      sliding_window_hours: 24,
      usage_cleanup_interval_hours: 6,
      quota_enforcement_enabled: true,
      real_time_tracking: true
    }
  end

  defp initialize_quota_enforcement do
    %{
      enabled: true,
      enforcement_level: :strict,
      grace_period_minutes: 5
    }
  end

  defp get_user_id(%{id: id}), do: id
  defp get_user_id(user) when is_binary(user), do: user
  defp get_user_id(_), do: nil

  defp check_user_quota(user_id, user_role, state) do
    quotas = Map.get(@usage_tiers, user_role, @usage_tiers.public)
    current_usage = get_current_user_usage(user_id, state)
    
    # Check each quota limit
    quota_checks = [
      check_hourly_quota(current_usage.hourly, quotas.evaluations_per_hour),
      check_daily_quota(current_usage.daily, quotas.evaluations_per_day),
      check_monthly_quota(current_usage.monthly, quotas.evaluations_per_month),
      check_concurrent_quota(current_usage.concurrent, quotas.concurrent_evaluations)
    ]
    
    case Enum.find(quota_checks, fn {status, _} -> status == :exceeded end) do
      nil ->
        {:ok, :quota_available}
      
      {_, limit_type} ->
        {:error, {:quota_exceeded, limit_type}}
    end
  end

  defp get_current_user_usage(user_id, state) do
    user_windows = Map.get(state.sliding_windows, user_id, %{})
    
    %{
      hourly: count_recent_evaluations(user_windows, :hour),
      daily: count_recent_evaluations(user_windows, :day),
      monthly: count_recent_evaluations(user_windows, :month),
      concurrent: count_concurrent_evaluations(user_windows)
    }
  end

  defp check_hourly_quota(_current, :unlimited), do: {:ok, :unlimited}
  defp check_hourly_quota(current, limit) when current >= limit, do: {:exceeded, :hourly}
  defp check_hourly_quota(_current, _limit), do: {:ok, :within_limit}

  defp check_daily_quota(_current, :unlimited), do: {:ok, :unlimited}
  defp check_daily_quota(current, limit) when current >= limit, do: {:exceeded, :daily}
  defp check_daily_quota(_current, _limit), do: {:ok, :within_limit}

  defp check_monthly_quota(_current, :unlimited), do: {:ok, :unlimited}
  defp check_monthly_quota(current, limit) when current >= limit, do: {:exceeded, :monthly}
  defp check_monthly_quota(_current, _limit), do: {:ok, :within_limit}

  defp check_concurrent_quota(_current, :unlimited), do: {:ok, :unlimited}
  defp check_concurrent_quota(current, limit) when current >= limit, do: {:exceeded, :concurrent}
  defp check_concurrent_quota(_current, _limit), do: {:ok, :within_limit}

  defp record_usage_entry(usage_tracking, entry) do
    user_entries = Map.get(usage_tracking, entry.user_id, [])
    updated_entries = [entry | user_entries] |> Enum.take(1000)  # Keep last 1000 per user
    
    Map.put(usage_tracking, entry.user_id, updated_entries)
  end

  defp update_sliding_windows(sliding_windows, user_id, action) do
    user_windows = Map.get(sliding_windows, user_id, %{
      hour: [],
      day: [],
      month: [],
      concurrent: []
    })
    
    timestamp = DateTime.utc_now()
    
    # Update appropriate windows based on action
    updated_windows = case action do
      :submitted ->
        %{user_windows |
          hour: [timestamp | user_windows.hour],
          day: [timestamp | user_windows.day],
          month: [timestamp | user_windows.month],
          concurrent: [timestamp | user_windows.concurrent]
        }
      
      :completed ->
        # Remove from concurrent tracking
        %{user_windows |
          concurrent: List.delete(user_windows.concurrent, timestamp)
        }
      
      _ ->
        user_windows
    end
    
    Map.put(sliding_windows, user_id, updated_windows)
  end

  defp count_recent_evaluations(user_windows, :hour) do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    count_since_time(Map.get(user_windows, :hour, []), cutoff)
  end

  defp count_recent_evaluations(user_windows, :day) do
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    count_since_time(Map.get(user_windows, :day, []), cutoff)
  end

  defp count_recent_evaluations(user_windows, :month) do
    cutoff = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)
    count_since_time(Map.get(user_windows, :month, []), cutoff)
  end

  defp count_concurrent_evaluations(user_windows) do
    length(Map.get(user_windows, :concurrent, []))
  end

  defp count_since_time(timestamps, cutoff_time) do
    timestamps
    |> Enum.count(fn timestamp ->
        DateTime.compare(timestamp, cutoff_time) == :gt
    end)
  end

  defp clean_old_usage_data(usage_tracking, cutoff_time) do
    usage_tracking
    |> Enum.map(fn {user_id, entries} ->
        cleaned_entries = Enum.filter(entries, fn entry ->
          DateTime.compare(entry.timestamp, cutoff_time) == :gt
        end)
        
        {user_id, cleaned_entries}
    end)
    |> Enum.filter(fn {_user_id, entries} -> entries != [] end)
    |> Enum.into(%{})
  end

  defp clean_old_sliding_windows(sliding_windows, cutoff_time) do
    sliding_windows
    |> Enum.map(fn {user_id, windows} ->
        cleaned_windows = %{
          hour: filter_timestamps(windows.hour, DateTime.add(cutoff_time, 23 * 3600, :second)),
          day: filter_timestamps(windows.day, DateTime.add(cutoff_time, 29 * 24 * 3600, :second)),
          month: filter_timestamps(windows.month, cutoff_time),
          concurrent: windows.concurrent  # Keep concurrent as-is
        }
        
        {user_id, cleaned_windows}
    end)
    |> Enum.into(%{})
  end

  defp filter_timestamps(timestamps, cutoff) do
    Enum.filter(timestamps, fn timestamp ->
      DateTime.compare(timestamp, cutoff) == :gt
    end)
  end

  defp generate_system_statistics(usage_tracking, sliding_windows) do
    %{
      total_users_tracked: map_size(usage_tracking),
      total_evaluations_tracked: count_total_evaluations(usage_tracking),
      active_users_last_hour: count_active_users(sliding_windows, :hour),
      active_users_last_day: count_active_users(sliding_windows, :day),
      usage_by_tier: calculate_usage_by_tier(sliding_windows),
      quota_violations: count_quota_violations(usage_tracking)
    }
  end

  defp count_total_evaluations(usage_tracking) do
    usage_tracking
    |> Enum.reduce(0, fn {_user_id, entries}, acc ->
        acc + length(entries)
    end)
  end

  defp count_active_users(sliding_windows, time_period) do
    sliding_windows
    |> Enum.count(fn {_user_id, windows} ->
        count_recent_evaluations(windows, time_period) > 0
    end)
  end

  defp calculate_usage_by_tier(_sliding_windows) do
    # Mock tier calculation - would determine user tiers from actual user data
    %{
      admin: :rand.uniform(5),
      researcher: :rand.uniform(20),
      public: :rand.uniform(100)
    }
  end

  defp count_quota_violations(_usage_tracking) do
    # Mock quota violation counting
    :rand.uniform(5)
  end

  defp schedule_usage_cleanup do
    Process.send_after(self(), :cleanup_usage_data, 6 * 60 * 60 * 1000)  # 6 hours
  end
end