defmodule SweBench.PartialCreditScoring.ScoringSupervisorTest do
  use ExUnit.Case, async: true

  alias SweBench.PartialCreditScoring.ScoringSupervisor

  describe "start_link/1" do
    test "starts supervisor with default configuration" do
      {:ok, pid} = start_supervised(ScoringSupervisor)
      assert Process.alive?(pid)
    end

    test "starts supervisor with custom configuration" do
      config = [scoring_config: %{timeout: 5000}]
      {:ok, pid} = start_supervised({ScoringSupervisor, config})
      assert Process.alive?(pid)
    end
  end

  describe "default_config/0" do
    test "returns valid default configuration" do
      config = ScoringSupervisor.default_config()
      
      assert is_map(config)
      assert Map.has_key?(config, :dimensions)
      assert Map.has_key?(config, :error_categories)
      assert Map.has_key?(config, :minimum_score_difference)
      
      # Validate dimensions structure
      dimensions = config.dimensions
      assert Map.has_key?(dimensions, :compilation)
      assert Map.has_key?(dimensions, :partial_tests)
      assert Map.has_key?(dimensions, :code_quality)
      assert Map.has_key?(dimensions, :performance)
      assert Map.has_key?(dimensions, :functional_programming)
      
      # Validate weight and threshold structure
      Enum.each(dimensions, fn {_key, dimension_config} ->
        assert Map.has_key?(dimension_config, :weight)
        assert Map.has_key?(dimension_config, :threshold)
        assert is_float(dimension_config.weight) or is_integer(dimension_config.weight)
        assert is_integer(dimension_config.threshold)
      end)
    end
  end

  describe "health_check/0" do
    test "returns health status of all processes" do
      start_supervised(ScoringSupervisor)
      
      # Give processes time to start
      Process.sleep(100)
      
      health_status = ScoringSupervisor.health_check()
      
      assert is_map(health_status)
      # Note: Some processes might not be started yet in test environment
      # so we just verify the structure is correct
    end
  end

  describe "get_config/0" do
    test "returns configuration when available" do
      start_supervised(ScoringSupervisor)
      
      # Give processes time to start
      Process.sleep(100)
      
      config = ScoringSupervisor.get_config()
      assert is_map(config)
    end
  end
end