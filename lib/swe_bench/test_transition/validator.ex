defmodule SweBench.TestTransition.Validator do
  @moduledoc """
  Core test transition validation logic.

  Implements the main validation workflow including patch application,
  test execution, transition analysis, and quality assessment.
  """

  require Logger

  alias SweBench.Container.{Executor, Pool}
  alias SweBench.TestRunner.{Analyzer, Orchestrator}
  alias SweBench.Issues.{Issue, PullRequest}
  alias SweBench.TestTransition.{PatchApplicator, QualityAssessor, TransitionAnalyzer}

  @doc """
  Validates test transitions for an issue-PR pair with comprehensive analysis.

  ## Parameters
    - issue_pr_link: The validated issue-PR relationship
    - opts: Validation configuration options

  ## Returns
    - {:ok, validation_result} - Successful validation with quality metrics
    - {:error, reason} - Validation failure with detailed error information
  """
  def validate_test_transitions(issue_pr_link, opts \\ []) do
    Logger.info("Starting test transition validation for issue-PR link #{issue_pr_link.id}")

    validation_runs = Keyword.get(opts, :validation_runs, 3)
    timeout = Keyword.get(opts, :timeout, 600_000)

    issue_pr_link
    |> prepare_validation_context(opts)
    |> execute_validation_workflow(validation_runs, timeout)
    |> analyze_validation_results()
    |> assess_benchmark_quality()
  rescue
    error ->
      Logger.error("Validation pipeline error: #{inspect(error)}")
      {:error, {:validation_pipeline_error, error}}
  end

  # Private implementation functions

  defp prepare_validation_context(issue_pr_link, opts) do
    with {:ok, issue} <- Ash.load(issue_pr_link, :issue),
         {:ok, pr} <- Ash.load(issue_pr_link, :pull_request),
         {:ok, repository} <- Ash.load(issue_pr_link, :repository) do
      context = %{
        issue_pr_link: issue_pr_link,
        issue: issue.issue,
        pull_request: pr.pull_request,
        repository: repository.repository,
        base_commit: get_base_commit(pr.pull_request),
        patch_content: get_patch_content(pr.pull_request),
        validation_config: normalize_validation_config(opts)
      }

      {:ok, context}
    else
      {:error, reason} ->
        {:error, {:context_preparation_failed, reason}}
    end
  end

  defp execute_validation_workflow({:ok, context}, validation_runs, timeout) do
    Logger.debug("Executing validation workflow with #{validation_runs} runs")

    with {:ok, container_id} <- acquire_validation_container(),
         {:ok, base_results} <- execute_base_tests(container_id, context, timeout),
         {:ok, patched_results} <-
           execute_multi_run_patched_tests(container_id, context, validation_runs, timeout) do
      validation_results = %{
        context: context,
        base_results: base_results,
        patched_results: patched_results,
        container_id: container_id
      }

      # Always release container
      Pool.release_container(container_id)
      {:ok, validation_results}
    else
      {:error, _reason} = error ->
        # Ensure container cleanup on failure - container_id may not be bound
        error
    end
  end

  defp execute_validation_workflow({:error, reason}, _validation_runs, _timeout) do
    {:error, reason}
  end

  defp acquire_validation_container do
    case Pool.acquire_container() do
      {:ok, container_id} ->
        Logger.debug("Acquired container #{container_id} for validation")
        {:ok, container_id}

      {:error, :no_available_containers} ->
        Logger.warning("No containers available for validation")
        {:error, :container_unavailable}

      {:error, reason} ->
        {:error, {:container_acquisition_failed, reason}}
    end
  end

  defp execute_base_tests(container_id, context, timeout) do
    Logger.debug("Executing base tests on commit #{context.base_commit}")

    with :ok <- setup_repository_at_commit(container_id, context.repository, context.base_commit),
         {:ok, test_results} <- run_tests_in_container(container_id, context, timeout) do
      Logger.debug("Base tests executed: #{count_test_results(test_results)} tests")
      {:ok, test_results}
    end
  end

  defp execute_multi_run_patched_tests(container_id, context, validation_runs, timeout) do
    Logger.debug("Executing #{validation_runs} patched test runs")

    results =
      1..validation_runs
      |> Enum.map(fn run_number ->
        Logger.debug("Executing patched test run #{run_number}/#{validation_runs}")

        with :ok <- reset_to_base_commit(container_id, context.repository, context.base_commit),
             :ok <- apply_patch_in_container(container_id, context.patch_content),
             {:ok, test_results} <- run_tests_in_container(container_id, context, timeout) do
          {:ok, test_results}
        else
          {:error, reason} ->
            Logger.warning("Patched test run #{run_number} failed: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    # Check if all runs succeeded
    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] ->
        successful_results = Enum.map(results, fn {:ok, result} -> result end)
        Logger.debug("All #{validation_runs} patched test runs completed successfully")
        {:ok, successful_results}

      failed_runs ->
        Logger.error("#{length(failed_runs)} patched test runs failed")
        {:error, {:patched_runs_failed, failed_runs}}
    end
  end

  defp setup_repository_at_commit(container_id, _repository, commit_sha) do
    commands = [
      ["git", "checkout", commit_sha],
      ["mix", "deps.get"],
      ["mix", "compile"]
    ]

    case execute_commands_in_container(container_id, commands) do
      {:ok, _outputs} ->
        Logger.debug("Repository setup completed at commit #{commit_sha}")
        :ok

      {:error, reason} ->
        Logger.error("Repository setup failed: #{inspect(reason)}")
        {:error, {:repository_setup_failed, reason}}
    end
  end

  defp apply_patch_in_container(container_id, _patch_content) do
    # Placeholder - will be implemented in Phase 2
    Logger.debug("Applying patch in container #{container_id}")
    :ok
  end

  defp run_tests_in_container(container_id, _context, _timeout) do
    # Placeholder - will use existing TestRunner integration
    Logger.debug("Running tests in container #{container_id}")

    # Mock test results for now
    {:ok,
     %{
       tests: [
         %{name: "test_example", status: :failed, module: "ExampleTest"},
         %{name: "test_another", status: :passed, module: "AnotherTest"}
       ],
       summary: %{passed: 1, failed: 1, total: 2}
     }}
  end

  defp reset_to_base_commit(container_id, _repository, commit_sha) do
    commands = [
      ["git", "reset", "--hard", commit_sha],
      ["git", "clean", "-fd"]
    ]

    case execute_commands_in_container(container_id, commands) do
      {:ok, _outputs} -> :ok
      {:error, reason} -> {:error, {:reset_failed, reason}}
    end
  end

  defp execute_commands_in_container(container_id, commands) do
    # Placeholder - will use existing Container.Executor
    Logger.debug("Executing #{length(commands)} commands in container #{container_id}")
    {:ok, []}
  end

  defp analyze_validation_results({:ok, validation_results}) do
    Logger.debug("Analyzing validation results for quality assessment")

    with {:ok, transitions} <-
           TransitionAnalyzer.analyze_transitions(
             validation_results.base_results,
             validation_results.patched_results
           ),
         {:ok, consistency} <- calculate_consistency_score(validation_results.patched_results),
         {:ok, confidence} <- calculate_confidence_level(transitions) do
      analysis = %{
        validation_results: validation_results,
        transitions: transitions,
        consistency_score: consistency,
        confidence_level: confidence
      }

      {:ok, analysis}
    end
  end

  defp analyze_validation_results({:error, reason}) do
    {:error, reason}
  end

  defp assess_benchmark_quality({:ok, analysis}) do
    with {:ok, quality_tier} <- QualityAssessor.assess_quality(analysis),
         {:ok, final_result} <- compile_final_validation_result(analysis, quality_tier) do
      Logger.info("Validation assessment complete: Quality tier #{quality_tier}")
      {:ok, final_result}
    end
  end

  defp assess_benchmark_quality({:error, reason}) do
    {:error, reason}
  end

  defp get_base_commit(pull_request) do
    # Extract base commit SHA from PR data
    Map.get(
      pull_request,
      :base_sha,
      Map.get(pull_request, "base", %{}) |> Map.get("sha", "HEAD~1")
    )
  end

  defp get_patch_content(pull_request) do
    # Extract patch content from PR data
    Map.get(pull_request, :diff_content, "")
  end

  defp normalize_validation_config(opts) do
    %{
      strict_mode: Keyword.get(opts, :strict_mode, true),
      include_compilation_check: Keyword.get(opts, :include_compilation, true),
      include_static_analysis: Keyword.get(opts, :include_static_analysis, false),
      determinism_threshold: Keyword.get(opts, :determinism_threshold, 0.95)
    }
  end

  defp calculate_consistency_score(patched_results) when is_list(patched_results) do
    # Calculate consistency across multiple runs
    if length(patched_results) <= 1 do
      # Single run is perfectly consistent
      {:ok, 1.0}
    else
      # Placeholder - will implement statistical analysis in Phase 4
      {:ok, 0.95}
    end
  end

  defp calculate_confidence_level(_transitions) do
    # Calculate statistical confidence based on transition patterns
    # Placeholder - will implement in Phase 4
    {:ok, 0.90}
  end

  defp compile_final_validation_result(analysis, quality_tier) do
    result = %{
      issue_pr_link_id: analysis.validation_results.context.issue_pr_link.id,
      repository_id: analysis.validation_results.context.repository.id,
      benchmark_quality: quality_tier,
      consistency_score: analysis.consistency_score,
      confidence_level: analysis.confidence_level,
      fail_to_pass_count: count_transitions(analysis.transitions, :fail_to_pass),
      pass_to_pass_count: count_transitions(analysis.transitions, :pass_to_pass),
      pass_to_fail_count: count_transitions(analysis.transitions, :pass_to_fail),
      validation_runs: length(analysis.validation_results.patched_results),
      flaky_tests: extract_flaky_tests(analysis.transitions)
    }

    {:ok, result}
  end

  defp count_test_results(%{summary: %{total: total}}), do: total
  defp count_test_results(_), do: 0

  defp count_transitions(transitions, type) do
    Map.get(transitions, type, []) |> length()
  end

  defp extract_flaky_tests(_transitions) do
    # Placeholder - will identify inconsistent tests in Phase 4
    []
  end
end
