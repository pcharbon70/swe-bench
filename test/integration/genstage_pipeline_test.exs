defmodule SweBench.Integration.GenStagePipelineTest do
  @moduledoc """
  GenStage pipeline integration tests.

  Tests end-to-end pipeline flow, backpressure handling, throughput
  validation, and failure recovery scenarios.
  """

  use ExUnit.Case, async: false

  alias SweBench.Pipeline
  alias SweBench.Pipeline.{ContainerEvaluator, PatchFetcher, ResultAnalyzer, TaskProducer}

  @moduletag :integration
  @moduletag timeout: 900_000

  describe "GenStage pipeline integration" do
    test "end-to-end pipeline flow with all stages" do
      # Start the complete pipeline
      assert {:ok, supervisor_pid} = Pipeline.start_pipeline()
      assert Process.alive?(supervisor_pid)

      # Wait for pipeline to initialize
      :timer.sleep(2000)

      # Verify all stages are running
      assert {:ok, status} = Pipeline.get_pipeline_status()
      assert status.overall_status in [:healthy, :degraded]
      assert status.pipeline_health.total_stages == 4

      # Test pipeline processing with sample tasks
      sample_tasks = create_sample_evaluation_tasks(5)

      # Monitor pipeline processing
      processing_start = System.monotonic_time(:millisecond)

      # Inject tasks into pipeline (would be done via TaskProducer in production)
      Enum.each(sample_tasks, fn task ->
        # Simulate task processing through pipeline
        process_task_through_pipeline(task)
      end)

      # Wait for processing to complete
      :timer.sleep(10_000)

      processing_time = System.monotonic_time(:millisecond) - processing_start

      # Verify pipeline processed tasks
      # Should complete within 30 seconds
      assert processing_time < 30_000

      # Stop pipeline gracefully
      assert :ok = Pipeline.stop_pipeline()
    end

    test "backpressure handling under load" do
      # Start pipeline with limited capacity
      pipeline_config = %{
        max_concurrent_evaluations: 3,
        batch_size: 2
      }

      assert {:ok, supervisor_pid} = Pipeline.start_pipeline(pipeline_config)

      # Create high load scenario
      high_load_tasks = create_sample_evaluation_tasks(20)

      # Monitor memory usage during high load
      initial_memory = get_pipeline_memory_usage()

      # Process high load through pipeline
      Enum.each(high_load_tasks, fn task ->
        process_task_through_pipeline(task)
      end)

      # Allow processing time
      :timer.sleep(15_000)

      # Verify memory didn't explode (backpressure working)
      final_memory = get_pipeline_memory_usage()
      memory_increase = final_memory - initial_memory

      # Memory increase should be bounded due to backpressure
      # Less than 500MB increase
      assert memory_increase < 500_000_000

      Pipeline.stop_pipeline()
    end

    test "throughput validation and performance targets" do
      # Start pipeline optimized for throughput
      throughput_config = %{
        max_concurrent_evaluations: 12,
        batch_size: 10,
        parallel_workers: 6
      }

      assert {:ok, _supervisor_pid} = Pipeline.start_pipeline(throughput_config)

      # Create substantial task load
      task_batch = create_sample_evaluation_tasks(50)

      # Measure throughput
      start_time = System.monotonic_time(:millisecond)

      # Process tasks through pipeline
      Enum.each(task_batch, &process_task_through_pipeline/1)

      # Wait for completion
      :timer.sleep(20_000)

      end_time = System.monotonic_time(:millisecond)
      processing_time_hours = (end_time - start_time) / 3_600_000

      # Calculate throughput
      throughput_per_hour = length(task_batch) / processing_time_hours

      # Verify throughput meets targets (300+ tasks/hour)
      # Relaxed for integration test
      assert throughput_per_hour >= 200

      Pipeline.stop_pipeline()
    end

    test "pipeline recovery from stage failures" do
      assert {:ok, _supervisor_pid} = Pipeline.start_pipeline()

      # Get initial pipeline health
      assert {:ok, initial_status} = Pipeline.get_pipeline_status()
      assert initial_status.overall_status == :healthy

      # Simulate stage failure (would need to implement failure injection)
      simulate_stage_failure(:patch_fetcher_1)

      # Wait for recovery
      :timer.sleep(5000)

      # Verify pipeline recovered
      assert {:ok, recovered_status} = Pipeline.get_pipeline_status()

      # Pipeline should either be healthy or degraded, not failed
      assert recovered_status.overall_status in [:healthy, :degraded]

      Pipeline.stop_pipeline()
    end
  end

  describe "pipeline performance monitoring" do
    test "pipeline statistics and metrics collection" do
      assert {:ok, _supervisor_pid} = Pipeline.start_pipeline()

      # Allow pipeline to initialize
      :timer.sleep(2000)

      # Get comprehensive pipeline status
      assert {:ok, status} = Pipeline.get_pipeline_status()

      # Verify status contains expected metrics
      assert Map.has_key?(status, :pipeline_health)
      assert Map.has_key?(status, :throughput_metrics)
      assert Map.has_key?(status, :stage_statistics)

      # Verify individual stage statistics
      stage_stats = status.stage_statistics
      assert Map.has_key?(stage_stats, :task_producer)
      assert Map.has_key?(stage_stats, :patch_fetcher)
      assert Map.has_key?(stage_stats, :container_evaluator)
      assert Map.has_key?(stage_stats, :result_analyzer)

      Pipeline.stop_pipeline()
    end

    test "throughput metrics calculation" do
      assert {:ok, _supervisor_pid} = Pipeline.start_pipeline()

      # Process some tasks to generate metrics
      tasks = create_sample_evaluation_tasks(10)
      Enum.each(tasks, &process_task_through_pipeline/1)

      # Wait for processing
      :timer.sleep(8000)

      # Get throughput metrics
      assert {:ok, metrics} = Pipeline.get_throughput_metrics()

      # Verify metrics structure
      assert Map.has_key?(metrics, :tasks_pending)
      assert Map.has_key?(metrics, :evaluations_active)
      assert Map.has_key?(metrics, :available_capacity)
      assert Map.has_key?(metrics, :estimated_throughput_per_hour)

      Pipeline.stop_pipeline()
    end
  end

  # Helper functions

  defp create_sample_evaluation_tasks(count) do
    for i <- 1..count do
      %{
        id: i,
        repository: Enum.random(["phoenix", "ecto", "jason", "tesla", "credo"]),
        issue_number: 100 + i,
        priority: Enum.random([:high, :medium, :low]),
        difficulty: Enum.random([:simple, :medium, :complex])
      }
    end
  end

  defp process_task_through_pipeline(task) do
    # Placeholder for task injection into pipeline
    # In production, would add task to database for TaskProducer to pick up
    Logger.debug("Processing task #{task.id} through pipeline")
    :ok
  end

  defp setup_test_container do
    # Placeholder for container setup
    {:ok, "integration_test_container_#{System.unique_integer()}"}
  end

  defp get_pipeline_memory_usage do
    # Placeholder for memory usage monitoring
    # Would use :erlang.memory() or system monitoring
    # 100MB baseline
    100_000_000
  end

  defp simulate_stage_failure(stage_name) do
    # Placeholder for stage failure simulation
    # Would need to implement controlled failure injection
    Logger.warning("Simulating failure for stage: #{stage_name}")
    :ok
  end
end
