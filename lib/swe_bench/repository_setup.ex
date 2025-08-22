defmodule SweBench.RepositorySetup do
  @moduledoc """
  Main interface for repository setup and validation in SWE-bench evaluations.

  Coordinates repository cloning, validation, task extraction, and
  evaluation infrastructure compatibility verification.
  """

  require Logger

  alias SweBench.RepositorySetup.{RepositoryManager, TaskExtractor, Validator}

  @doc """
  Performs complete setup and validation for all evaluation repositories.
  """
  def setup_evaluation_repositories(base_path, opts \\ []) do
    Logger.info("Starting complete repository setup and validation")

    with {:ok, setup_results} <- RepositoryManager.setup_all_repositories(base_path, opts),
         {:ok, validation_results} <- validate_all_repositories(base_path, opts),
         {:ok, compatibility_check} <-
           Validator.validate_cross_repository_compatibility(validation_results),
         {:ok, task_extraction} <- extract_tasks_from_all_repositories(base_path, opts) do
      complete_setup = %{
        setup_results: setup_results,
        validation_results: validation_results,
        compatibility_check: compatibility_check,
        task_extraction: task_extraction,
        total_repositories: setup_results.successful,
        total_tasks: count_total_extracted_tasks(task_extraction),
        setup_completed_at: DateTime.utc_now()
      }

      Logger.info(
        "Repository setup complete: #{setup_results.successful} repositories, #{complete_setup.total_tasks} tasks"
      )

      {:ok, complete_setup}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates all setup repositories for evaluation compatibility.
  """
  def validate_all_repositories(base_path, opts \\ []) do
    Logger.debug("Validating all repository setups")

    {:ok, supported_repos} = RepositoryManager.list_supported_repositories()

    validation_results =
      Map.new(supported_repos, fn {repo_name, _config} ->
        repo_path = Path.join(base_path, repo_name)

        validation =
          case RepositoryManager.validate_repository_setup(repo_name, repo_path, opts) do
            {:ok, result} -> result
            {:error, reason} -> %{error: reason, validated: false}
          end

        {repo_name, validation}
      end)

    {:ok, validation_results}
  end

  @doc """
  Extracts evaluation tasks from all setup repositories.
  """
  def extract_tasks_from_all_repositories(base_path, opts \\ []) do
    Logger.debug("Extracting tasks from all repositories")

    task_count_per_repo = Keyword.get(opts, :tasks_per_repository, 10)
    {:ok, supported_repos} = RepositoryManager.list_supported_repositories()

    extraction_results =
      Map.new(supported_repos, fn {repo_name, _config} ->
        repo_path = Path.join(base_path, repo_name)

        extraction =
          case TaskExtractor.extract_sample_tasks(repo_name, repo_path, task_count_per_repo) do
            {:ok, result} -> result
            {:error, reason} -> %{error: reason, extracted_count: 0}
          end

        {repo_name, extraction}
      end)

    {:ok, extraction_results}
  end

  @doc """
  Gets comprehensive status of repository setup and validation.
  """
  def get_evaluation_readiness_status(base_path) do
    Logger.debug("Checking evaluation readiness status")

    with {:ok, setup_status} <- RepositoryManager.get_setup_status(base_path),
         {:ok, validation_results} <- validate_all_repositories(base_path),
         {:ok, task_extractions} <- extract_tasks_from_all_repositories(base_path) do
      readiness = %{
        repositories_setup: setup_status.setup_count,
        total_repositories: setup_status.total_repositories,
        validation_passed: count_passed_validations(validation_results),
        total_tasks_extracted: count_total_extracted_tasks(task_extractions),
        evaluation_ready: evaluation_ready?(setup_status, validation_results, task_extractions),
        status_checked_at: DateTime.utc_now()
      }

      {:ok, readiness}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates evaluation readiness report.
  """
  def generate_readiness_report(base_path) do
    Logger.info("Generating evaluation readiness report")

    case get_evaluation_readiness_status(base_path) do
      {:ok, status} ->
        report = create_detailed_report(status)
        {:ok, report}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp count_total_extracted_tasks(task_extractions) do
    task_extractions
    |> Map.values()
    |> Enum.map(fn extraction ->
      Map.get(extraction, :extracted_count, 0)
    end)
    |> Enum.sum()
  end

  defp count_passed_validations(validation_results) do
    validation_results
    |> Map.values()
    |> Enum.count(fn validation ->
      Map.get(validation, :quality_score, 0) >= 70
    end)
  end

  defp evaluation_ready?(setup_status, validation_results, task_extractions) do
    setup_status.setup_count == setup_status.total_repositories &&
      count_passed_validations(validation_results) >= 4 &&
      count_total_extracted_tasks(task_extractions) >= 40
  end

  defp create_detailed_report(status) do
    %{
      summary: %{
        evaluation_ready: status.evaluation_ready,
        repositories_ready: "#{status.repositories_setup}/#{status.total_repositories}",
        validations_passed: status.validation_passed,
        total_tasks: status.total_tasks_extracted
      },
      recommendations: generate_recommendations(status),
      next_steps: generate_next_steps(status),
      generated_at: status.status_checked_at
    }
  end

  defp generate_recommendations(status) do
    recommendations = []

    recommendations =
      if status.repositories_setup < status.total_repositories,
        do: ["Complete repository setup for remaining repositories" | recommendations],
        else: recommendations

    recommendations =
      if status.validation_passed < 4,
        do: ["Address validation failures to meet minimum requirements" | recommendations],
        else: recommendations

    recommendations =
      if status.total_tasks_extracted < 50,
        do: ["Improve task extraction to reach target of 50 tasks" | recommendations],
        else: recommendations

    if recommendations == [] do
      ["System ready for Phase 2 implementation"]
    else
      recommendations
    end
  end

  defp generate_next_steps(status) do
    if status.evaluation_ready do
      [
        "Proceed to Phase 2: Advanced Evaluation Pipeline",
        "Consider performance optimization and scaling",
        "Plan for additional repository integration"
      ]
    else
      [
        "Complete remaining repository setup tasks",
        "Address validation failures and quality issues",
        "Verify task extraction meets quality standards",
        "Re-run evaluation readiness assessment"
      ]
    end
  end
end
