defmodule SweBench.Accounts.AuditLogger do
  @moduledoc """
  Comprehensive audit logging for admin actions and security events.

  Provides secure audit trail for compliance, security monitoring,
  and administrative oversight of system operations.
  """

  use GenServer
  require Logger

  alias SweBench.RealTimeEvents.EventBroadcaster

  defstruct [
    :config,
    :audit_log,
    :security_events,
    :retention_policy
  ]

  @audit_event_types [
    # Authentication events
    :user_login,
    :user_logout,
    :login_failed,
    :password_changed,
    :oauth_login,
    :two_factor_enabled,
    :two_factor_disabled,

    # Session events
    :session_created,
    :session_expired,
    :session_ended,
    :session_extended,
    :session_hijack_detected,

    # Authorization events
    :access_granted,
    :access_denied,
    :role_changed,
    :permission_escalation,
    :unauthorized_access_attempt,

    # Administrative actions
    :evaluation_submitted,
    :evaluation_cancelled,
    :system_settings_changed,
    :user_created,
    :user_deleted,
    :user_role_modified,

    # Security events
    :suspicious_activity,
    :rate_limit_exceeded,
    :security_scan_detected,
    :data_export_requested,
    :admin_action_performed
  ]

  @doc """
  Starts the audit logger with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Logs an authentication event.
  """
  def log_auth_event(event_type, user_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:log_event, :authentication, event_type, user_id, metadata})
  end

  @doc """
  Logs a session event.
  """
  def log_session_event(event_type, user_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:log_event, :session, event_type, user_id, metadata})
  end

  @doc """
  Logs an authorization event.
  """
  def log_authorization_event(event_type, user_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:log_event, :authorization, event_type, user_id, metadata})
  end

  @doc """
  Logs an administrative action.
  """
  def log_admin_action(action_type, user_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:log_event, :admin_action, action_type, user_id, metadata})
  end

  @doc """
  Logs a security event.
  """
  def log_security_event(event_type, user_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:log_event, :security, event_type, user_id, metadata})
  end

  @doc """
  Retrieves audit log entries with filtering.
  """
  def get_audit_log(filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_audit_log, filters})
  end

  @doc """
  Returns audit statistics and metrics.
  """
  def get_audit_statistics do
    GenServer.call(__MODULE__, :get_audit_statistics)
  end

  @impl true
  def init(config) do
    audit_config = build_audit_config(config)

    state = %__MODULE__{
      config: audit_config,
      audit_log: [],
      security_events: %{},
      retention_policy: build_retention_policy(audit_config)
    }

    # Schedule log cleanup
    schedule_log_cleanup()

    Logger.info("Accounts.AuditLogger initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast({:log_event, category, event_type, user_id, metadata}, state) do
    audit_entry = create_audit_entry(category, event_type, user_id, metadata)

    # Add to audit log
    new_audit_log =
      [audit_entry | state.audit_log]
      |> Enum.take(state.config.max_log_entries)

    # Update security event tracking
    new_security_events = update_security_tracking(state.security_events, audit_entry)

    # Broadcast security events for real-time monitoring
    if should_broadcast_event?(audit_entry) do
      EventBroadcaster.broadcast_system_health(%{
        status: :security_event,
        event_type: audit_entry.event_type,
        user_id: audit_entry.user_id,
        timestamp: audit_entry.timestamp
      })
    end

    # Persist if configured
    if state.config.persistent_storage do
      persist_audit_entry(audit_entry)
    end

    new_state = %{state | audit_log: new_audit_log, security_events: new_security_events}

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_audit_log, filters}, _from, state) do
    filtered_log = apply_log_filters(state.audit_log, filters)
    {:reply, filtered_log, state}
  end

  @impl true
  def handle_call(:get_audit_statistics, _from, state) do
    statistics = generate_audit_statistics(state.audit_log, state.security_events)
    {:reply, statistics, state}
  end

  @impl true
  def handle_info(:cleanup_old_logs, state) do
    # Clean up old audit entries based on retention policy
    cutoff_time =
      DateTime.add(DateTime.utc_now(), -state.retention_policy.days * 24 * 3600, :second)

    cleaned_log =
      state.audit_log
      |> Enum.filter(fn entry ->
        DateTime.compare(entry.timestamp, cutoff_time) == :gt
      end)

    # Schedule next cleanup
    schedule_log_cleanup()

    new_state = %{state | audit_log: cleaned_log}

    Logger.debug("Cleaned up old audit entries, current size: #{length(cleaned_log)}")
    {:noreply, new_state}
  end

  # Private functions

  defp build_audit_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      max_log_entries: 10_000,
      # Would integrate with database
      persistent_storage: false,
      real_time_broadcasting: true,
      security_alerting: true,
      retention_days: 90
    }
  end

  defp build_retention_policy(config) do
    %{
      days: Map.get(config, :retention_days, 90),
      cleanup_interval_hours: 24
    }
  end

  defp create_audit_entry(category, event_type, user_id, metadata) do
    %{
      id: generate_audit_id(),
      category: category,
      event_type: event_type,
      user_id: user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: Map.get(metadata, :ip_address),
      user_agent: Map.get(metadata, :user_agent),
      severity: determine_event_severity(event_type)
    }
  end

  defp determine_event_severity(event_type) do
    case event_type do
      type when type in [:login_failed, :unauthorized_access_attempt, :suspicious_activity] ->
        :high

      type when type in [:permission_escalation, :role_changed, :security_scan_detected] ->
        :medium

      type when type in [:user_login, :user_logout, :session_created] ->
        :low

      _ ->
        :info
    end
  end

  defp update_security_tracking(security_events, audit_entry) do
    case audit_entry.severity do
      severity when severity in [:high, :medium] ->
        # Track security events for alerting
        user_events = Map.get(security_events, audit_entry.user_id, [])
        updated_user_events = [audit_entry | user_events] |> Enum.take(100)

        Map.put(security_events, audit_entry.user_id, updated_user_events)

      _ ->
        security_events
    end
  end

  defp should_broadcast_event?(audit_entry) do
    # Broadcast high-severity events for real-time monitoring
    audit_entry.severity in [:high, :medium]
  end

  defp apply_log_filters(audit_log, filters) do
    audit_log
    |> filter_by_category(Map.get(filters, :category))
    |> filter_by_user(Map.get(filters, :user_id))
    |> filter_by_time_range(Map.get(filters, :start_time), Map.get(filters, :end_time))
    |> filter_by_severity(Map.get(filters, :severity))
  end

  defp filter_by_category(log, nil), do: log

  defp filter_by_category(log, category) do
    Enum.filter(log, fn entry -> entry.category == category end)
  end

  defp filter_by_user(log, nil), do: log

  defp filter_by_user(log, user_id) do
    Enum.filter(log, fn entry -> entry.user_id == user_id end)
  end

  defp filter_by_time_range(log, nil, nil), do: log

  defp filter_by_time_range(log, start_time, end_time) do
    Enum.filter(log, fn entry ->
      after_start =
        if start_time, do: DateTime.compare(entry.timestamp, start_time) != :lt, else: true

      before_end = if end_time, do: DateTime.compare(entry.timestamp, end_time) != :gt, else: true
      after_start and before_end
    end)
  end

  defp filter_by_severity(log, nil), do: log

  defp filter_by_severity(log, severity) do
    Enum.filter(log, fn entry -> entry.severity == severity end)
  end

  defp generate_audit_statistics(audit_log, security_events) do
    %{
      total_entries: length(audit_log),
      entries_by_category: count_by_category(audit_log),
      entries_by_severity: count_by_severity(audit_log),
      security_events_count: map_size(security_events),
      recent_activity: get_recent_activity(audit_log),
      top_event_types: get_top_event_types(audit_log)
    }
  end

  defp count_by_category(audit_log) do
    audit_log
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, entries} -> {category, length(entries)} end)
    |> Enum.into(%{})
  end

  defp count_by_severity(audit_log) do
    audit_log
    |> Enum.group_by(& &1.severity)
    |> Enum.map(fn {severity, entries} -> {severity, length(entries)} end)
    |> Enum.into(%{})
  end

  defp get_recent_activity(audit_log) do
    audit_log
    |> Enum.take(10)
    |> Enum.map(fn entry ->
      %{
        event_type: entry.event_type,
        user_id: entry.user_id,
        timestamp: entry.timestamp,
        severity: entry.severity
      }
    end)
  end

  defp get_top_event_types(audit_log) do
    audit_log
    |> Enum.group_by(& &1.event_type)
    |> Enum.map(fn {event_type, entries} -> {event_type, length(entries)} end)
    |> Enum.sort_by(fn {_type, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp persist_audit_entry(audit_entry) do
    # Mock persistence - would integrate with actual database
    Logger.debug("Persisting audit entry: #{audit_entry.id}")
    :ok
  end

  defp schedule_log_cleanup do
    # 24 hours
    Process.send_after(self(), :cleanup_old_logs, 24 * 60 * 60 * 1000)
  end

  defp generate_audit_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
