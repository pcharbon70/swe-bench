defmodule SweBench.DataStorage do
  @moduledoc """
  Main interface for data storage optimization and management.

  Provides database optimization, performance monitoring, and production-ready
  data management capabilities for the SWE-bench-Elixir system.
  """

  alias SweBench.DataStorage.{IndexManager, OptimizationManager, PartitionManager}

  @doc """
  Optimizes database for production performance.

  ## Parameters
    - opts: Configuration options for optimization

  ## Examples
      iex> SweBench.DataStorage.optimize_for_production()
      {:ok, %{indexes_created: 12, partitions_configured: 3}}
  """
  def optimize_for_production(opts \\ []) do
    OptimizationManager.optimize_for_production(opts)
  end

  @doc """
  Gets database performance metrics and health status.
  """
  def get_performance_metrics do
    OptimizationManager.get_performance_metrics()
  end

  @doc """
  Creates production indexes for efficient querying.
  """
  def create_production_indexes do
    IndexManager.create_production_indexes()
  end

  @doc """
  Configures table partitioning for large datasets.
  """
  def configure_partitioning do
    PartitionManager.configure_partitioning()
  end

  @doc """
  Analyzes query performance and suggests optimizations.
  """
  def analyze_query_performance(opts \\ []) do
    OptimizationManager.analyze_query_performance(opts)
  end

  @doc """
  Validates database schema integrity and optimization.
  """
  def validate_schema_optimization do
    OptimizationManager.validate_schema_optimization()
  end
end
