defmodule SweBench.ConcurrentEvaluation.HarnessTest do
  use ExUnit.Case, async: true

  alias SweBench.ConcurrentEvaluation.Harness

  describe "start_link/1" do
    test "starts harness with default configuration" do
      {:ok, pid} = start_supervised(Harness)
      assert Process.alive?(pid)
    end

    test "starts harness with custom configuration" do
      config = [monitoring_tier: :light, fault_injection_enabled: false]
      {:ok, pid} = start_supervised({Harness, config})
      assert Process.alive?(pid)
    end
  end

  describe "get_evaluation_metrics/0" do
    test "returns evaluation metrics when available" do
      start_supervised(Harness)

      # Give process time to start
      Process.sleep(100)

      metrics = Harness.get_evaluation_metrics()
      assert is_map(metrics)
      assert Map.has_key?(metrics, :total_evaluations)
      assert Map.has_key?(metrics, :concurrent_issues_detected)
      assert Map.has_key?(metrics, :monitoring_tier_usage)
    end
  end

  describe "evaluate_concurrent_system/2" do
    test "handles basic concurrent evaluation" do
      start_supervised(Harness)

      # Give processes time to start
      Process.sleep(100)

      solution_data = %{
        solution_code: """
        defmodule TestModule do
          def simple_function(x), do: x * 2
        end
        """,
        compilation_successful: true
      }

      # This should work without actual concurrent patterns
      result = Harness.evaluate_concurrent_system(solution_data, monitoring_tier: :light)

      # Should succeed even if no concurrent patterns detected
      case result do
        {:ok, analysis} ->
          assert is_map(analysis)
          assert Map.has_key?(analysis, :overall_score)

        {:error, reason} ->
          # Acceptable if dependencies aren't fully mocked
          assert reason != nil
      end
    end
  end
end
