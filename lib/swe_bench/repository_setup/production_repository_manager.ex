defmodule SweBench.RepositorySetup.ProductionRepositoryManager do
  @moduledoc """
  Production-tier repository management for complex applications.

  Handles Plausible Analytics, Changelog.com, and other production applications
  requiring specialized environments, dependencies, and testing scenarios.
  """

  use GenServer
  require Logger

  alias SweBench.RepositorySetup.{
    ResourceAllocationManager,
    ValidationFramework
  }

  defstruct [
    :config,
    :production_repositories,
    :resource_allocations,
    :validation_results
  ]

  @production_repositories [
    %{
      name: "plausible_analytics",
      github_url: "https://github.com/plausible/analytics",
      tier: :production,
      complexity: :high,
      dependencies: [:clickhouse, :postgresql, :redis],
      resource_requirements: %{
        memory: "8GB",
        cpu: "4",
        disk: "20GB",
        timeout_multiplier: 3.0
      },
      testing_scenarios: [
        :analytics_pipeline,
        :large_scale_data,
        :real_time_processing,
        :dashboard_queries,
        :data_retention
      ],
      target_instances: 20
    },
    %{
      name: "changelog_platform",
      github_url: "https://github.com/thechangelog/changelog.com",
      tier: :production,
      complexity: :high,
      dependencies: [:ffmpeg, :imagemagick, :postgresql, :redis],
      resource_requirements: %{
        memory: "6GB",
        cpu: "3",
        disk: "15GB",
        timeout_multiplier: 2.5
      },
      testing_scenarios: [
        :media_processing,
        :cms_functionality,
        :file_uploads,
        :podcast_generation,
        :content_delivery
      ],
      target_instances: 15
    }
  ]

  @doc """
  Starts the production repository manager with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Configures a production repository for evaluation.
  """
  def configure_production_repository(repository_name, options \\ []) do
    GenServer.call(
      __MODULE__,
      {:configure_production_repository, repository_name, options},
      300_000
    )
  end

  @doc """
  Returns the list of supported production repositories.
  """
  def list_production_repositories do
    @production_repositories
  end

  @doc """
  Gets production repository configuration and status.
  """
  def get_repository_status(repository_name) do
    GenServer.call(__MODULE__, {:get_repository_status, repository_name})
  end

  @doc """
  Generates task instances for production repositories.
  """
  def generate_production_task_instances(repository_name, count \\ nil) do
    GenServer.call(__MODULE__, {:generate_task_instances, repository_name, count}, 600_000)
  end

  @impl true
  def init(config) do
    production_config = Enum.into(config, %{})

    state = %__MODULE__{
      config: production_config,
      production_repositories: %{},
      resource_allocations: %{},
      validation_results: %{}
    }

    Logger.info("ProductionRepositoryManager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:configure_production_repository, repository_name, options}, _from, state) do
    repository_spec = find_repository_spec(repository_name)

    case repository_spec do
      nil ->
        {:reply, {:error, :repository_not_found}, state}

      spec ->
        configuration_result = perform_production_configuration(spec, options, state)

        case configuration_result do
          {:ok, config_data} ->
            new_repositories =
              Map.put(state.production_repositories, repository_name, config_data)

            new_state = %{state | production_repositories: new_repositories}
            {:reply, {:ok, config_data}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  rescue
    error ->
      Logger.error("Production repository configuration failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  @impl true
  def handle_call({:get_repository_status, repository_name}, _from, state) do
    status = Map.get(state.production_repositories, repository_name, :not_configured)
    {:reply, status, state}
  end

  @impl true
  def handle_call({:generate_task_instances, repository_name, count}, _from, state) do
    repository_config = Map.get(state.production_repositories, repository_name)

    case repository_config do
      nil ->
        {:reply, {:error, :repository_not_configured}, state}

      config ->
        task_generation_result = generate_production_tasks(config, count)
        {:reply, task_generation_result, state}
    end
  rescue
    error ->
      Logger.error("Task instance generation failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp find_repository_spec(repository_name) do
    @production_repositories
    |> Enum.find(fn repo -> repo.name == to_string(repository_name) end)
  end

  defp perform_production_configuration(repository_spec, options, _state) do
    Logger.info("Configuring production repository: #{repository_spec.name}")

    # Allocate resources based on repository requirements
    resource_allocation =
      ResourceAllocationManager.allocate_production_resources(
        repository_spec,
        options
      )

    # Set up specialized environment based on repository type
    environment_config = setup_production_environment(repository_spec, resource_allocation)

    # Validate configuration
    validation_result =
      ValidationFramework.validate_production_configuration(
        repository_spec,
        environment_config
      )

    case validation_result do
      {:ok, _validation_data} ->
        config_data = %{
          repository_spec: repository_spec,
          resource_allocation: resource_allocation,
          environment_config: environment_config,
          validation_result: validation_result,
          configured_at: DateTime.utc_now(),
          status: :ready
        }

        {:ok, config_data}

      {:error, reason} ->
        {:error, {:validation_failed, reason}}
    end
  end

  defp setup_production_environment(repository_spec, resource_allocation) do
    case repository_spec.name do
      "plausible_analytics" ->
        setup_plausible_environment(repository_spec, resource_allocation)

      "changelog_platform" ->
        setup_changelog_environment(repository_spec, resource_allocation)

      _ ->
        setup_generic_production_environment(repository_spec, resource_allocation)
    end
  end

  defp setup_plausible_environment(repository_spec, resource_allocation) do
    %{
      container_configuration: %{
        main_app: %{
          image: "elixir:1.15-alpine",
          memory: resource_allocation.memory_limit,
          cpu: resource_allocation.cpu_limit,
          environment: %{
            "MIX_ENV" => "test",
            "DATABASE_URL" => "postgres://postgres:postgres@db:5432/plausible_test",
            "CLICKHOUSE_DATABASE_URL" => "http://clickhouse:8123/plausible_ch_test"
          }
        },
        clickhouse: %{
          image: "clickhouse/clickhouse-server:latest",
          memory: "2GB",
          ports: ["8123:8123", "9000:9000"],
          volumes: ["clickhouse_data:/var/lib/clickhouse"],
          environment: %{
            "CLICKHOUSE_DB" => "plausible_ch_test",
            "CLICKHOUSE_USER" => "test_user",
            "CLICKHOUSE_PASSWORD" => "test_pass"
          }
        },
        postgresql: %{
          image: "postgres:13",
          memory: "1GB",
          environment: %{
            "POSTGRES_DB" => "plausible_test",
            "POSTGRES_USER" => "postgres",
            "POSTGRES_PASSWORD" => "postgres"
          }
        }
      },
      testing_scenarios: repository_spec.testing_scenarios,
      dependency_setup: [
        {:database_migration, "mix ecto.create && mix ecto.migrate"},
        {:clickhouse_init, "mix plausible.clickhouse.init"},
        {:seed_data, "mix run priv/repo/seeds.exs"}
      ]
    }
  end

  defp setup_changelog_environment(repository_spec, resource_allocation) do
    %{
      container_configuration: %{
        main_app: %{
          image: "elixir:1.15-alpine",
          memory: resource_allocation.memory_limit,
          cpu: resource_allocation.cpu_limit,
          environment: %{
            "MIX_ENV" => "test",
            "DATABASE_URL" => "postgres://postgres:postgres@db:5432/changelog_test",
            "AWS_ACCESS_KEY_ID" => "test",
            "AWS_SECRET_ACCESS_KEY" => "test"
          }
        },
        media_processor: %{
          image: "jrottenberg/ffmpeg:alpine",
          memory: "2GB",
          volumes: ["media_processing:/tmp/media"]
        },
        postgresql: %{
          image: "postgres:13",
          memory: "1GB",
          environment: %{
            "POSTGRES_DB" => "changelog_test",
            "POSTGRES_USER" => "postgres",
            "POSTGRES_PASSWORD" => "postgres"
          }
        }
      },
      testing_scenarios: repository_spec.testing_scenarios,
      dependency_setup: [
        {:database_migration, "mix ecto.create && mix ecto.migrate"},
        {:media_setup, "mkdir -p /tmp/media && chmod 777 /tmp/media"},
        {:cdn_mock, "mix test.setup_cdn_mock"}
      ]
    }
  end

  defp setup_generic_production_environment(repository_spec, resource_allocation) do
    %{
      container_configuration: %{
        main_app: %{
          image: "elixir:1.15-alpine",
          memory: resource_allocation.memory_limit,
          cpu: resource_allocation.cpu_limit,
          environment: %{
            "MIX_ENV" => "test"
          }
        }
      },
      testing_scenarios: repository_spec.testing_scenarios,
      dependency_setup: []
    }
  end

  defp generate_production_tasks(repository_config, count) do
    repository_spec = repository_config.repository_spec
    target_count = count || repository_spec.target_instances

    Logger.info("Generating #{target_count} task instances for #{repository_spec.name}")

    # Generate tasks based on testing scenarios
    task_instances =
      repository_spec.testing_scenarios
      |> Enum.flat_map(fn scenario ->
        generate_tasks_for_scenario(repository_spec, scenario, target_count)
      end)
      |> Enum.take(target_count)

    if length(task_instances) >= target_count do
      {:ok,
       %{
         repository: repository_spec.name,
         task_instances: task_instances,
         total_generated: length(task_instances),
         scenarios_covered: repository_spec.testing_scenarios
       }}
    else
      {:error, :insufficient_task_generation}
    end
  end

  defp generate_tasks_for_scenario(repository_spec, scenario, total_target) do
    scenario_target = div(total_target, length(repository_spec.testing_scenarios))

    1..scenario_target
    |> Enum.map(fn i ->
      %{
        id: "#{repository_spec.name}_#{scenario}_#{i}",
        repository: repository_spec.name,
        scenario: scenario,
        complexity: determine_scenario_complexity(scenario),
        description: generate_scenario_description(repository_spec.name, scenario),
        test_requirements: generate_scenario_test_requirements(scenario),
        created_at: DateTime.utc_now()
      }
    end)
  end

  defp determine_scenario_complexity(:analytics_pipeline), do: :expert
  defp determine_scenario_complexity(:large_scale_data), do: :expert
  defp determine_scenario_complexity(:media_processing), do: :high
  defp determine_scenario_complexity(:cms_functionality), do: :high
  defp determine_scenario_complexity(:real_time_processing), do: :high
  defp determine_scenario_complexity(:file_uploads), do: :medium
  defp determine_scenario_complexity(:podcast_generation), do: :medium
  defp determine_scenario_complexity(_), do: :medium

  defp generate_scenario_description("plausible_analytics", :analytics_pipeline) do
    "Implement analytics data pipeline with ClickHouse integration for real-time event processing and aggregation"
  end

  defp generate_scenario_description("plausible_analytics", :large_scale_data) do
    "Handle large-scale analytics data processing with efficient query optimization and data retention policies"
  end

  defp generate_scenario_description("changelog_platform", :media_processing) do
    "Implement media file processing pipeline with ffmpeg integration for podcast and video content"
  end

  defp generate_scenario_description("changelog_platform", :cms_functionality) do
    "Build content management system functionality with article publishing and podcast feed generation"
  end

  defp generate_scenario_description(repository, scenario) do
    "Implement #{scenario} functionality for #{repository} production application"
  end

  defp generate_scenario_test_requirements(:analytics_pipeline) do
    [
      "ClickHouse integration tests",
      "Real-time data ingestion validation",
      "Query performance benchmarks",
      "Data aggregation accuracy"
    ]
  end

  defp generate_scenario_test_requirements(:media_processing) do
    [
      "File upload handling tests",
      "Media format conversion validation",
      "CDN integration tests",
      "Processing pipeline reliability"
    ]
  end

  defp generate_scenario_test_requirements(scenario) do
    ["Integration tests for #{scenario}", "Unit test coverage", "Performance validation"]
  end
end
