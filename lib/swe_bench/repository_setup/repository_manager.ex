defmodule SweBench.RepositorySetup.RepositoryManager do
  @moduledoc """
  Repository management for SWE-bench evaluation setup.

  Handles cloning, validation, and setup of evaluation repositories
  with comprehensive quality assessment and task extraction.
  """

  require Logger

  alias SweBench.MixProjectManager
  alias SweBench.RepositorySetup.{TaskExtractor, Validator}

  @supported_repositories %{
    # Original 5 repositories
    "phoenix" => %{
      url: "https://github.com/phoenixframework/phoenix",
      stable_version: "v1.7.14",
      type: :umbrella,
      requires_database: true,
      complexity: :high,
      category: :web_framework
    },
    "ecto" => %{
      url: "https://github.com/elixir-ecto/ecto",
      stable_version: "v3.11.2",
      type: :standard,
      requires_database: true,
      complexity: :medium,
      category: :database
    },
    "jason" => %{
      url: "https://github.com/michalmuskala/jason",
      stable_version: "v1.4.4",
      type: :standard,
      requires_database: false,
      complexity: :low,
      category: :json_library
    },
    "tesla" => %{
      url: "https://github.com/elixir-tesla/tesla",
      stable_version: "v1.9.0",
      type: :standard,
      requires_database: false,
      complexity: :medium,
      category: :http_client
    },
    "credo" => %{
      url: "https://github.com/rrrene/credo",
      stable_version: "v1.7.7",
      type: :standard,
      requires_database: false,
      complexity: :medium,
      category: :code_quality
    },

    # New repositories for Phase 2.6 expansion

    # Task 2.6.1: Phoenix LiveView repository
    "phoenix_live_view" => %{
      url: "https://github.com/phoenixframework/phoenix_live_view",
      stable_version: "v0.20.2",
      type: :standard,
      requires_database: true,
      complexity: :very_high,
      category: :real_time_web,
      special_requirements: %{
        javascript_assets: true,
        websocket_testing: true,
        browser_automation: true,
        asset_compilation: ["esbuild", "tailwind"]
      }
    },

    # Task 2.6.2: Oban job processor
    "oban" => %{
      url: "https://github.com/sorentwo/oban",
      stable_version: "v2.16.3",
      type: :standard,
      requires_database: true,
      complexity: :high,
      category: :job_processing,
      special_requirements: %{
        postgresql_required: true,
        job_queue_testing: true,
        time_based_scenarios: true,
        background_job_simulation: true
      }
    },

    # Task 2.6.3: Broadway data pipeline
    "broadway" => %{
      url: "https://github.com/dashbitco/broadway",
      stable_version: "v1.0.7",
      type: :standard,
      requires_database: false,
      complexity: :high,
      category: :data_pipeline,
      special_requirements: %{
        message_queue_mocks: true,
        producer_consumer_testing: true,
        backpressure_scenarios: true,
        flow_control_validation: true
      }
    },

    # Task 2.6.4: Remaining 7 repositories

    # Benchee performance library
    "benchee" => %{
      url: "https://github.com/bencheeorg/benchee",
      stable_version: "v1.3.0",
      type: :standard,
      requires_database: false,
      complexity: :medium,
      category: :performance_testing,
      special_requirements: %{
        benchmark_execution: true,
        performance_metrics: true,
        statistical_analysis: true
      }
    },

    # ExDoc documentation generator
    "ex_doc" => %{
      url: "https://github.com/elixir-lang/ex_doc",
      stable_version: "v0.31.0",
      type: :standard,
      requires_database: false,
      complexity: :medium,
      category: :documentation,
      special_requirements: %{
        html_generation: true,
        markdown_processing: true,
        documentation_validation: true
      }
    },

    # Bamboo email library
    "bamboo" => %{
      url: "https://github.com/beam-community/bamboo",
      stable_version: "v2.3.0",
      type: :standard,
      requires_database: false,
      complexity: :medium,
      category: :email_delivery,
      special_requirements: %{
        email_testing: true,
        smtp_mocking: true,
        adapter_testing: true
      }
    },

    # Guardian authentication
    "guardian" => %{
      url: "https://github.com/ueberauth/guardian",
      stable_version: "v2.3.2",
      type: :standard,
      requires_database: true,
      complexity: :medium,
      category: :authentication,
      special_requirements: %{
        jwt_testing: true,
        token_validation: true,
        session_management: true
      }
    },

    # Absinthe GraphQL
    "absinthe" => %{
      url: "https://github.com/absinthe-graphql/absinthe",
      stable_version: "v1.7.5",
      type: :umbrella,
      requires_database: false,
      complexity: :high,
      category: :graphql,
      special_requirements: %{
        schema_validation: true,
        query_testing: true,
        resolver_testing: true,
        subscription_testing: true
      }
    },

    # Nx numerical computing
    "nx" => %{
      url: "https://github.com/elixir-nx/nx",
      stable_version: "v0.6.4",
      type: :umbrella,
      requires_database: false,
      complexity: :very_high,
      category: :numerical_computing,
      special_requirements: %{
        numerical_testing: true,
        tensor_operations: true,
        # For container environment
        gpu_compatibility: false,
        large_computation_handling: true
      }
    },

    # Membrane multimedia framework
    "membrane" => %{
      url: "https://github.com/membraneframework/membrane_core",
      stable_version: "v1.0.1",
      type: :umbrella,
      requires_database: false,
      complexity: :very_high,
      category: :multimedia,
      special_requirements: %{
        multimedia_testing: true,
        pipeline_testing: true,
        streaming_simulation: true,
        # Simplified for container environment
        codec_testing: false
      }
    }
  }

  @doc """
  Sets up all supported repositories for evaluation.
  """
  def setup_all_repositories(base_path, opts \\ []) do
    Logger.info("Setting up all repositories for evaluation")

    parallel = Keyword.get(opts, :parallel, true)

    if parallel do
      setup_repositories_parallel(base_path, opts)
    else
      setup_repositories_sequential(base_path, opts)
    end
  end

  @doc """
  Sets up a single repository for evaluation.
  """
  def setup_repository(repository_name, base_path, opts \\ []) do
    Logger.info("Setting up repository: #{repository_name}")

    case Map.get(@supported_repositories, repository_name) do
      nil ->
        {:error, {:unsupported_repository, repository_name}}

      repo_config ->
        perform_repository_setup(repository_name, repo_config, base_path, opts)
    end
  end

  @doc """
  Validates repository setup and compatibility.
  """
  def validate_repository_setup(repository_name, repository_path, _opts \\ []) do
    Logger.debug("Validating repository setup: #{repository_name}")

    with {:ok, repo_config} <- get_repository_config(repository_name),
         {:ok, project_analysis} <- MixProjectManager.get_project_status(repository_path),
         {:ok, test_validation} <- Validator.validate_test_suite(repository_path, repo_config),
         {:ok, docker_validation} <-
           Validator.validate_docker_execution(repository_path, repo_config),
         {:ok, task_sample} <-
           TaskExtractor.extract_sample_tasks(repository_name, repository_path, 10) do
      validation_result = %{
        repository: repository_name,
        project_analysis: project_analysis,
        test_validation: test_validation,
        docker_validation: docker_validation,
        extracted_tasks: length(task_sample.tasks),
        quality_score: calculate_quality_score(test_validation, docker_validation, task_sample),
        validated_at: DateTime.utc_now()
      }

      Logger.info(
        "Repository validation complete: #{repository_name} (score: #{validation_result.quality_score})"
      )

      {:ok, validation_result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets configuration for a supported repository.
  """
  def get_repository_config(repository_name) do
    case Map.get(@supported_repositories, repository_name) do
      nil -> {:error, {:unsupported_repository, repository_name}}
      config -> {:ok, config}
    end
  end

  @doc """
  Lists all supported repositories with their configurations.
  """
  def list_supported_repositories do
    {:ok, @supported_repositories}
  end

  @doc """
  Gets repository setup status and statistics.
  """
  def get_setup_status(base_path) do
    repository_statuses =
      Map.new(@supported_repositories, fn {name, _config} ->
        repo_path = Path.join(base_path, name)
        status = if File.exists?(repo_path), do: :setup, else: :not_setup
        {name, status}
      end)

    stats = %{
      total_repositories: map_size(@supported_repositories),
      setup_count: Enum.count(repository_statuses, fn {_name, status} -> status == :setup end),
      repositories: repository_statuses
    }

    {:ok, stats}
  end

  # Private helper functions

  defp setup_repositories_parallel(base_path, opts) do
    tasks =
      Map.keys(@supported_repositories)
      |> Enum.map(fn repo_name ->
        Task.async(fn ->
          setup_repository(repo_name, base_path, opts)
        end)
      end)

    results = Task.await_many(tasks, :timer.minutes(30))

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    {:ok,
     %{
       successful: length(successes),
       failed: length(failures),
       results: results
     }}
  end

  defp setup_repositories_sequential(base_path, opts) do
    results =
      Enum.map(@supported_repositories, fn {repo_name, _config} ->
        setup_repository(repo_name, base_path, opts)
      end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    {:ok,
     %{
       successful: length(successes),
       failed: length(failures),
       results: results
     }}
  end

  defp perform_repository_setup(repository_name, repo_config, base_path, opts) do
    repository_path = Path.join(base_path, repository_name)

    with :ok <- clone_repository(repo_config, repository_path, opts),
         :ok <- checkout_stable_version(repository_path, repo_config.stable_version),
         {:ok, validation} <- validate_repository_setup(repository_name, repository_path, opts) do
      setup_result = %{
        repository: repository_name,
        path: repository_path,
        config: repo_config,
        validation: validation,
        setup_at: DateTime.utc_now()
      }

      Logger.info("Repository setup complete: #{repository_name}")
      {:ok, setup_result}
    else
      {:error, reason} ->
        Logger.error("Repository setup failed for #{repository_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp clone_repository(repo_config, target_path, opts) do
    if File.exists?(target_path) and not Keyword.get(opts, :force, false) do
      Logger.debug("Repository already exists at #{target_path}")
      :ok
    else
      Logger.debug("Cloning repository from #{repo_config.url}")

      # Placeholder for git clone - would use System.cmd("git", ["clone", ...])
      File.mkdir_p!(target_path)
      :ok
    end
  end

  defp checkout_stable_version(_repository_path, version) do
    Logger.debug("Checking out stable version: #{version}")

    # Placeholder for git checkout - would use System.cmd("git", ["checkout", version])
    :ok
  end

  defp calculate_quality_score(test_validation, docker_validation, task_sample) do
    test_score = if test_validation.test_suite_complete, do: 30, else: 0
    docker_score = if docker_validation.docker_compatible, do: 25, else: 0
    task_score = min(45, task_sample.extracted_count * 4.5)

    round(test_score + docker_score + task_score)
  end
end
