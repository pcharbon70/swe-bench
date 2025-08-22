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
    "phoenix" => %{
      url: "https://github.com/phoenixframework/phoenix",
      stable_version: "v1.7.14",
      type: :umbrella,
      requires_database: true,
      complexity: :high
    },
    "ecto" => %{
      url: "https://github.com/elixir-ecto/ecto",
      stable_version: "v3.11.2",
      type: :standard,
      requires_database: true,
      complexity: :medium
    },
    "jason" => %{
      url: "https://github.com/michalmuskala/jason",
      stable_version: "v1.4.4",
      type: :standard,
      requires_database: false,
      complexity: :low
    },
    "tesla" => %{
      url: "https://github.com/elixir-tesla/tesla",
      stable_version: "v1.9.0",
      type: :standard,
      requires_database: false,
      complexity: :medium
    },
    "credo" => %{
      url: "https://github.com/rrrene/credo",
      stable_version: "v1.7.7",
      type: :standard,
      requires_database: false,
      complexity: :medium
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
