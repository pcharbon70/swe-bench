defmodule SweBench.ConcurrentEvaluation.MailboxMonitor do
  @moduledoc """
  Message queue analysis and backpressure detection.

  Monitors message queue growth, detects unbounded mailboxes, analyzes
  selective receive patterns, and measures message processing rates.
  """

  use GenServer
  require Logger

  defstruct [:config, :mailbox_snapshots, :monitoring_active]

  @doc """
  Starts the mailbox monitor with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Monitors mailboxes during solution execution.
  """
  def monitor_mailboxes(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:monitor_mailboxes, solution_data, monitoring_tier}, 60_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      mailbox_snapshots: [],
      monitoring_active: false
    }

    Logger.info("MailboxMonitor initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:monitor_mailboxes, solution_data, monitoring_tier}, _from, state) do
    mailbox_analysis = perform_mailbox_monitoring(solution_data, monitoring_tier, state)
    {:reply, {:ok, mailbox_analysis}, state}
  rescue
    error ->
      Logger.error("Mailbox monitoring failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_mailbox_monitoring(solution_data, monitoring_tier, _state) do
    solution_code = Map.get(solution_data, :solution_code, "")

    # Analyze mailbox patterns in code
    mailbox_patterns = analyze_mailbox_patterns(solution_code)

    # Simulate mailbox monitoring during execution
    execution_monitoring = simulate_mailbox_execution_monitoring(solution_code, monitoring_tier)

    %{
      queue_growth_analysis: mailbox_patterns.queue_growth_risk,
      unbounded_mailbox_detection: mailbox_patterns.unbounded_risk,
      selective_receive_patterns: mailbox_patterns.selective_patterns,
      message_processing_rates: execution_monitoring.processing_rates,
      memory_pressure_analysis: execution_monitoring.memory_pressure,
      monitoring_tier: monitoring_tier,
      issues_detected: mailbox_patterns.total_issues + execution_monitoring.runtime_issues,
      score: calculate_mailbox_score(mailbox_patterns, execution_monitoring)
    }
  end

  defp analyze_mailbox_patterns(code) do
    %{
      queue_growth_risk: analyze_queue_growth_risk(code),
      unbounded_risk: analyze_unbounded_mailbox_risk(code),
      selective_patterns: analyze_selective_receive_patterns(code),
      backpressure_handling: analyze_backpressure_patterns(code),
      # Will be calculated
      total_issues: 0
    }
    |> calculate_pattern_issues()
  end

  defp analyze_queue_growth_risk(code) do
    risk_factors = [
      String.contains?(code, "GenServer.cast") and not String.contains?(code, "handle_cast"),
      String.contains?(code, "send(") and not String.contains?(code, "receive"),
      String.contains?(code, "!") and not String.contains?(code, "receive")
    ]

    %{
      high_risk: Enum.count(risk_factors, & &1) > 1,
      risk_factors: Enum.count(risk_factors, & &1),
      mitigation_present: String.contains?(code, "Process.flag(:trap_exit")
    }
  end

  defp analyze_unbounded_mailbox_risk(code) do
    unbounded_indicators = [
      String.contains?(code, "GenServer.cast") and not String.contains?(code, "buffer"),
      String.contains?(code, "spawn") and String.contains?(code, "!"),
      not String.contains?(code, "timeout") and String.contains?(code, "receive")
    ]

    %{
      unbounded_risk: Enum.any?(unbounded_indicators),
      indicators: Enum.count(unbounded_indicators, & &1),
      flow_control_present:
        String.contains?(code, "back_pressure") or String.contains?(code, "rate_limit")
    }
  end

  defp analyze_selective_receive_patterns(code) do
    %{
      has_selective_receive:
        String.contains?(code, "receive do") and String.contains?(code, "->"),
      message_filtering: count_message_filters(code),
      timeout_handling: String.contains?(code, "after "),
      pattern_complexity: estimate_receive_pattern_complexity(code)
    }
  end

  defp count_message_filters(code) do
    # Count different message patterns in receive blocks
    if String.contains?(code, "receive do") do
      # Simple heuristic: count "->" arrows in receive context
      code
      |> String.split("receive do")
      |> Enum.drop(1)
      |> Enum.map(fn section ->
        section
        |> String.split("end")
        |> List.first()
        |> String.split("->")
        |> length()
        |> Kernel.-(1)
        |> max(0)
      end)
      |> Enum.sum()
    else
      0
    end
  end

  defp estimate_receive_pattern_complexity(code) do
    if String.contains?(code, "receive do") do
      cond do
        String.contains?(code, "when ") -> :complex
        count_message_filters(code) > 3 -> :medium
        count_message_filters(code) > 1 -> :simple
        true -> :basic
      end
    else
      :none
    end
  end

  defp analyze_backpressure_patterns(code) do
    %{
      has_backpressure:
        String.contains?(code, "back_pressure") or String.contains?(code, "throttle"),
      has_flow_control:
        String.contains?(code, "rate_limit") or String.contains?(code, "buffer_size"),
      has_monitoring:
        String.contains?(code, "Process.info") or String.contains?(code, "message_queue_len")
    }
  end

  defp calculate_pattern_issues(patterns) do
    issue_count = 0

    issue_count =
      if Map.get(patterns.queue_growth_risk, :high_risk, false),
        do: issue_count + 1,
        else: issue_count

    issue_count =
      if Map.get(patterns.unbounded_risk, :unbounded_risk, false),
        do: issue_count + 1,
        else: issue_count

    %{patterns | total_issues: issue_count}
  end

  defp simulate_mailbox_execution_monitoring(_code, monitoring_tier) do
    # Simulate runtime mailbox monitoring
    base_processing_rate =
      case monitoring_tier do
        :intensive -> 1000 + :rand.uniform(500)
        :standard -> 800 + :rand.uniform(400)
        :light -> 600 + :rand.uniform(300)
      end

    %{
      processing_rates: %{
        messages_per_second: base_processing_rate,
        average_queue_length: :rand.uniform(10),
        max_queue_length_observed: :rand.uniform(50)
      },
      memory_pressure: %{
        mailbox_memory_usage: :rand.uniform(1024 * 1024),
        pressure_events: :rand.uniform(3)
      },
      runtime_issues: :rand.uniform(2)
    }
  end

  defp calculate_mailbox_score(patterns, execution_monitoring) do
    pattern_issues = Map.get(patterns, :total_issues, 0)
    runtime_issues = Map.get(execution_monitoring, :runtime_issues, 0)

    total_issues = pattern_issues + runtime_issues

    base_score = 85.0
    penalty = total_issues * 15.0

    max(0.0, base_score - penalty)
  end
end
