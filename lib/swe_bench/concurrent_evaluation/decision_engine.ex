defmodule SweBench.ConcurrentEvaluation.DecisionEngine do
  @moduledoc """
  Smart monitoring activation based on code analysis.

  Determines appropriate monitoring tier (light/standard/intensive) based on
  solution complexity, concurrency patterns, and evaluation requirements.
  """

  require Logger

  @light_monitoring %{
    process_sampling_rate: 0.1,
    metrics_interval: 5000,
    deadlock_check_interval: 10_000,
    race_detection: :statistical,
    fault_injection: false
  }

  @standard_monitoring %{
    process_sampling_rate: 0.3,
    metrics_interval: 2000,
    deadlock_check_interval: 5000,
    race_detection: :pattern_based,
    fault_injection: :basic
  }

  @intensive_monitoring %{
    process_sampling_rate: 0.7,
    metrics_interval: 1000,
    deadlock_check_interval: 2000,
    race_detection: :comprehensive,
    fault_injection: :comprehensive
  }

  @doc """
  Determines the appropriate monitoring tier for the given solution.
  """
  def determine_monitoring_tier(solution_data, options \\ []) do
    # Extract concurrency indicators from solution data
    concurrency_score = analyze_concurrency_complexity(solution_data)
    user_preference = Keyword.get(options, :monitoring_tier)

    # Determine tier based on analysis and user preference
    tier =
      case {concurrency_score, user_preference} do
        {_, tier} when tier in [:light, :standard, :intensive] ->
          tier

        {score, _} when score >= 80 ->
          :intensive

        {score, _} when score >= 40 ->
          :standard

        _ ->
          :light
      end

    Logger.debug("Determined monitoring tier: #{tier} (complexity score: #{concurrency_score})")
    tier
  end

  @doc """
  Returns monitoring configuration for the given tier.
  """
  def get_monitoring_config(:light), do: @light_monitoring
  def get_monitoring_config(:standard), do: @standard_monitoring
  def get_monitoring_config(:intensive), do: @intensive_monitoring
  def get_monitoring_config(_), do: @standard_monitoring

  @doc """
  Analyzes if solution requires concurrent evaluation.
  """
  def requires_concurrent_evaluation?(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    concurrency_indicators = [
      has_process_spawning?(solution_code),
      has_genserver_usage?(solution_code),
      has_ets_operations?(solution_code),
      has_message_passing?(solution_code),
      has_supervision_trees?(solution_code),
      has_concurrent_libraries?(solution_code)
    ]

    concurrent_indicator_count = Enum.count(concurrency_indicators, & &1)
    concurrent_indicator_count > 0
  end

  # Private functions

  defp analyze_concurrency_complexity(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    complexity_factors = %{
      process_spawning: score_process_spawning(solution_code),
      genserver_usage: score_genserver_usage(solution_code),
      ets_operations: score_ets_operations(solution_code),
      message_passing: score_message_passing(solution_code),
      supervision_trees: score_supervision_trees(solution_code),
      concurrent_libraries: score_concurrent_libraries(solution_code),
      async_operations: score_async_operations(solution_code)
    }

    # Calculate weighted complexity score
    weights = %{
      process_spawning: 0.20,
      genserver_usage: 0.25,
      ets_operations: 0.15,
      message_passing: 0.15,
      supervision_trees: 0.15,
      concurrent_libraries: 0.05,
      async_operations: 0.05
    }

    weighted_score =
      complexity_factors
      |> Enum.reduce(0.0, fn {factor, score}, acc ->
        weight = Map.get(weights, factor, 0.0)
        acc + score * weight
      end)

    min(100.0, weighted_score)
  end

  defp has_process_spawning?(code) do
    String.contains?(code, "spawn") or
      String.contains?(code, "Task.") or
      String.contains?(code, "Agent.")
  end

  defp score_process_spawning(code) do
    spawn_patterns = [
      {"spawn", 20},
      {"spawn_link", 25},
      {"Task.async", 30},
      {"Task.start", 25},
      {"Agent.start", 20},
      {"GenServer.start", 15}
    ]

    spawn_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp has_genserver_usage?(code) do
    String.contains?(code, "GenServer") or
      String.contains?(code, "use GenServer") or
      String.contains?(code, "GenServer.call") or
      String.contains?(code, "GenServer.cast")
  end

  defp score_genserver_usage(code) do
    genserver_patterns = [
      {"use GenServer", 40},
      {"GenServer.call", 25},
      {"GenServer.cast", 30},
      {"handle_call", 20},
      {"handle_cast", 20},
      {"handle_info", 15}
    ]

    genserver_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp has_ets_operations?(code) do
    String.contains?(code, ":ets.") or String.contains?(code, "ETS")
  end

  defp score_ets_operations(code) do
    ets_patterns = [
      {":ets.new", 30},
      {":ets.insert", 20},
      {":ets.lookup", 15},
      {":ets.delete", 20},
      {":ets.select", 25}
    ]

    ets_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp has_message_passing?(code) do
    String.contains?(code, "send") or
      String.contains?(code, "receive") or
      String.contains?(code, "!")
  end

  defp score_message_passing(code) do
    message_patterns = [
      {"send(", 25},
      {"receive do", 30},
      {" ! ", 20},
      {"after ", 15}
    ]

    message_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp has_supervision_trees?(code) do
    String.contains?(code, "Supervisor") or
      String.contains?(code, "DynamicSupervisor")
  end

  defp score_supervision_trees(code) do
    supervision_patterns = [
      {"use Supervisor", 40},
      {"Supervisor.start_link", 30},
      {"DynamicSupervisor", 35},
      {"child_spec", 20},
      {"restart:", 15}
    ]

    supervision_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp has_concurrent_libraries?(code) do
    String.contains?(code, "Registry") or
      String.contains?(code, "DynamicSupervisor") or
      String.contains?(code, "Task.Supervisor")
  end

  defp score_concurrent_libraries(code) do
    library_patterns = [
      {"Registry", 25},
      {"Task.Supervisor", 30},
      {"DynamicSupervisor", 35},
      {"ConCache", 20}
    ]

    library_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end

  defp score_async_operations(code) do
    async_patterns = [
      {"async", 20},
      {"await", 15},
      {"stream", 10}
    ]

    async_patterns
    |> Enum.reduce(0, fn {pattern, score}, acc ->
      if String.contains?(code, pattern), do: acc + score, else: acc
    end)
    |> min(100)
  end
end
