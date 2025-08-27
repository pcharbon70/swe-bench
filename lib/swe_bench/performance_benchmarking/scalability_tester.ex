defmodule SweBench.PerformanceBenchmarking.ScalabilityTester do
  @moduledoc """
  Tests scalability characteristics and algorithmic complexity.

  Analyzes performance scaling with varying input sizes, concurrent loads,
  and resource utilization to assess algorithmic efficiency and optimization.
  """

  use GenServer
  require Logger

  @scale_factors [1, 10, 100, 1000, 10_000]
  @concurrency_levels [1, 5, 10, 25, 50]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tests scalability characteristics for an implementation.
  """
  def test_scalability(implementation, scalability_spec) do
    GenServer.call(__MODULE__, {:test_scalability, implementation, scalability_spec}, 600_000)
  end

  @doc """
  Tests algorithmic complexity with varying input sizes.
  """
  def test_algorithmic_complexity(implementation, input_generator, opts \\ []) do
    GenServer.call(__MODULE__, {:test_complexity, implementation, input_generator, opts})
  end

  @doc """
  Gets scalability testing statistics.
  """
  def get_scalability_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      scalability_tests: [],
      complexity_analyses: %{},
      test_statistics: %{
        tests_performed: 0,
        complexity_classifications: %{},
        avg_scaling_efficiency: 0.0
      }
    }

    Logger.info("Scalability tester started")
    {:ok, state}
  end

  @impl true
  def handle_call({:test_scalability, implementation, scalability_spec}, _from, state) do
    test_id = generate_test_id()
    Logger.info("Starting scalability test #{test_id}")

    result =
      implementation
      |> test_input_scaling(scalability_spec)
      |> test_concurrent_performance(scalability_spec)
      |> analyze_algorithmic_complexity()
      |> detect_performance_bottlenecks()
      |> compile_scalability_assessment()

    test_record = %{
      id: test_id,
      result: result,
      tested_at: DateTime.utc_now()
    }

    updated_state = %{
      state
      | scalability_tests: [test_record | state.scalability_tests]
    }

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call({:test_complexity, implementation, input_generator, opts}, _from, state) do
    timeout = Keyword.get(opts, :timeout, 180_000)  # 3 minutes default

    complexity_result =
      @scale_factors
      |> Enum.map(fn scale ->
        test_input = input_generator.(scale)
        {scale, benchmark_with_input_size(implementation, test_input, timeout)}
      end)
      |> Enum.filter(fn {_scale, result} -> result != :timeout end)
      |> analyze_complexity_curve()

    {:reply, complexity_result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.test_statistics, state}
  end

  # Private implementation functions

  defp test_input_scaling(implementation, scalability_spec) do
    Logger.debug("Testing input scaling performance")

    input_sizes = Map.get(scalability_spec, :input_sizes, @scale_factors)
    
    scaling_results =
      input_sizes
      |> Enum.map(fn size ->
        test_input = generate_scaled_input(size, scalability_spec)
        
        case benchmark_implementation_with_input(implementation, test_input) do
          {:ok, benchmark_result} ->
            {size, benchmark_result}

          {:error, reason} ->
            Logger.warning("Scaling test failed for input size #{size}: #{inspect(reason)}")
            {size, :failed}
        end
      end)
      |> Enum.filter(fn {_size, result} -> result != :failed end)

    {:ok, {implementation, scaling_results}}
  end

  defp test_concurrent_performance({:ok, {implementation, scaling_results}}, scalability_spec) do
    Logger.debug("Testing concurrent performance")

    concurrency_levels = Map.get(scalability_spec, :concurrency_levels, @concurrency_levels)

    concurrent_results =
      concurrency_levels
      |> Enum.map(fn concurrency ->
        case test_concurrent_execution(implementation, concurrency, scalability_spec) do
          {:ok, concurrent_result} ->
            {concurrency, concurrent_result}

          {:error, reason} ->
            Logger.warning("Concurrent test failed for #{concurrency} processes: #{inspect(reason)}")
            {concurrency, :failed}
        end
      end)
      |> Enum.filter(fn {_concurrency, result} -> result != :failed end)

    {:ok, {implementation, scaling_results, concurrent_results}}
  end

  defp test_concurrent_performance({:error, reason}, _scalability_spec) do
    {:error, reason}
  end

  defp analyze_algorithmic_complexity({:ok, {implementation, scaling_results, concurrent_results}}) do
    Logger.debug("Analyzing algorithmic complexity")

    complexity_analysis = %{
      complexity_classification: classify_algorithmic_complexity(scaling_results),
      scaling_efficiency: calculate_scaling_efficiency(scaling_results),
      concurrent_efficiency: calculate_concurrent_efficiency(concurrent_results),
      performance_characteristics: analyze_performance_characteristics(scaling_results)
    }

    {:ok, {implementation, scaling_results, concurrent_results, complexity_analysis}}
  end

  defp analyze_algorithmic_complexity({:error, reason}) do
    {:error, reason}
  end

  defp detect_performance_bottlenecks({:ok, {implementation, scaling_results, concurrent_results, complexity_analysis}}) do
    Logger.debug("Detecting performance bottlenecks")

    bottleneck_analysis = %{
      memory_bottlenecks: detect_memory_bottlenecks(scaling_results),
      cpu_bottlenecks: detect_cpu_bottlenecks(concurrent_results),
      algorithmic_bottlenecks: detect_algorithmic_bottlenecks(complexity_analysis),
      optimization_opportunities: identify_optimization_opportunities(complexity_analysis)
    }

    {:ok, {implementation, scaling_results, concurrent_results, complexity_analysis, bottleneck_analysis}}
  end

  defp detect_performance_bottlenecks({:error, reason}) do
    {:error, reason}
  end

  defp compile_scalability_assessment({:ok, {implementation, scaling_results, concurrent_results, complexity_analysis, bottleneck_analysis}}) do
    scalability_assessment = %{
      overall_scalability_score: calculate_overall_scalability_score(complexity_analysis, bottleneck_analysis),
      algorithmic_complexity: complexity_analysis.complexity_classification,
      scaling_efficiency: complexity_analysis.scaling_efficiency,
      concurrent_performance: concurrent_results,
      bottleneck_analysis: bottleneck_analysis,
      optimization_recommendations: generate_optimization_recommendations(bottleneck_analysis)
    }

    {:ok, scalability_assessment}
  end

  defp compile_scalability_assessment({:error, reason}) do
    {:error, reason}
  end

  defp generate_scaled_input(size, scalability_spec) do
    # Generate scaled test input based on size
    base_input = Map.get(scalability_spec, :base_input, [1, 2, 3])
    
    case Map.get(scalability_spec, :input_type, :list) do
      :list -> Enum.take(Stream.cycle(base_input), size)
      :number -> size
      :string -> String.duplicate("test", size)
      _ -> base_input
    end
  end

  defp benchmark_implementation_with_input(implementation, test_input) do
    # Benchmark implementation with specific input
    benchmark_config = %{
      time: 2,
      warmup: 1,
      memory_time: 1
    }

    benchmark_functions = %{
      "test" => fn -> implementation.(test_input) end
    }

    case SweBench.PerformanceBenchmarking.BencheeExecutor.run_benchee_benchmark(benchmark_functions, benchmark_config) do
      {:ok, results} ->
        {:ok, extract_benchmark_summary(results)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_concurrent_execution(implementation, concurrency, scalability_spec) do
    # Test implementation under concurrent load
    test_input = Map.get(scalability_spec, :concurrent_input, [1, 2, 3])

    tasks = 
      1..concurrency
      |> Enum.map(fn _i ->
        Task.async(fn ->
          :timer.tc(fn -> implementation.(test_input) end)
        end)
      end)

    case Task.await_many(tasks, 30_000) do
      results when is_list(results) ->
        concurrent_metrics = %{
          concurrency_level: concurrency,
          execution_times: Enum.map(results, &elem(&1, 0)),
          avg_execution_time: Enum.sum(Enum.map(results, &elem(&1, 0))) / length(results),
          throughput: concurrency * 1_000_000 / (Enum.sum(Enum.map(results, &elem(&1, 0))) / length(results))
        }

        {:ok, concurrent_metrics}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, {:concurrent_test_failed, error}}
  end

  defp benchmark_with_input_size(implementation, test_input, timeout) do
    # Benchmark with timeout protection
    task = Task.async(fn ->
      :timer.tc(fn -> implementation.(test_input) end)
    end)

    case Task.await(task, timeout) do
      {execution_time, _result} ->
        %{execution_time: execution_time, input_size: estimate_input_size(test_input)}

      {:timeout, _} ->
        :timeout
    end
  rescue
    _ ->
      :timeout
  end

  defp analyze_complexity_curve(scaling_data) when length(scaling_data) >= 3 do
    # Analyze performance scaling curve to determine algorithmic complexity
    time_ratios = calculate_performance_ratios(scaling_data)

    complexity = cond do
      linear_pattern?(time_ratios) -> :linear
      quadratic_pattern?(time_ratios) -> :quadratic
      logarithmic_pattern?(time_ratios) -> :logarithmic
      constant_pattern?(time_ratios) -> :constant
      exponential_pattern?(time_ratios) -> :exponential
      true -> :unknown
    end

    %{
      complexity_classification: complexity,
      scaling_data: scaling_data,
      confidence: calculate_complexity_confidence(time_ratios)
    }
  end

  defp analyze_complexity_curve(_scaling_data) do
    %{
      complexity_classification: :insufficient_data,
      scaling_data: [],
      confidence: 0.0
    }
  end

  # Helper functions for complexity analysis

  defp calculate_performance_ratios(scaling_data) do
    scaling_data
    |> Enum.sort_by(fn {size, _metrics} -> size end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{size1, metrics1}, {size2, metrics2}] ->
      size_ratio = size2 / size1
      time_ratio = metrics2.execution_time / metrics1.execution_time
      {size_ratio, time_ratio}
    end)
  end

  defp linear_pattern?(time_ratios) do
    # Check if time scales linearly with input size
    Enum.all?(time_ratios, fn {size_ratio, time_ratio} ->
      abs(time_ratio / size_ratio - 1.0) < 0.3
    end)
  end

  defp quadratic_pattern?(time_ratios) do
    # Check if time scales quadratically with input size
    Enum.all?(time_ratios, fn {size_ratio, time_ratio} ->
      expected_ratio = size_ratio * size_ratio
      abs(time_ratio / expected_ratio - 1.0) < 0.4
    end)
  end

  defp logarithmic_pattern?(time_ratios) do
    # Check if time scales logarithmically with input size
    Enum.all?(time_ratios, fn {size_ratio, time_ratio} ->
      expected_ratio = :math.log(size_ratio)
      abs(time_ratio / expected_ratio - 1.0) < 0.5
    end)
  end

  defp constant_pattern?(time_ratios) do
    # Check if time is constant regardless of input size
    Enum.all?(time_ratios, fn {_size_ratio, time_ratio} ->
      abs(time_ratio - 1.0) < 0.2
    end)
  end

  defp exponential_pattern?(time_ratios) do
    # Check if time grows exponentially with input size
    Enum.all?(time_ratios, fn {size_ratio, time_ratio} ->
      time_ratio > size_ratio * 2
    end)
  end

  defp calculate_complexity_confidence(time_ratios) do
    if length(time_ratios) >= 3 do
      0.8
    else
      0.4
    end
  end

  # Placeholder implementations for additional analysis functions

  defp classify_algorithmic_complexity(scaling_results) do
    # Placeholder complexity classification
    if length(scaling_results) >= 3 do
      :linear
    else
      :insufficient_data
    end
  end

  defp calculate_scaling_efficiency(scaling_results) do
    # Placeholder efficiency calculation
    if length(scaling_results) > 1 do
      0.85
    else
      0.0
    end
  end

  defp calculate_concurrent_efficiency(concurrent_results) do
    # Placeholder concurrent efficiency
    if length(concurrent_results) > 1 do
      0.80
    else
      0.0
    end
  end

  defp analyze_performance_characteristics(_scaling_results) do
    # Placeholder performance characteristics
    %{
      memory_scaling: :linear,
      cpu_scaling: :linear,
      throughput_scaling: :good
    }
  end

  defp detect_memory_bottlenecks(_scaling_results) do
    # Placeholder memory bottleneck detection
    []
  end

  defp detect_cpu_bottlenecks(_concurrent_results) do
    # Placeholder CPU bottleneck detection
    []
  end

  defp detect_algorithmic_bottlenecks(_complexity_analysis) do
    # Placeholder algorithmic bottleneck detection
    []
  end

  defp identify_optimization_opportunities(_complexity_analysis) do
    # Placeholder optimization opportunities
    []
  end

  defp calculate_overall_scalability_score(_complexity_analysis, _bottleneck_analysis) do
    # Placeholder overall score calculation
    0.75
  end

  defp generate_optimization_recommendations(_bottleneck_analysis) do
    # Placeholder optimization recommendations
    []
  end

  defp extract_benchmark_summary(_benchee_results) do
    # Placeholder benchmark summary extraction
    %{execution_time: 1000, memory_usage: 1024}
  end

  defp estimate_input_size(input) when is_list(input), do: length(input)
  defp estimate_input_size(input) when is_binary(input), do: String.length(input)
  defp estimate_input_size(input) when is_number(input), do: input
  defp estimate_input_size(_input), do: 1

  defp generate_test_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end
end