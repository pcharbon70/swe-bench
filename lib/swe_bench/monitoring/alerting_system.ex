defmodule SweBench.Monitoring.AlertingSystem do
  @moduledoc """
  Comprehensive alerting system with SLI/SLO monitoring.

  Implements alert rules, escalation policies, and integration
  with external notification systems for proactive monitoring.
  """

  use GenServer
  require Logger

  alias SweBench.Monitoring.MetricsCollector

  defstruct [
    :config,
    :alert_rules,
    :active_alerts,
    :notification_channels,
    :slo_tracking
  ]

  @slos %{
    # System availability
    system_availability: %{
      target: 99.9,  # 99.9% uptime
      measurement_window: :monthly,
      alert_threshold: 99.5
    },
    
    # Response time performance
    response_time_p95: %{
      target: 500,  # 500ms P95 response time
      measurement_window: :hourly,
      alert_threshold: 1000  # Alert if >1s
    },
    
    # Evaluation throughput
    evaluation_throughput: %{
      target: 100,  # 100 evaluations/hour
      measurement_window: :hourly,
      alert_threshold: 50  # Alert if <50/hour
    },
    
    # Error rate
    error_rate: %{
      target: 1.0,  # <1% error rate
      measurement_window: :hourly,
      alert_threshold: 5.0  # Alert if >5%
    }
  }

  @alert_rules [
    %{
      name: "high_evaluation_queue_depth",
      condition: {:greater_than, :evaluation_queue_depth, 20},
      severity: :warning,
      message: "Evaluation queue depth is high (>20)"
    },
    %{
      name: "low_evaluation_throughput",
      condition: {:less_than, :evaluations_completed_total, 50},
      severity: :critical,
      message: "Evaluation throughput is below threshold (<50/hour)"
    },
    %{
      name: "high_memory_usage",
      condition: {:greater_than, :memory_usage_bytes, 30_000_000_000},  # 30GB
      severity: :warning,
      message: "High memory usage detected (>30GB)"
    },
    %{
      name: "websocket_connection_issues",
      condition: {:less_than, :websocket_connections_active, 10},
      severity: :warning,
      message: "Low WebSocket connection count may indicate connectivity issues"
    },
    %{
      name: "container_pool_exhaustion",
      condition: {:greater_than, :container_utilization_percent, 90},
      severity: :critical,
      message: "Container pool utilization is critically high (>90%)"
    }
  ]

  @doc """
  Starts the alerting system with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Evaluates alert rules against current metrics.
  """
  def evaluate_alert_rules do
    GenServer.cast(__MODULE__, :evaluate_alert_rules)
  end

  @doc """
  Sends a custom alert.
  """
  def send_alert(alert_name, severity, message, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:send_alert, alert_name, severity, message, metadata})
  end

  @doc """
  Returns current SLO status.
  """
  def get_slo_status do
    GenServer.call(__MODULE__, :get_slo_status)
  end

  @doc """
  Returns active alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end

  @impl true
  def init(config) do
    alerting_config = build_alerting_config(config)
    
    state = %__MODULE__{
      config: alerting_config,
      alert_rules: @alert_rules,
      active_alerts: %{},
      notification_channels: initialize_notification_channels(alerting_config),
      slo_tracking: initialize_slo_tracking()
    }

    # Schedule periodic alert rule evaluation
    schedule_alert_evaluation()

    Logger.info("Monitoring.AlertingSystem initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast(:evaluate_alert_rules, state) do
    # Get current metrics
    current_metrics = MetricsCollector.get_metrics_summary()
    
    # Evaluate each alert rule
    new_alerts = evaluate_rules_against_metrics(state.alert_rules, current_metrics, state.active_alerts)
    
    # Update SLO tracking
    updated_slo_tracking = update_slo_measurements(state.slo_tracking, current_metrics)

    new_state = %{state |
      active_alerts: new_alerts,
      slo_tracking: updated_slo_tracking
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:send_alert, alert_name, severity, message, metadata}, state) do
    alert = %{
      name: alert_name,
      severity: severity,
      message: message,
      metadata: metadata,
      triggered_at: DateTime.utc_now(),
      status: :active
    }
    
    # Send to notification channels
    send_to_notification_channels(alert, state.notification_channels)
    
    # Store active alert
    new_alerts = Map.put(state.active_alerts, alert_name, alert)

    new_state = %{state | active_alerts: new_alerts}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_slo_status, _from, state) do
    slo_status = calculate_slo_status(state.slo_tracking)
    {:reply, slo_status, state}
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    {:reply, Map.values(state.active_alerts), state}
  end

  @impl true
  def handle_info(:evaluate_alert_rules_periodic, state) do
    # Periodic alert rule evaluation
    GenServer.cast(self(), :evaluate_alert_rules)
    
    # Schedule next evaluation
    schedule_alert_evaluation()
    
    {:noreply, state}
  end

  # Private functions

  defp build_alerting_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      alert_evaluation_interval_ms: 30_000,  # 30 seconds
      notification_channels: [:log, :slack],
      slo_calculation_enabled: true,
      alert_deduplication_enabled: true
    }
  end

  defp initialize_notification_channels(config) do
    channels = Map.get(config, :notification_channels, [:log])
    
    channels
    |> Enum.map(fn channel ->
        {channel, %{enabled: true, last_notification: nil}}
    end)
    |> Enum.into(%{})
  end

  defp initialize_slo_tracking do
    @slos
    |> Enum.map(fn {slo_name, slo_config} ->
        {slo_name, %{
          config: slo_config,
          measurements: [],
          current_value: 0.0,
          status: :healthy
        }}
    end)
    |> Enum.into(%{})
  end

  defp evaluate_rules_against_metrics(alert_rules, current_metrics, active_alerts) do
    latest_values = Map.get(current_metrics, :latest_values, %{})
    
    Enum.reduce(alert_rules, active_alerts, fn rule, alerts ->
      case evaluate_single_rule(rule, latest_values) do
        {:triggered, alert_data} ->
          # New alert triggered
          send_to_notification_channels(alert_data, %{})
          Map.put(alerts, rule.name, alert_data)
        
        {:resolved, _} ->
          # Alert resolved
          Map.delete(alerts, rule.name)
        
        _ ->
          # No change in alert status
          alerts
      end
    end)
  end

  defp evaluate_single_rule(rule, metric_values) do
    {comparison, metric_name, threshold} = rule.condition
    current_value = Map.get(metric_values, metric_name, 0)
    
    alert_triggered = case comparison do
      :greater_than -> current_value > threshold
      :less_than -> current_value < threshold
      :equals -> current_value == threshold
      _ -> false
    end
    
    if alert_triggered do
      alert_data = %{
        name: rule.name,
        severity: rule.severity,
        message: rule.message,
        current_value: current_value,
        threshold: threshold,
        triggered_at: DateTime.utc_now(),
        status: :active
      }
      
      {:triggered, alert_data}
    else
      {:resolved, rule.name}
    end
  end

  defp send_to_notification_channels(alert, notification_channels) do
    # Log alert
    Logger.warning("ALERT: #{alert.name} - #{alert.message}")
    
    # Send to configured channels
    Enum.each(notification_channels, fn {channel, config} ->
      if config.enabled do
        send_to_channel(channel, alert)
      end
    end)
  end

  defp send_to_channel(:log, alert) do
    Logger.warning("Alert #{alert.name}: #{alert.message}")
  end

  defp send_to_channel(:slack, alert) do
    # Mock Slack notification - would integrate with actual Slack API
    Logger.info("Sending Slack notification for alert: #{alert.name}")
  end

  defp send_to_channel(:pagerduty, alert) do
    # Mock PagerDuty notification - would integrate with actual PagerDuty API
    Logger.info("Sending PagerDuty alert: #{alert.name}")
  end

  defp send_to_channel(_channel, _alert) do
    # Unknown channel
    :ok
  end

  defp update_slo_measurements(slo_tracking, current_metrics) do
    latest_values = Map.get(current_metrics, :latest_values, %{})
    
    slo_tracking
    |> Enum.map(fn {slo_name, slo_data} ->
        updated_slo = update_single_slo(slo_name, slo_data, latest_values)
        {slo_name, updated_slo}
    end)
    |> Enum.into(%{})
  end

  defp update_single_slo(slo_name, slo_data, metric_values) do
    # Update SLO based on current metrics
    current_value = case slo_name do
      :system_availability ->
        # Calculate availability based on successful requests
        calculate_availability(metric_values)
      
      :response_time_p95 ->
        # Get P95 response time
        Map.get(metric_values, :phoenix_request_duration, 0) / 1_000_000  # Convert to ms
      
      :evaluation_throughput ->
        # Get evaluation completion rate
        Map.get(metric_values, :evaluations_completed_total, 0)
      
      :error_rate ->
        # Calculate error rate
        calculate_error_rate(metric_values)
      
      _ ->
        0.0
    end
    
    new_measurements = [current_value | slo_data.measurements] |> Enum.take(100)
    slo_status = if current_value < slo_data.config.alert_threshold, do: :breached, else: :healthy
    
    %{slo_data |
      measurements: new_measurements,
      current_value: current_value,
      status: slo_status
    }
  end

  defp calculate_availability(_metric_values) do
    # Mock availability calculation
    base_availability = 99.5 + :rand.uniform() * 0.4  # 99.5-99.9%
    max(95.0, base_availability)
  end

  defp calculate_error_rate(_metric_values) do
    # Mock error rate calculation
    :rand.uniform() * 2.0  # 0-2% error rate
  end

  defp calculate_slo_status(slo_tracking) do
    slo_tracking
    |> Enum.map(fn {slo_name, slo_data} ->
        compliance_percentage = calculate_slo_compliance(slo_data)
        
        {slo_name, %{
          target: slo_data.config.target,
          current_value: slo_data.current_value,
          status: slo_data.status,
          compliance_percentage: compliance_percentage
        }}
    end)
    |> Enum.into(%{})
  end

  defp calculate_slo_compliance(slo_data) do
    if slo_data.measurements == [] do
      100.0
    else
      target = slo_data.config.target
      
      compliant_measurements = slo_data.measurements
      |> Enum.count(fn measurement ->
          measurement >= target
      end)
      
      compliant_measurements / length(slo_data.measurements) * 100.0
    end
  end

  defp schedule_alert_evaluation do
    Process.send_after(self(), :evaluate_alert_rules_periodic, 30_000)  # 30 seconds
  end
end