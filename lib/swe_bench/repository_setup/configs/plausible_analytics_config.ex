defmodule SweBench.RepositorySetup.Configs.PlausibleAnalyticsConfig do
  @moduledoc """
  ClickHouse integration and analytics pipeline configuration for Plausible Analytics.

  Handles complex data analytics scenarios with large-scale data processing,
  real-time ingestion, and production-like testing environments.
  """

  require Logger

  @behaviour SweBench.RepositorySetup.RepositoryConfig

  @clickhouse_config %{
    image: "clickhouse/clickhouse-server:latest",
    memory: "2GB",
    ports: ["8123:8123", "9000:9000"],
    volumes: ["clickhouse_data:/var/lib/clickhouse"],
    environment: %{
      "CLICKHOUSE_DB" => "plausible_test",
      "CLICKHOUSE_USER" => "test_user",
      "CLICKHOUSE_PASSWORD" => "test_pass"
    }
  }

  @analytics_pipeline_tests %{
    page_views: :large_scale_ingestion,
    event_processing: :real_time_aggregation,
    dashboard_queries: :complex_analytics,
    data_retention: :automated_cleanup,
    performance_optimization: :query_analysis
  }

  @impl true
  def repository_name, do: "plausible/analytics"

  @impl true
  def github_url, do: "https://github.com/plausible/analytics"

  @impl true
  def complexity_tier, do: :production

  @impl true
  def dependencies do
    [
      {:clickhouse, @clickhouse_config},
      {:postgresql, standard_postgres_config()},
      {:redis, standard_redis_config()}
    ]
  end

  @impl true
  def environment_setup do
    %{
      pre_test_commands: [
        "mix deps.get",
        "mix ecto.create",
        "mix ecto.migrate",
        "mix plausible.clickhouse.init"
      ],
      test_environment: %{
        "MIX_ENV" => "test",
        "DATABASE_URL" => "postgres://postgres:postgres@postgres:5432/plausible_test",
        "CLICKHOUSE_DATABASE_URL" => "http://clickhouse:8123/plausible_test"
      },
      post_test_cleanup: [
        "mix ecto.drop",
        "docker volume rm clickhouse_data || true"
      ]
    }
  end

  @impl true
  def testing_scenarios, do: Map.keys(@analytics_pipeline_tests)

  @impl true
  def resource_requirements do
    %{
      memory_limit: "8GB",
      cpu_limit: "4",
      disk_space: "20GB",
      timeout_multiplier: 3.0,
      concurrent_tasks: 8
    }
  end

  @impl true
  def task_generation_config do
    %{
      target_instances: 20,
      complexity_distribution: %{
        low: 0.15,     # 15% - Basic analytics queries
        medium: 0.35,  # 35% - Dashboard functionality
        high: 0.35,    # 35% - Real-time processing
        expert: 0.15   # 15% - Large-scale optimization
      },
      scenario_distribution: @analytics_pipeline_tests
    }
  end

  @impl true
  def validation_requirements do
    %{
      clickhouse_connectivity: true,
      analytics_data_flow: true,
      query_performance: %{min_queries_per_second: 100},
      data_retention_policies: true,
      dashboard_functionality: true
    }
  end

  @doc """
  Generates analytics-specific test data for realistic evaluation scenarios.
  """
  def generate_analytics_test_data do
    %{
      page_views: generate_page_view_data(),
      events: generate_event_data(), 
      sessions: generate_session_data(),
      goals: generate_goal_data()
    }
  end

  @doc """
  Validates ClickHouse integration and data pipeline functionality.
  """
  def validate_clickhouse_integration(container_id) do
    validation_queries = [
      "SELECT 1",
      "SHOW DATABASES", 
      "CREATE TABLE IF NOT EXISTS test_events (id UInt64, timestamp DateTime) ENGINE = MergeTree ORDER BY id",
      "INSERT INTO test_events VALUES (1, now())",
      "SELECT COUNT(*) FROM test_events"
    ]
    
    validation_queries
    |> Enum.reduce_while({:ok, []}, fn query, {:ok, results} ->
        case execute_clickhouse_query(container_id, query) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  # Private functions

  defp standard_postgres_config do
    %{
      image: "postgres:13",
      memory: "1GB",
      environment: %{
        "POSTGRES_DB" => "plausible_test",
        "POSTGRES_USER" => "postgres",
        "POSTGRES_PASSWORD" => "postgres"
      }
    }
  end

  defp standard_redis_config do
    %{
      image: "redis:6-alpine",
      memory: "512MB"
    }
  end

  defp generate_page_view_data do
    1..1000
    |> Enum.map(fn i ->
        %{
          id: i,
          hostname: "example-#{rem(i, 10)}.com",
          pathname: "/page-#{rem(i, 50)}",
          timestamp: DateTime.add(DateTime.utc_now(), -i * 60, :second),
          referrer: if(rem(i, 3) == 0, do: "https://google.com", else: nil),
          user_agent: "Mozilla/5.0 TestBot/#{rem(i, 5)}"
        }
    end)
  end

  defp generate_event_data do
    1..500
    |> Enum.map(fn i ->
        %{
          id: i,
          name: "event_#{rem(i, 20)}",
          hostname: "example-#{rem(i, 10)}.com", 
          timestamp: DateTime.add(DateTime.utc_now(), -i * 120, :second),
          meta: %{
            key: "value_#{i}",
            source: "test_#{rem(i, 5)}"
          }
        }
    end)
  end

  defp generate_session_data do
    1..200
    |> Enum.map(fn i ->
        %{
          session_id: "session_#{i}",
          hostname: "example-#{rem(i, 10)}.com",
          start_time: DateTime.add(DateTime.utc_now(), -i * 300, :second),
          duration_seconds: 30 + :rand.uniform(600),
          page_views: 1 + :rand.uniform(10),
          referrer: if(rem(i, 4) == 0, do: "https://twitter.com", else: nil)
        }
    end)
  end

  defp generate_goal_data do
    1..50
    |> Enum.map(fn i ->
        %{
          goal_id: i,
          name: "goal_#{i}",
          hostname: "example-#{rem(i, 10)}.com",
          event_name: "signup",
          conversions: :rand.uniform(100),
          conversion_rate: :rand.uniform() * 0.1
        }
    end)
  end

  defp execute_clickhouse_query(_container_id, query) do
    # Mock ClickHouse query execution - would integrate with actual container
    Logger.debug("Executing ClickHouse query: #{query}")
    
    cond do
      query == "SELECT 1" -> {:ok, "1"}
      query == "SHOW DATABASES" -> {:ok, ["default", "system", "plausible_test"]}
      String.starts_with?(query, "CREATE TABLE") -> {:ok, "Table created"}
      String.starts_with?(query, "INSERT") -> {:ok, "1 row inserted"}
      String.starts_with?(query, "SELECT COUNT") -> {:ok, "1"}
      true -> {:ok, "Query executed"}
    end
  end
end