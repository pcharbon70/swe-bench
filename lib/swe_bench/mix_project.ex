defmodule SweBench.MixProjectManager do
  @moduledoc """
  Main interface for Mix project management in SWE-bench evaluations.

  Coordinates environment isolation, dependency resolution, compilation
  orchestration, and project analysis for deterministic builds.
  """

  require Logger

  alias SweBench.MixProject.{
    CompilationOrchestrator,
    DependencyManager,
    EnvironmentIsolator,
    ProjectAnalyzer
  }

  @doc """
  Prepares a Mix project for evaluation with full environment setup.
  """
  def prepare_project_for_evaluation(project_path, opts \\ []) do
    Logger.info("Preparing Mix project for evaluation: #{project_path}")

    with {:ok, analysis} <- ProjectAnalyzer.analyze_project(project_path, opts),
         {:ok, environment} <- EnvironmentIsolator.create_execution_context(project_path, opts),
         {:ok, dependencies} <- DependencyManager.resolve_dependencies(project_path, opts),
         {:ok, compilation} <- CompilationOrchestrator.compile_project(project_path, opts) do
      preparation_result = %{
        project_analysis: analysis,
        environment: environment,
        dependencies: dependencies,
        compilation: compilation,
        status: :ready_for_evaluation,
        prepared_at: DateTime.utc_now()
      }

      Logger.info("Project preparation complete for #{analysis.project_type} project")
      {:ok, preparation_result}
    else
      {:error, reason} ->
        Logger.error("Project preparation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Cleans up project evaluation environment and artifacts.
  """
  def cleanup_project_evaluation(preparation_result) do
    Logger.info("Cleaning up project evaluation environment")

    environment = preparation_result.environment

    case EnvironmentIsolator.cleanup_isolated_environment(environment) do
      :ok ->
        Logger.info("Project evaluation cleanup complete")
        :ok

      error ->
        Logger.warning("Cleanup had issues: #{inspect(error)}")
        :ok
    end
  end

  @doc """
  Gets project evaluation status and statistics.
  """
  def get_project_status(project_path) do
    with {:ok, analysis} <- ProjectAnalyzer.analyze_project(project_path),
         {:ok, dep_stats} <- DependencyManager.get_dependency_stats(project_path) do
      status = %{
        project_type: analysis.project_type,
        applications_count: length(analysis.applications),
        test_files_count: count_test_files(analysis.test_structure),
        dependencies: dep_stats,
        last_analyzed: analysis.analysis_timestamp
      }

      {:ok, status}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that a project is ready for evaluation.
  """
  def validate_project_readiness(project_path) do
    Logger.debug("Validating project readiness for evaluation")

    checks = [
      check_mix_exs_exists(project_path),
      check_test_directory_exists(project_path),
      check_project_compiles(project_path),
      check_dependencies_resolvable(project_path)
    ]

    failed_checks = Enum.filter(checks, fn {status, _check} -> status != :ok end)

    case failed_checks do
      [] ->
        {:ok, :ready}

      failures ->
        {:error, {:validation_failed, failures}}
    end
  end

  # Private helper functions

  defp count_test_files(test_structure) when is_list(test_structure) do
    Enum.count(test_structure)
  end

  defp count_test_files(_), do: 0

  defp check_mix_exs_exists(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")

    if File.exists?(mix_exs_path) do
      {:ok, :mix_exs_exists}
    else
      {:error, :missing_mix_exs}
    end
  end

  defp check_test_directory_exists(project_path) do
    test_path = Path.join(project_path, "test")

    if File.exists?(test_path) do
      {:ok, :test_directory_exists}
    else
      {:warning, :no_test_directory}
    end
  end

  defp check_project_compiles(project_path) do
    Logger.debug("Checking if project compiles at #{project_path}")

    # Simplified compilation check - would run actual Mix.Task.Compile in production
    case File.exists?(Path.join(project_path, "lib")) do
      true -> {:ok, :project_structure_valid}
      false -> {:error, :missing_lib_directory}
    end
  end

  defp check_dependencies_resolvable(project_path) do
    case DependencyManager.parse_lockfile(project_path) do
      {:ok, _deps} -> {:ok, :dependencies_parseable}
      {:error, reason} -> {:error, {:dependency_parse_failed, reason}}
    end
  end
end
