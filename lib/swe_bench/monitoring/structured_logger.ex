defmodule SweBench.Monitoring.StructuredLogger do
  @moduledoc """
  Structured logging infrastructure with correlation and aggregation.

  Provides JSON-structured logging with trace correlation, security audit
  integration, and centralized log aggregation capabilities.
  """

  require Logger

  @log_fields [
    :timestamp, :level, :message, :module, :function, :line,
    :trace_id, :span_id, :user_id, :session_id, :evaluation_id,
    :repository, :model, :request_id, :ip_address
  ]

  @doc """
  Logs a structured message with automatic field extraction.
  """
  def log(level, message, metadata \\ %{}) when level in [:debug, :info, :warning, :error] do
    structured_entry = build_structured_entry(level, message, metadata)
    
    # Log through standard Logger
    Logger.log(level, format_structured_message(structured_entry), structured_entry.metadata)
    
    # Send to real-time monitoring if configured
    maybe_broadcast_log_event(structured_entry)
    
    :ok
  end

  @doc """
  Logs an evaluation-related event.
  """
  def log_evaluation_event(event_type, evaluation_id, message, metadata \\ %{}) do
    enhanced_metadata = Map.merge(metadata, %{
      event_type: event_type,
      evaluation_id: evaluation_id,
      category: :evaluation
    })
    
    log(:info, message, enhanced_metadata)
  end

  @doc """
  Logs a security event with appropriate severity.
  """
  def log_security_event(event_type, message, metadata \\ %{}) do
    severity = determine_security_severity(event_type)
    
    enhanced_metadata = Map.merge(metadata, %{
      event_type: event_type,
      category: :security,
      requires_audit: true
    })
    
    log(severity, message, enhanced_metadata)
  end

  @doc """
  Logs a system health event.
  """
  def log_system_event(component, status, message, metadata \\ %{}) do
    severity = if status in [:healthy, :ok], do: :info, else: :warning
    
    enhanced_metadata = Map.merge(metadata, %{
      component: component,
      status: status,
      category: :system_health
    })
    
    log(severity, message, enhanced_metadata)
  end

  @doc """
  Creates a trace context for distributed logging.
  """
  def create_trace_context(operation_name \\ "unknown") do
    %{
      trace_id: generate_trace_id(),
      span_id: generate_span_id(),
      operation_name: operation_name,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Adds trace context to metadata for correlation.
  """
  def with_trace_context(metadata, trace_context) do
    Map.merge(metadata, %{
      trace_id: trace_context.trace_id,
      span_id: trace_context.span_id,
      operation_name: trace_context.operation_name
    })
  end

  @doc """
  Configures log retention policies.
  """
  def configure_retention_policy(policy_config \\ %{}) do
    default_policy = %{
      debug_logs: %{retention_days: 7, compression: true},
      info_logs: %{retention_days: 30, compression: true},
      warning_logs: %{retention_days: 90, compression: false},
      error_logs: %{retention_days: 365, compression: false},
      security_logs: %{retention_days: 365, compression: false, backup: true}
    }
    
    Map.merge(default_policy, policy_config)
  end

  # Private functions

  defp build_structured_entry(level, message, metadata) do
    base_entry = %{
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      module: Map.get(metadata, :module, __MODULE__),
      function: Map.get(metadata, :function, "unknown"),
      line: Map.get(metadata, :line, 0),
      pid: inspect(self())
    }
    
    # Add optional fields if present
    optional_fields = Map.take(metadata, @log_fields)
    
    %{
      entry: Map.merge(base_entry, optional_fields),
      metadata: metadata
    }
  end

  defp format_structured_message(structured_entry) do
    entry = structured_entry.entry
    
    base_message = "[#{entry.timestamp}] #{String.upcase(to_string(entry.level))} #{entry.message}"
    
    # Add context if available
    context_parts = []
    
    context_parts = if entry[:trace_id] do
      ["trace_id=#{entry.trace_id}" | context_parts]
    else
      context_parts
    end
    
    context_parts = if entry[:evaluation_id] do
      ["eval_id=#{entry.evaluation_id}" | context_parts]
    else
      context_parts
    end
    
    context_parts = if entry[:user_id] do
      ["user_id=#{entry.user_id}" | context_parts]
    else
      context_parts
    end
    
    if context_parts != [] do
      base_message <> " [" <> Enum.join(context_parts, ", ") <> "]"
    else
      base_message
    end
  end

  defp determine_security_severity(:login_failed), do: :warning
  defp determine_security_severity(:unauthorized_access), do: :error
  defp determine_security_severity(:suspicious_activity), do: :error
  defp determine_security_severity(:admin_action), do: :info
  defp determine_security_severity(_), do: :info

  defp maybe_broadcast_log_event(structured_entry) do
    # Broadcast high-severity logs to real-time monitoring
    if structured_entry.entry.level in [:warning, :error] do
      :telemetry.execute([:swe_bench, :monitoring, :log_event], %{
        level: structured_entry.entry.level,
        timestamp: structured_entry.entry.timestamp
      }, structured_entry.metadata)
    end
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end