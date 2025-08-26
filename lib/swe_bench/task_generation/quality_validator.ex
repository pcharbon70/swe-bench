defmodule SweBench.TaskGeneration.QualityValidator do
  @moduledoc """
  Quality validation for task instances.

  Implements comprehensive quality assessment including SWE-bench format
  compliance, content validation, and suitability for benchmark tasks.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validates a task instance for quality and format compliance.
  """
  def validate_task_instance(task_data) do
    GenServer.call(__MODULE__, {:validate_instance, task_data})
  end

  @doc """
  Gets validation statistics.
  """
  def get_validation_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      validations_performed: 0,
      validations_passed: 0,
      validations_failed: 0,
      avg_validation_time: 0.0
    }

    Logger.info("Quality validator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:validate_instance, task_data}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      task_data
      |> validate_swe_bench_format()
      |> validate_content_completeness()
      |> validate_patch_integrity()
      |> validate_problem_clarity()
      |> assess_benchmark_suitability()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_validation_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private validation functions

  defp validate_swe_bench_format(task_data) do
    Logger.debug("Validating SWE-bench format compliance")

    required_fields = [:instance_id, :problem_statement, :patch_content, :base_commit]
    missing_fields = Enum.filter(required_fields, &is_nil(Map.get(task_data, &1)))

    if Enum.empty?(missing_fields) do
      add_validation_result(task_data, :format_compliance, :passed, "All required fields present")
    else
      add_validation_result(
        task_data,
        :format_compliance,
        :failed,
        "Missing fields: #{inspect(missing_fields)}"
      )
    end
  end

  defp validate_content_completeness(task_data) do
    Logger.debug("Validating content completeness")

    validations = [
      {String.length(task_data.problem_statement) > 50, "Problem statement too short"},
      {String.length(task_data.patch_content) > 0, "Empty patch content"},
      {Map.get(task_data, :test_transitions, %{}) != %{}, "Missing test transition data"}
    ]

    failed_validations = Enum.filter(validations, fn {passed, _message} -> not passed end)

    if Enum.empty?(failed_validations) do
      add_validation_result(
        task_data,
        :content_completeness,
        :passed,
        "All content validation passed"
      )
    else
      messages = Enum.map(failed_validations, fn {_passed, message} -> message end)

      add_validation_result(
        task_data,
        :content_completeness,
        :warning,
        "Issues: #{Enum.join(messages, ", ")}"
      )
    end
  end

  defp validate_patch_integrity(task_data) do
    Logger.debug("Validating patch integrity")

    patch_content = task_data.patch_content
    integrity_checks = build_integrity_checks(patch_content)

    if Enum.all?(Map.values(integrity_checks)) do
      add_validation_result(task_data, :patch_integrity, :passed, "Patch format valid")
    else
      failed_checks = extract_failed_checks(integrity_checks)

      add_validation_result(
        task_data,
        :patch_integrity,
        :failed,
        "Failed checks: #{inspect(failed_checks)}"
      )
    end
  end

  defp validate_problem_clarity(task_data) do
    Logger.debug("Validating problem clarity")

    problem_statement = task_data.problem_statement
    clarity_metrics = calculate_clarity_metrics(problem_statement)

    passed_count = Enum.count(Map.values(clarity_metrics), & &1)
    clarity_score = passed_count / map_size(clarity_metrics)

    status = determine_clarity_status(clarity_score)

    add_validation_result(
      task_data,
      :problem_clarity,
      status,
      "Clarity score: #{Float.round(clarity_score, 2)}"
    )
  end

  defp assess_benchmark_suitability(task_data) do
    Logger.debug("Assessing benchmark suitability")

    validation_results = Map.get(task_data, :validation_results, [])
    validation_summary = calculate_validation_summary(validation_results)
    benchmark_quality = determine_benchmark_quality(validation_summary)

    quality_assessment = %{
      benchmark_quality: benchmark_quality,
      validation_summary: validation_summary,
      suitability_score: calculate_suitability_score(validation_summary),
      assessment_confidence: calculate_assessment_confidence(validation_summary.total)
    }

    {:ok, quality_assessment}
  end

  # Helper functions for complexity reduction

  defp build_integrity_checks(patch_content) do
    %{
      has_diff_headers: String.contains?(patch_content, "diff --git"),
      has_hunks: String.contains?(patch_content, "@@"),
      has_changes: String.contains?(patch_content, "+") or String.contains?(patch_content, "-"),
      valid_format: validate_patch_format(patch_content)
    }
  end

  defp extract_failed_checks(integrity_checks) do
    integrity_checks
    |> Enum.filter(fn {_check, passed} -> not passed end)
    |> Enum.map(fn {check, _passed} -> check end)
  end

  defp calculate_clarity_metrics(problem_statement) do
    %{
      sufficient_length: String.length(problem_statement) >= 100,
      has_context:
        String.contains?(problem_statement, "when") or
          String.contains?(problem_statement, "should"),
      has_specifics: contains_code_references?(problem_statement),
      clear_requirements: contains_clear_requirements?(problem_statement)
    }
  end

  defp determine_clarity_status(clarity_score) do
    cond do
      clarity_score >= 0.75 -> :passed
      clarity_score >= 0.50 -> :warning
      true -> :failed
    end
  end

  defp calculate_validation_summary(validation_results) do
    %{
      passed: Enum.count(validation_results, &(&1.status == :passed)),
      warnings: Enum.count(validation_results, &(&1.status == :warning)),
      failed: Enum.count(validation_results, &(&1.status == :failed)),
      total: length(validation_results)
    }
  end

  defp determine_benchmark_quality(summary) do
    cond do
      gold_quality?(summary) -> :gold
      silver_quality?(summary) -> :silver
      bronze_quality?(summary) -> :bronze
      true -> :unsuitable
    end
  end

  defp gold_quality?(%{passed: passed, warnings: warnings, failed: failed}) do
    failed == 0 and warnings <= 1 and passed >= 3
  end

  defp silver_quality?(%{passed: passed, warnings: warnings, failed: failed}) do
    failed == 0 and warnings <= 2 and passed >= 2
  end

  defp bronze_quality?(%{passed: passed, failed: failed}) do
    failed <= 1 and passed >= 2
  end

  defp add_validation_result(task_data, stage, status, message) do
    validation_result = %{
      stage: stage,
      status: status,
      message: message,
      timestamp: DateTime.utc_now()
    }

    existing_results = Map.get(task_data, :validation_results, [])
    Map.put(task_data, :validation_results, [validation_result | existing_results])
  end

  defp validate_patch_format(patch_content) do
    # Basic patch format validation
    lines = String.split(patch_content, "\n")

    has_file_headers = Enum.any?(lines, &String.starts_with?(&1, "diff --git"))
    has_hunks = Enum.any?(lines, &String.starts_with?(&1, "@@"))

    has_file_headers and has_hunks
  end

  defp contains_code_references?(text) do
    code_patterns = [~r/`[^`]+`/, ~r/def\s+\w+/, ~r/\w+\.\w+/, ~r/:[a-z_]+/]
    Enum.any?(code_patterns, &Regex.match?(&1, text))
  end

  defp contains_clear_requirements?(text) do
    requirement_words = ["should", "must", "need", "require", "expect"]
    Enum.any?(requirement_words, &String.contains?(String.downcase(text), &1))
  end

  defp calculate_suitability_score(%{passed: passed, warnings: warnings, failed: failed}) do
    total = passed + warnings + failed

    if total > 0 do
      (passed * 1.0 + warnings * 0.5 + failed * 0.0) / total
    else
      0.0
    end
  end

  defp calculate_assessment_confidence(total_validations) do
    # Higher confidence with more validation data points
    case total_validations do
      0 -> 0.0
      1 -> 0.3
      2 -> 0.6
      3 -> 0.8
      _ -> 0.95
    end
  end

  defp update_validation_stats(state, result, processing_time) do
    new_total = state.validations_performed + 1

    {new_passed, new_failed} =
      case result do
        {:ok, _} -> {state.validations_passed + 1, state.validations_failed}
        {:error, _} -> {state.validations_passed, state.validations_failed + 1}
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_validation_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | validations_performed: new_total,
        validations_passed: new_passed,
        validations_failed: new_failed,
        avg_validation_time: new_avg_time
    }
  end
end
