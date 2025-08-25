defmodule SweBench.TestTransition.Worker do
  @moduledoc """
  Individual worker process for test transition validation.

  Handles the complete validation workflow from patch application through
  test execution to transition analysis with proper error handling.
  """

  use GenServer
  require Logger

  alias SweBench.ValidationResults.ValidationResult
  alias SweBench.TestTransition.Validator

  defstruct [
    :job,
    :coordinator,
    :start_time,
    :current_operation,
    :validation_results
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    job = Keyword.fetch!(opts, :job)
    coordinator = Keyword.fetch!(opts, :coordinator)

    state = %__MODULE__{
      job: job,
      coordinator: coordinator,
      start_time: DateTime.utc_now(),
      current_operation: :initializing,
      validation_results: nil
    }

    # Start validation immediately
    send(self(), :start_validation)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_validation, state) do
    Logger.info("Starting validation job #{state.job.id}")

    case execute_validation_pipeline(state) do
      {:ok, results} ->
        complete_validation_job(state, results)

      {:error, reason} ->
        fail_validation_job(state, reason)
    end

    {:stop, :normal, state}
  end

  # Private implementation functions

  defp execute_validation_pipeline(state) do
    state.job.issue_pr_link_id
    |> load_validation_context()
    |> execute_core_validation(state.job)
    |> persist_validation_results(state.job)
    |> compile_worker_results(state)
  end

  defp load_validation_context(issue_pr_link_id) do
    Logger.debug("Loading validation context for issue-PR link #{issue_pr_link_id}")

    case Ash.get(SweBench.Issues.IssuePrLink, issue_pr_link_id) do
      {:ok, issue_pr_link} ->
        case Ash.load(issue_pr_link, [:issue, :pull_request, :repository]) do
          {:ok, loaded_link} ->
            context = %{
              issue_pr_link: loaded_link,
              issue: loaded_link.issue,
              pull_request: loaded_link.pull_request,
              repository: loaded_link.repository
            }

            {:ok, context}

          {:error, reason} ->
            {:error, {:load_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:link_not_found, reason}}
    end
  end

  defp execute_core_validation({:ok, context}, job) do
    Logger.debug("Executing core validation for repository #{context.repository.full_name}")

    validation_opts = [
      validation_runs: job.validation_runs,
      timeout: job.timeout,
      confidence_threshold: job.confidence_threshold
    ]

    case Validator.validate_test_transitions(context.issue_pr_link, validation_opts) do
      {:ok, validation_result} ->
        {:ok, {context, validation_result}}

      {:error, reason} ->
        {:error, {:core_validation_failed, reason}}
    end
  end

  defp execute_core_validation({:error, reason}, _job) do
    {:error, reason}
  end

  defp persist_validation_results({:ok, {context, validation_result}}, job) do
    Logger.debug("Persisting validation results")

    attrs = %{
      issue_pr_link_id: context.issue_pr_link.id,
      repository_id: context.repository.id,
      base_commit_sha: extract_base_commit_sha(context),
      patch_sha256: calculate_patch_hash(context),
      validation_runs: job.validation_runs,
      consistency_score: validation_result.consistency_score,
      confidence_level: validation_result.confidence_level,
      benchmark_quality: validation_result.benchmark_quality,
      fail_to_pass_count: validation_result.fail_to_pass_count,
      pass_to_pass_count: validation_result.pass_to_pass_count,
      pass_to_fail_count: validation_result.pass_to_fail_count,
      flaky_tests: validation_result.flaky_tests,
      validation_metadata: %{
        job_id: job.id,
        validation_version: "1.0.0",
        created_by: "automated_validation"
      }
    }

    case ValidationResult
         |> Ash.Changeset.for_create(:create_validation, attrs)
         |> Ash.create() do
      {:ok, persisted_result} ->
        {:ok, {context, validation_result, persisted_result}}

      {:error, reason} ->
        Logger.error("Failed to persist validation result: #{inspect(reason)}")
        {:error, {:persistence_failed, reason}}
    end
  end

  defp persist_validation_results({:error, reason}, _job) do
    {:error, reason}
  end

  defp compile_worker_results({:ok, {context, validation_result, persisted_result}}, state) do
    processing_time = DateTime.diff(DateTime.utc_now(), state.start_time, :millisecond)

    worker_result = %{
      validation_id: state.job.id,
      issue_pr_link_id: context.issue_pr_link.id,
      repository_name: context.repository.full_name,
      benchmark_quality: validation_result.benchmark_quality,
      consistency_score: validation_result.consistency_score,
      confidence_level: validation_result.confidence_level,
      processing_time_ms: processing_time,
      persisted_result_id: persisted_result.id
    }

    {:ok, worker_result}
  end

  defp compile_worker_results({:error, reason}, _state) do
    {:error, reason}
  end

  defp extract_base_commit_sha(context) do
    # Extract from PR data or use repository default
    case Map.get(context.pull_request, :base_sha) do
      sha when is_binary(sha) -> sha
      _ -> "HEAD~1"
    end
  end

  defp calculate_patch_hash(context) do
    patch_content = Map.get(context.pull_request, :diff_content, "")
    :crypto.hash(:sha256, patch_content) |> Base.encode16(case: :lower)
  end

  defp complete_validation_job(state, results) do
    Logger.info("Completing validation job #{state.job.id}")

    # Notify coordinator
    send(state.coordinator, {:worker_completed, self(), state.job.id, results})
  end

  defp fail_validation_job(state, reason) do
    Logger.error("Validation job #{state.job.id} failed: #{inspect(reason)}")

    # Notify coordinator
    send(state.coordinator, {:worker_failed, self(), state.job.id, reason})
  end
end