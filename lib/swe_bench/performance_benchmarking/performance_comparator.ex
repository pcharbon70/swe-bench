defmodule SweBench.PerformanceBenchmarking.PerformanceComparator do
  @moduledoc """
  Compares performance between implementations with statistical analysis.

  Provides baseline establishment, performance delta calculation, and
  regression detection for comprehensive performance assessment.
  """

  use GenServer
  require Logger

  defstruct [
    :baseline_cache,
    :comparison_history,
    :comparison_statistics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compares performance between original and generated implementations.
  """
  def compare_implementations(original_impl, generated_impl, comparison_spec) do
    GenServer.call(
      __MODULE__,
      {:compare_implementations, original_impl, generated_impl, comparison_spec}
    )
  end

  @doc """
  Establishes performance baseline for an implementation.
  """
  def establish_baseline(implementation, baseline_spec) do
    GenServer.call(__MODULE__, {:establish_baseline, implementation, baseline_spec})
  end

  @doc """
  Gets performance comparison statistics.
  """
  def get_comparison_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      baseline_cache: %{},
      comparison_history: [],
      comparison_statistics: %{
        total_comparisons: 0,
        performance_improvements: 0,
        performance_regressions: 0,
        avg_performance_delta: 0.0
      }
    }

    Logger.info("Performance comparator started")
    {:ok, state}
  end

  @impl true
  def handle_call(
        {:compare_implementations, original_impl, generated_impl, comparison_spec},
        _from,
        state
      ) do
    comparison_id = generate_comparison_id()
    Logger.debug("Comparing implementations #{comparison_id}")

    result =
      original_impl
      |> benchmark_implementation("original", comparison_spec)
      |> benchmark_generated_implementation(generated_impl, comparison_spec)
      |> calculate_performance_delta()
      |> assess_statistical_significance()
      |> compile_comparison_result()

    # Update comparison history and statistics
    comparison_record = %{
      id: comparison_id,
      result: result,
      compared_at: DateTime.utc_now()
    }

    updated_stats = update_comparison_statistics(state.comparison_statistics, result)

    updated_state = %{
      state
      | comparison_history: [comparison_record | Enum.take(state.comparison_history, 99)],
        comparison_statistics: updated_stats
    }

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call({:establish_baseline, implementation, baseline_spec}, _from, state) do
    baseline_key = generate_baseline_key(implementation, baseline_spec)

    baseline_result = execute_baseline_benchmark(implementation, baseline_spec)

    updated_cache = Map.put(state.baseline_cache, baseline_key, baseline_result)
    updated_state = %{state | baseline_cache: updated_cache}

    {:reply, baseline_result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.comparison_statistics, state}
  end

  # Private implementation functions

  defp benchmark_implementation(original_impl, impl_label, comparison_spec) do
    Logger.debug("Benchmarking #{impl_label} implementation")

    # Create benchmark configuration
    benchmark_config = %{
      time: Map.get(comparison_spec, :time, 5),
      warmup: Map.get(comparison_spec, :warmup, 2),
      memory_time: Map.get(comparison_spec, :memory_time, 1)
    }

    # Execute Benchee benchmark
    benchmark_functions = %{impl_label => original_impl}

    case run_benchee_benchmark(benchmark_functions, benchmark_config) do
      {:ok, results} ->
        {:ok, {original_impl, impl_label, results}}

      {:error, reason} ->
        {:error, {:benchmark_failed, impl_label, reason}}
    end
  end

  defp benchmark_generated_implementation(
         {:ok, {original_impl, original_label, original_results}},
         generated_impl,
         comparison_spec
       ) do
    Logger.debug("Benchmarking generated implementation")

    case benchmark_implementation(generated_impl, "generated", comparison_spec) do
      {:ok, {_gen_impl, gen_label, gen_results}} ->
        {:ok,
         {
           {original_impl, original_label, original_results},
           {generated_impl, gen_label, gen_results}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp benchmark_generated_implementation({:error, reason}, _generated_impl, _comparison_spec) do
    {:error, reason}
  end

  defp calculate_performance_delta(
         {:ok, {{_orig_impl, _orig_label, orig_results}, {_gen_impl, _gen_label, gen_results}}}
       ) do
    Logger.debug("Calculating performance delta")

    # Extract key performance metrics
    orig_metrics = extract_key_metrics(orig_results)
    gen_metrics = extract_key_metrics(gen_results)

    performance_delta = %{
      execution_time_ratio: gen_metrics.average_time / orig_metrics.average_time,
      ips_ratio: gen_metrics.ips / orig_metrics.ips,
      memory_ratio: gen_metrics.memory_usage / orig_metrics.memory_usage,
      performance_change: classify_performance_change(orig_metrics, gen_metrics)
    }

    {:ok, {orig_metrics, gen_metrics, performance_delta}}
  end

  defp calculate_performance_delta({:error, reason}) do
    {:error, reason}
  end

  defp assess_statistical_significance({:ok, {orig_metrics, gen_metrics, performance_delta}}) do
    Logger.debug("Assessing statistical significance")

    # Assess significance of performance differences
    significance_assessment = %{
      execution_time_significant: abs(performance_delta.execution_time_ratio - 1.0) > 0.1,
      memory_significant: abs(performance_delta.memory_ratio - 1.0) > 0.1,
      confidence_level: calculate_confidence_level(orig_metrics, gen_metrics),
      # Placeholder for power analysis
      statistical_power: 0.80
    }

    {:ok, {orig_metrics, gen_metrics, performance_delta, significance_assessment}}
  end

  defp assess_statistical_significance({:error, reason}) do
    {:error, reason}
  end

  defp compile_comparison_result(
         {:ok, {orig_metrics, gen_metrics, performance_delta, significance_assessment}}
       ) do
    comparison_result = %{
      original_performance: orig_metrics,
      generated_performance: gen_metrics,
      performance_delta: performance_delta,
      statistical_significance: significance_assessment,
      comparison_summary: generate_comparison_summary(performance_delta, significance_assessment),
      performance_recommendation: generate_performance_recommendation(performance_delta)
    }

    {:ok, comparison_result}
  end

  defp compile_comparison_result({:error, reason}) do
    {:error, reason}
  end

  defp run_benchee_benchmark(benchmark_functions, config) do
    try do
      results = Benchee.run(benchmark_functions, config)
      {:ok, results}
    rescue
      error ->
        {:error, error}
    end
  end

  defp extract_key_metrics(benchee_results) do
    # Extract key metrics from Benchee results structure
    # Placeholder for metrics extraction
    %{
      ips: 1000.0,
      average_time: 1.0,
      memory_usage: 1024,
      std_dev: 0.1
    }
  end

  defp classify_performance_change(orig_metrics, gen_metrics) do
    ratio = gen_metrics.ips / orig_metrics.ips

    cond do
      ratio > 1.2 -> :significant_improvement
      ratio > 1.05 -> :minor_improvement
      ratio > 0.95 -> :no_significant_change
      ratio > 0.8 -> :minor_regression
      true -> :significant_regression
    end
  end

  defp calculate_confidence_level(_orig_metrics, _gen_metrics) do
    # Calculate statistical confidence level
    # Placeholder for confidence calculation
    0.95
  end

  defp generate_comparison_summary(performance_delta, significance_assessment) do
    case {performance_delta.performance_change,
          significance_assessment.execution_time_significant} do
      {:significant_improvement, true} ->
        "Generated implementation shows significant performance improvement"

      {:significant_regression, true} ->
        "Generated implementation shows concerning performance regression"

      {:no_significant_change, false} ->
        "Generated implementation performs similarly to original"

      _ ->
        "Generated implementation shows performance differences requiring analysis"
    end
  end

  defp generate_performance_recommendation(performance_delta) do
    case performance_delta.performance_change do
      :significant_regression ->
        "Consider algorithmic optimization and profiling for performance improvement"

      :minor_regression ->
        "Monitor performance and consider optimization opportunities"

      :no_significant_change ->
        "Performance is acceptable, focus on other quality aspects"

      _ ->
        "Performance is satisfactory or improved"
    end
  end

  defp execute_baseline_benchmark(implementation, baseline_spec) do
    # Execute baseline benchmark for implementation
    # Placeholder for baseline execution
    {:ok,
     %{
       baseline_metrics: %{ips: 1000.0, memory: 1024},
       established_at: DateTime.utc_now()
     }}
  end

  defp generate_baseline_key(implementation, baseline_spec) do
    content = "#{inspect(implementation)}:#{inspect(baseline_spec)}"
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp update_comparison_statistics(current_stats, comparison_result) do
    new_total = current_stats.total_comparisons + 1

    {new_improvements, new_regressions} =
      case comparison_result do
        {:ok, %{performance_delta: %{performance_change: :significant_improvement}}} ->
          {current_stats.performance_improvements + 1, current_stats.performance_regressions}

        {:ok, %{performance_delta: %{performance_change: :significant_regression}}} ->
          {current_stats.performance_improvements, current_stats.performance_regressions + 1}

        _ ->
          {current_stats.performance_improvements, current_stats.performance_regressions}
      end

    # Calculate new average delta (placeholder)
    new_avg_delta = current_stats.avg_performance_delta

    %{
      current_stats
      | total_comparisons: new_total,
        performance_improvements: new_improvements,
        performance_regressions: new_regressions,
        avg_performance_delta: new_avg_delta
    }
  end

  defp generate_comparison_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end
end
