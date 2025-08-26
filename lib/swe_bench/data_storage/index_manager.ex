defmodule SweBench.DataStorage.IndexManager do
  @moduledoc """
  Index management for production database optimization.

  Handles creation, monitoring, and maintenance of database indexes
  for optimal query performance across large benchmark datasets.
  """

  use GenServer
  require Logger
  alias SweBench.Repo

  @production_indexes [
    # Task instances performance indexes
    {:task_instances, [:repository_id, :quality_tier, :packaging_status], %{name: "idx_task_instances_repo_quality_status"}},
    {:task_instances, [:created_at], %{name: "idx_task_instances_created_at"}},
    {:task_instances, [:quality_tier], %{where: "quality_tier IN ('gold', 'silver')", name: "idx_task_instances_high_quality"}},
    {:task_instances, [:packaging_status], %{where: "packaging_status = 'ready'", name: "idx_task_instances_ready"}},
    {:task_instances, [:difficulty_level, :complexity_score], %{name: "idx_task_instances_difficulty_complexity"}},
    
    # Validation results indexes
    {:validation_results, [:repository_id, :benchmark_quality, :confidence_level], %{name: "idx_validation_results_repo_quality_confidence"}},
    {:validation_results, [:created_at], %{where: "benchmark_quality != 'unsuitable'", name: "idx_validation_results_suitable"}},
    {:validation_results, [:issue_pr_link_id], %{name: "idx_validation_results_link"}},
    
    # Repository analysis indexes
    {:repositories, [:language, :stars_count], %{name: "idx_repositories_language_stars"}},
    {:repositories, [:mining_status, :mining_completed_at], %{name: "idx_repositories_mining_status"}},
    {:repositories, [:is_umbrella_project], %{name: "idx_repositories_umbrella"}},
    
    # Issue-PR relationship indexes
    {:issue_pr_links, [:repository_id, :confidence_score], %{name: "idx_issue_pr_links_repo_confidence"}},
    {:issue_pr_links, [:validation_status, :confidence_score], %{name: "idx_issue_pr_links_validation_confidence"}},
    
    # Quality validation indexes
    {:quality_validations, [:task_instance_id, :validation_stage], %{name: "idx_quality_validations_task_stage"}},
    {:quality_validations, [:quality_score], %{where: "validation_status = 'completed'", name: "idx_quality_validations_completed"}}
  ]

  @jsonb_indexes [
    # JSONB GIN indexes for metadata queries
    {:task_instances, [:task_metadata], %{using: :gin, name: "idx_task_instances_metadata_gin"}},
    {:task_instances, [:evaluation_metadata], %{using: :gin, name: "idx_task_instances_eval_metadata_gin"}},
    {:repositories, [:analysis_metadata], %{using: :gin, name: "idx_repositories_analysis_metadata_gin"}},
    {:validation_results, [:validation_metadata], %{using: :gin, name: "idx_validation_results_metadata_gin"}}
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates all production indexes for optimal performance.
  """
  def create_production_indexes do
    GenServer.call(__MODULE__, :create_production_indexes, 300_000)  # 5 minutes timeout
  end

  @doc """
  Analyzes index effectiveness and usage.
  """
  def analyze_index_effectiveness do
    GenServer.call(__MODULE__, :analyze_index_effectiveness)
  end

  @doc """
  Gets index management statistics.
  """
  def get_index_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      indexes_created: 0,
      indexes_failed: 0,
      last_analysis: nil,
      index_statistics: %{}
    }

    Logger.info("Index manager started")
    {:ok, state}
  end

  @impl true
  def handle_call(:create_production_indexes, _from, state) do
    Logger.info("Creating production indexes")

    # Create standard indexes
    standard_results = create_standard_indexes()
    
    # Create JSONB indexes
    jsonb_results = create_jsonb_indexes()

    # Compile results
    all_results = standard_results ++ jsonb_results
    successful_indexes = Enum.filter(all_results, &match?({:ok, _}, &1))
    failed_indexes = Enum.filter(all_results, &match?({:error, _}, &1))

    result = %{
      indexes_created: length(successful_indexes),
      indexes_failed: length(failed_indexes),
      successful_indexes: Enum.map(successful_indexes, fn {:ok, name} -> name end),
      failed_indexes: Enum.map(failed_indexes, fn {:error, {name, reason}} -> {name, reason} end)
    }

    updated_state = %{
      state
      | indexes_created: state.indexes_created + length(successful_indexes),
        indexes_failed: state.indexes_failed + length(failed_indexes)
    }

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:analyze_index_effectiveness, _from, state) do
    analysis = %{
      index_usage_stats: get_index_usage_statistics(),
      unused_indexes: identify_unused_indexes(),
      missing_indexes: suggest_missing_indexes(),
      performance_impact: calculate_index_performance_impact()
    }

    updated_state = %{state | last_analysis: analysis, index_statistics: analysis}

    {:reply, analysis, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp create_standard_indexes do
    @production_indexes
    |> Enum.map(&create_single_index/1)
  end

  defp create_jsonb_indexes do
    @jsonb_indexes
    |> Enum.map(&create_single_jsonb_index/1)
  end

  defp create_single_index({table, columns, opts}) do
    index_name = Map.get(opts, :name, generate_index_name(table, columns))
    where_clause = Map.get(opts, :where)

    try do
      sql = build_index_sql(index_name, table, columns, where_clause, false)
      
      case Repo.query(sql) do
        {:ok, _result} ->
          Logger.info("Created index #{index_name}")
          {:ok, index_name}

        {:error, %Postgrex.Error{postgres: %{code: :duplicate_table}}} ->
          Logger.debug("Index #{index_name} already exists")
          {:ok, index_name}

        {:error, reason} ->
          Logger.error("Failed to create index #{index_name}: #{inspect(reason)}")
          {:error, {index_name, reason}}
      end
    rescue
      error ->
        Logger.error("Exception creating index #{index_name}: #{inspect(error)}")
        {:error, {index_name, error}}
    end
  end

  defp create_single_jsonb_index({table, columns, opts}) do
    index_name = Map.get(opts, :name, generate_jsonb_index_name(table, columns))

    try do
      sql = build_jsonb_index_sql(index_name, table, columns)
      
      case Repo.query(sql) do
        {:ok, _result} ->
          Logger.info("Created JSONB index #{index_name}")
          {:ok, index_name}

        {:error, %Postgrex.Error{postgres: %{code: :duplicate_table}}} ->
          Logger.debug("JSONB index #{index_name} already exists")
          {:ok, index_name}

        {:error, reason} ->
          Logger.error("Failed to create JSONB index #{index_name}: #{inspect(reason)}")
          {:error, {index_name, reason}}
      end
    rescue
      error ->
        Logger.error("Exception creating JSONB index #{index_name}: #{inspect(error)}")
        {:error, {index_name, error}}
    end
  end

  defp build_index_sql(index_name, table, columns, where_clause, concurrent \\ true) do
    concurrent_keyword = if concurrent, do: "CONCURRENTLY ", else: ""
    column_list = Enum.join(columns, ", ")
    where_part = if where_clause, do: " WHERE #{where_clause}", else: ""

    "CREATE INDEX #{concurrent_keyword}#{index_name} ON #{table} (#{column_list})#{where_part}"
  end

  defp build_jsonb_index_sql(index_name, table, columns) do
    column_list = Enum.join(columns, ", ")
    "CREATE INDEX CONCURRENTLY #{index_name} ON #{table} USING GIN (#{column_list})"
  end

  defp generate_index_name(table, columns) do
    column_suffix = columns |> Enum.join("_") |> String.slice(0, 20)
    "idx_#{table}_#{column_suffix}"
  end

  defp generate_jsonb_index_name(table, columns) do
    column_suffix = columns |> Enum.join("_") |> String.slice(0, 20)
    "idx_#{table}_#{column_suffix}_gin"
  end

  # Placeholder monitoring functions
  defp get_index_usage_statistics do
    []
  end

  defp identify_unused_indexes do
    []
  end

  defp suggest_missing_indexes do
    []
  end

  defp calculate_index_performance_impact do
    %{performance_improvement: 0.0, query_speedup: 1.0}
  end
end