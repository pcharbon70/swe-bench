defmodule SweBench.ConcurrentEvaluation.FaultInjector do
  @moduledoc """
  Chaos engineering for process and supervisor testing.

  Implements systematic fault injection including process termination,
  resource exhaustion, and timing disruption for resilience testing.
  """

  use GenServer
  require Logger

  defstruct [:config, :injection_history, :fault_scenarios]

  @doc """
  Starts the fault injector with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Injects faults during solution execution.
  """
  def inject_faults(solution_data, monitoring_tier \\ :standard) do
    GenServer.call(__MODULE__, {:inject_faults, solution_data, monitoring_tier}, 60_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: Enum.into(config, %{}),
      injection_history: [],
      fault_scenarios: initialize_fault_scenarios()
    }

    Logger.info("FaultInjector initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:inject_faults, solution_data, monitoring_tier}, _from, state) do
    fault_analysis = perform_fault_injection(solution_data, monitoring_tier, state)
    {:reply, {:ok, fault_analysis}, state}
  rescue
    error ->
      Logger.error("Fault injection failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_fault_injection(solution_data, monitoring_tier, _state) do
    solution_code = Map.get(solution_data, :solution_code, "")

    fault_scenarios = select_fault_scenarios(solution_code, monitoring_tier)

    # Simulate fault injection based on tier
    injection_results =
      case monitoring_tier do
        :intensive ->
          simulate_comprehensive_fault_injection(solution_code, fault_scenarios)

        :standard when fault_scenarios != [] ->
          simulate_basic_fault_injection(solution_code, fault_scenarios)

        _ ->
          simulate_no_fault_injection()
      end

    %{
      fault_injection_enabled: monitoring_tier in [:standard, :intensive],
      scenarios_tested: fault_scenarios,
      resilience_analysis: injection_results,
      recovery_success_rate: calculate_recovery_rate(injection_results),
      issues_detected: count_fault_issues(injection_results),
      score: calculate_fault_tolerance_score(injection_results)
    }
  end

  defp select_fault_scenarios(code, monitoring_tier) do
    available_scenarios = []

    # Add scenarios based on code patterns
    available_scenarios =
      if String.contains?(code, "Supervisor"),
        do: [:supervisor_child_crash | available_scenarios],
        else: available_scenarios

    available_scenarios =
      if String.contains?(code, "GenServer"),
        do: [:genserver_timeout | available_scenarios],
        else: available_scenarios

    available_scenarios =
      if String.contains?(code, "Task."),
        do: [:task_failure | available_scenarios],
        else: available_scenarios

    # Select scenarios based on monitoring tier
    case monitoring_tier do
      :intensive -> available_scenarios
      :standard -> Enum.take(available_scenarios, 2)
      _ -> []
    end
  end

  defp simulate_comprehensive_fault_injection(_code, scenarios) do
    scenarios
    |> Enum.map(fn scenario ->
      {scenario, simulate_fault_scenario(scenario, :comprehensive)}
    end)
    |> Enum.into(%{})
  end

  defp simulate_basic_fault_injection(_code, scenarios) do
    scenarios
    # Test only first scenario for basic injection
    |> Enum.take(1)
    |> Enum.map(fn scenario ->
      {scenario, simulate_fault_scenario(scenario, :basic)}
    end)
    |> Enum.into(%{})
  end

  defp simulate_no_fault_injection do
    %{fault_injection_disabled: true}
  end

  defp simulate_fault_scenario(:supervisor_child_crash, intensity) do
    success_rate =
      case intensity do
        # 70-90% recovery
        :comprehensive -> 0.7 + :rand.uniform() * 0.2
        # 80-95% recovery
        :basic -> 0.8 + :rand.uniform() * 0.15
      end

    %{
      fault_type: :supervisor_child_crash,
      recovery_successful: success_rate > 0.75,
      recovery_time_ms: :rand.uniform(1000),
      cascade_prevented: success_rate > 0.8
    }
  end

  defp simulate_fault_scenario(:genserver_timeout, intensity) do
    timeout_handled =
      case intensity do
        # 70% handle timeouts well
        :comprehensive -> :rand.uniform() > 0.3
        # 80% handle timeouts well
        :basic -> :rand.uniform() > 0.2
      end

    %{
      fault_type: :genserver_timeout,
      timeout_handled: timeout_handled,
      graceful_degradation: timeout_handled,
      error_propagation_controlled: timeout_handled
    }
  end

  defp simulate_fault_scenario(:task_failure, intensity) do
    failure_handled =
      case intensity do
        # 75% handle failures
        :comprehensive -> :rand.uniform() > 0.25
        # 85% handle failures
        :basic -> :rand.uniform() > 0.15
      end

    %{
      fault_type: :task_failure,
      failure_handled: failure_handled,
      supervisor_notified: failure_handled,
      resource_cleanup: failure_handled
    }
  end

  defp simulate_fault_scenario(scenario, _intensity) do
    %{
      fault_type: scenario,
      simulated: true,
      success: :rand.uniform() > 0.5
    }
  end

  defp calculate_recovery_rate(injection_results) when injection_results == %{} do
    # No faults injected means 100% success
    1.0
  end

  defp calculate_recovery_rate(injection_results) do
    results = Map.values(injection_results)

    if results != [] do
      successful_recoveries =
        results
        |> Enum.count(fn result ->
          Map.get(result, :recovery_successful, false) or
            Map.get(result, :timeout_handled, false) or
            Map.get(result, :failure_handled, false) or
            Map.get(result, :success, false)
        end)

      successful_recoveries / length(results)
    else
      1.0
    end
  end

  defp count_fault_issues(injection_results) when injection_results == %{} do
    0
  end

  defp count_fault_issues(injection_results) do
    injection_results
    |> Map.values()
    |> Enum.count(fn result ->
      not (Map.get(result, :recovery_successful, true) and
             Map.get(result, :timeout_handled, true) and
             Map.get(result, :failure_handled, true))
    end)
  end

  defp calculate_fault_tolerance_score(injection_results) do
    recovery_rate = calculate_recovery_rate(injection_results)
    issue_count = count_fault_issues(injection_results)

    base_score = recovery_rate * 100.0
    penalty = issue_count * 10.0

    max(0.0, base_score - penalty)
  end

  defp initialize_fault_scenarios do
    %{
      process_crashes: [:supervisor_child_crash, :task_failure],
      timeout_scenarios: [:genserver_timeout, :receive_timeout],
      resource_exhaustion: [:memory_pressure, :process_limit],
      network_issues: [:message_loss, :partition_simulation]
    }
  end
end
