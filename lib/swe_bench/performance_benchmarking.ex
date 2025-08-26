defmodule SweBench.PerformanceBenchmarking do
  @moduledoc """
  Main interface for performance evaluation using Benchee integration.

  Provides comprehensive performance assessment including execution speed,
  memory usage, and scalability characteristics for AI-generated solutions.
  """

  alias SweBench.PerformanceBenchmarking.{BencheeExecutor, PerformanceComparator, ScalabilityTester}

  @doc """
  Evaluates performance for a task instance with comprehensive benchmarking.

  ## Parameters
    - task_instance_id: UUID of task instance to benchmark
    - benchmark_spec: Configuration for performance evaluation

  ## Examples
      iex> SweBench.PerformanceBenchmarking.evaluate_performance(task_id, %{type: :comprehensive})
      {:ok, %{performance_score: 0.85, memory_efficiency: 0.90}}
  """
  def evaluate_performance(task_instance_id, benchmark_spec, opts \\ []) do
    BencheeExecutor.execute_performance_evaluation(task_instance_id, benchmark_spec, opts)
  end

  @doc """
  Compares performance between original and generated implementations.
  """
  def compare_implementations(original_impl, generated_impl, comparison_spec) do
    PerformanceComparator.compare_implementations(original_impl, generated_impl, comparison_spec)
  end

  @doc """
  Tests scalability characteristics for an implementation.
  """
  def test_scalability(implementation, scalability_spec) do
    ScalabilityTester.test_scalability(implementation, scalability_spec)
  end

  @doc """
  Gets performance benchmarking statistics and metrics.
  """
  def get_benchmark_statistics do
    BencheeExecutor.get_benchmark_statistics()
  end

  @doc """
  Lists available benchmark scenarios and configurations.
  """
  def list_benchmark_scenarios do
    %{
      execution_speed: %{
        description: "Execution time and iterations per second measurement",
        duration_estimate: "10-30 seconds",
        resource_requirements: %{memory: "1GB", cpu: "1 core"}
      },
      memory_profiling: %{
        description: "Memory usage and garbage collection analysis",
        duration_estimate: "5-15 seconds",
        resource_requirements: %{memory: "2GB", cpu: "1 core"}
      },
      scalability_testing: %{
        description: "Algorithmic complexity and scaling characteristics",
        duration_estimate: "30-120 seconds",
        resource_requirements: %{memory: "4GB", cpu: "2 cores"}
      },
      concurrent_performance: %{
        description: "Multi-process and concurrent execution performance",
        duration_estimate: "60-180 seconds",
        resource_requirements: %{memory: "4GB", cpu: "4 cores"}
      }
    }
  end

  @doc """
  Estimates benchmark duration and resource requirements.
  """
  def estimate_benchmark_requirements(benchmark_spec) do
    %{
      estimated_duration_seconds: calculate_duration_estimate(benchmark_spec),
      memory_requirements_gb: calculate_memory_requirements(benchmark_spec),
      cpu_requirements: calculate_cpu_requirements(benchmark_spec),
      isolation_requirements: determine_isolation_requirements(benchmark_spec)
    }
  end

  # Private helper functions

  defp calculate_duration_estimate(benchmark_spec) do
    base_time = Map.get(benchmark_spec, :base_duration, 15)
    
    multipliers = [
      (if Map.get(benchmark_spec, :memory_profiling, false), do: 1.5, else: 1.0),
      (if Map.get(benchmark_spec, :scalability_testing, false), do: 3.0, else: 1.0),
      (if Map.get(benchmark_spec, :concurrent_testing, false), do: 2.0, else: 1.0)
    ]

    round(base_time * Enum.reduce(multipliers, 1.0, &*/2))
  end

  defp calculate_memory_requirements(benchmark_spec) do
    base_memory = 1.0  # 1GB base

    if Map.get(benchmark_spec, :memory_profiling, false) do
      base_memory * 2
    else
      base_memory
    end
  end

  defp calculate_cpu_requirements(benchmark_spec) do
    if Map.get(benchmark_spec, :concurrent_testing, false) do
      %{cores: 4, priority: :high}
    else
      %{cores: 2, priority: :medium}
    end
  end

  defp determine_isolation_requirements(benchmark_spec) do
    %{
      container_isolation: true,
      resource_limits: true,
      network_isolation: Map.get(benchmark_spec, :distributed_testing, false)
    }
  end
end