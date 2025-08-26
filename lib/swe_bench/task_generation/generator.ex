defmodule SweBench.TaskGeneration.Generator do
  @moduledoc """
  Core task instance generation logic.

  Implements the main generation workflow including data extraction,
  format compliance, metadata enrichment, and quality validation.
  """

  use GenServer
  require Logger

  alias SweBench.TaskGeneration.{ComplexityAnalyzer, Enricher, QualityValidator}
  alias SweBench.TaskInstances.TaskInstance
  alias SweBench.ValidationResults.ValidationResult

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates a task instance from validation result.
  """
  def generate_task_instance(validation_result_id, opts \\ []) do
    GenServer.call(__MODULE__, {:generate_instance, validation_result_id, opts})
  end

  @doc """
  Gets generation statistics.
  """
  def get_generation_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      instances_generated: 0,
      instances_failed: 0,
      avg_generation_time: 0.0,
      last_generation: nil
    }

    Logger.info("Task instance generator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_instance, validation_result_id, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      validation_result_id
      |> load_validation_context()
      |> extract_task_data()
      |> enrich_with_metadata(opts)
      |> validate_instance_quality()
      |> persist_task_instance()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_generation_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp load_validation_context(validation_result_id) do
    Logger.debug("Loading validation context for #{validation_result_id}")

    case Ash.get(ValidationResult, validation_result_id) do
      {:ok, validation_result} ->
        case Ash.load(validation_result, [:issue_pr_link, :repository]) do
          {:ok, loaded_result} ->
            context = %{
              validation_result: loaded_result,
              issue_pr_link: loaded_result.issue_pr_link,
              repository: loaded_result.repository
            }

            {:ok, context}

          {:error, reason} ->
            {:error, {:load_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:validation_result_not_found, reason}}
    end
  end

  defp extract_task_data({:ok, context}) do
    Logger.debug("Extracting task data from validation context")

    with {:ok, issue} <- Ash.load(context.issue_pr_link, :issue),
         {:ok, pr} <- Ash.load(context.issue_pr_link, :pull_request) do
      task_data = %{
        context: context,
        instance_id: generate_instance_id(context),
        problem_statement: extract_problem_statement(issue.issue),
        patch_content: extract_patch_content(pr.pull_request),
        base_commit: context.validation_result.base_commit_sha,
        test_transitions: extract_test_transitions(context.validation_result),
        repository: context.repository
      }

      {:ok, task_data}
    end
  end

  defp extract_task_data({:error, reason}) do
    {:error, reason}
  end

  defp enrich_with_metadata({:ok, task_data}, opts) do
    Logger.debug("Enriching task instance with metadata")

    with {:ok, code_analysis} <- Enricher.analyze_code_changes(task_data.patch_content),
         {:ok, complexity_metrics} <- ComplexityAnalyzer.analyze_complexity(task_data),
         {:ok, enriched_metadata} <-
           build_comprehensive_metadata(task_data, code_analysis, complexity_metrics) do
      enriched_task = Map.put(task_data, :enriched_metadata, enriched_metadata)
      {:ok, enriched_task}
    end
  end

  defp enrich_with_metadata({:error, reason}, _opts) do
    {:error, reason}
  end

  defp validate_instance_quality({:ok, task_data}) do
    Logger.debug("Validating instance quality")

    case QualityValidator.validate_task_instance(task_data) do
      {:ok, quality_assessment} ->
        validated_task = Map.put(task_data, :quality_assessment, quality_assessment)
        {:ok, validated_task}

      {:error, reason} ->
        {:error, {:quality_validation_failed, reason}}
    end
  end

  defp validate_instance_quality({:error, reason}) do
    {:error, reason}
  end

  defp persist_task_instance({:ok, task_data}) do
    Logger.debug("Persisting task instance")

    attrs = %{
      instance_id: task_data.instance_id,
      repository_id: task_data.repository.id,
      issue_pr_link_id: task_data.context.issue_pr_link.id,
      validation_result_id: task_data.context.validation_result.id,
      base_commit_sha: task_data.base_commit,
      problem_statement: task_data.problem_statement,
      patch_content: task_data.patch_content,
      hints: extract_hints(task_data),
      test_specification: build_test_specification(task_data),
      solution_specification: build_solution_specification(task_data),
      task_metadata: task_data.enriched_metadata,
      evaluation_metadata: build_evaluation_metadata(task_data),
      quality_tier: determine_quality_tier(task_data.quality_assessment),
      difficulty_level: determine_difficulty_level(task_data),
      content_checksum: calculate_content_checksum(task_data)
    }

    case TaskInstance
         |> Ash.Changeset.for_create(:generate_instance, attrs)
         |> Ash.create() do
      {:ok, instance} ->
        Logger.info("Task instance #{instance.instance_id} generated successfully")
        {:ok, instance}

      {:error, reason} ->
        Logger.error("Failed to persist task instance: #{inspect(reason)}")
        {:error, {:persistence_failed, reason}}
    end
  end

  defp persist_task_instance({:error, reason}) do
    {:error, reason}
  end

  defp generate_instance_id(context) do
    repo_name = String.replace(context.repository.full_name, "/", "__")
    issue_number = extract_issue_number(context.issue_pr_link)
    "#{repo_name}-#{issue_number}"
  end

  defp extract_issue_number(issue_pr_link) do
    # Extract issue number from the relationship
    # Placeholder - will extract from actual issue data
    :rand.uniform(9999)
  end

  defp extract_problem_statement(issue) when is_map(issue) do
    title = Map.get(issue, :title, "")
    body = Map.get(issue, :body, "")

    if String.length(body) > 100 do
      "#{title}\n\n#{body}"
    else
      title
    end
  end

  defp extract_patch_content(pull_request) when is_map(pull_request) do
    Map.get(pull_request, :diff_content, "")
  end

  defp extract_test_transitions(validation_result) do
    %{
      fail_to_pass_count: validation_result.fail_to_pass_count,
      pass_to_pass_count: validation_result.pass_to_pass_count,
      pass_to_fail_count: validation_result.pass_to_fail_count,
      consistency_score: validation_result.consistency_score
    }
  end

  defp build_comprehensive_metadata(task_data, code_analysis, complexity_metrics) do
    metadata = %{
      elixir_analysis: code_analysis,
      complexity_analysis: complexity_metrics,
      test_transitions: task_data.test_transitions,
      generation_info: %{
        generated_at: DateTime.utc_now(),
        generator_version: "1.0.0",
        source_validation_id: task_data.context.validation_result.id
      }
    }

    {:ok, metadata}
  end

  defp extract_hints(task_data) do
    # Extract helpful hints from issue and validation data
    []
  end

  defp build_test_specification(task_data) do
    %{
      # Will be populated from validation result
      fail_to_pass_tests: [],
      test_framework: "ExUnit",
      test_commands: ["mix test"],
      expected_failures: task_data.test_transitions.fail_to_pass_count
    }
  end

  defp build_solution_specification(task_data) do
    %{
      files_changed: count_changed_files(task_data.patch_content),
      lines_modified: count_modified_lines(task_data.patch_content),
      solution_type: classify_solution_type(task_data.patch_content)
    }
  end

  defp build_evaluation_metadata(task_data) do
    %{
      evaluation_framework: "swe-bench-elixir",
      expected_runtime: estimate_runtime(task_data),
      resource_requirements: estimate_resources(task_data),
      complexity_level: task_data.enriched_metadata.complexity_analysis.difficulty_level
    }
  end

  defp determine_quality_tier(quality_assessment) do
    # Map validation quality to task quality tiers
    case Map.get(quality_assessment, :benchmark_quality, :bronze) do
      :gold -> :gold
      :silver -> :silver
      _ -> :bronze
    end
  end

  defp determine_difficulty_level(task_data) do
    # Determine difficulty based on complexity metrics
    # Placeholder - will use actual complexity analysis
    :medium
  end

  defp calculate_content_checksum(task_data) do
    content =
      [
        task_data.problem_statement,
        task_data.patch_content,
        Jason.encode!(task_data.enriched_metadata)
      ]
      |> Enum.join("")

    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp count_changed_files(patch_content) do
    patch_content
    |> String.split("\n")
    |> Enum.count(&String.starts_with?(&1, "diff --git"))
  end

  defp count_modified_lines(patch_content) do
    lines = String.split(patch_content, "\n")
    additions = Enum.count(lines, &String.starts_with?(&1, "+"))
    deletions = Enum.count(lines, &String.starts_with?(&1, "-"))
    additions + deletions
  end

  defp classify_solution_type(patch_content) do
    cond do
      String.contains?(patch_content, "defmodule") -> :module_addition
      String.contains?(patch_content, "def ") -> :function_modification
      String.contains?(patch_content, "test") -> :test_related
      true -> :general_fix
    end
  end

  defp estimate_runtime(_task_data) do
    # Placeholder - will implement runtime estimation
    "5-10 minutes"
  end

  defp estimate_resources(_task_data) do
    # Placeholder - will implement resource estimation
    %{memory_mb: 512, cpu_cores: 1, timeout_minutes: 15}
  end

  defp update_generation_stats(state, result, processing_time) do
    new_total = state.instances_generated + 1

    {new_generated, new_failed} =
      case result do
        {:ok, _instance} -> {state.instances_generated + 1, state.instances_failed}
        {:error, _reason} -> {state.instances_generated, state.instances_failed + 1}
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_generation_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | instances_generated: new_generated,
        instances_failed: new_failed,
        avg_generation_time: new_avg_time,
        last_generation: DateTime.utc_now()
    }
  end
end
