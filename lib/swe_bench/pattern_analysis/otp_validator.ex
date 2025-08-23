defmodule SweBench.PatternAnalysis.OTPValidator do
  @moduledoc """
  Main OTP behavior validation coordinator.

  Orchestrates comprehensive OTP behavior analysis including GenServer validation,
  Supervisor analysis, behavior compliance checking, and process metrics collection.
  Integrates seamlessly with the existing pattern analysis system.
  """

  require Logger

  alias SweBench.PatternAnalysis.OTP.{
    BehaviorChecker,
    GenServerValidator,
    ProcessMetrics,
    SupervisorAnalyzer,
    ValidationSchemas
  }

  @doc """
  Performs comprehensive OTP behavior validation on Elixir source code.

  Returns a structured validation result compatible with the existing
  pattern analysis pipeline.
  """
  def validate_otp_behaviors(source_code, opts \\ []) when is_binary(source_code) do
    Logger.info("Starting OTP behavior validation")
    start_time = System.monotonic_time(:millisecond)

    validation_phases = Keyword.get(opts, :phases, default_validation_phases())
    timeout = Keyword.get(opts, :timeout, 30_000)

    result =
      with {:ok, ast} <- parse_source_code(source_code),
           {:ok, module_info} <- extract_module_information(ast),
           {:ok, validation_result} <-
             run_validation_phases(module_info, validation_phases, timeout) do
        end_time = System.monotonic_time(:millisecond)
        analysis_duration = end_time - start_time

        final_result =
          validation_result
          |> Map.put(:analysis_duration_ms, analysis_duration)
          |> Map.put(
            :overall_otp_score,
            ValidationSchemas.calculate_overall_score(validation_result)
          )

        Logger.info("OTP validation complete in #{analysis_duration}ms")
        {:ok, final_result}
      else
        {:error, reason} ->
          Logger.warning("OTP validation failed: #{inspect(reason)}")
          {:error, reason}
      end

    result
  end

  @doc """
  Validates OTP behaviors from a file path.
  """
  def validate_file(file_path, opts \\ []) do
    Logger.info("Validating OTP behaviors in file: #{file_path}")

    case File.read(file_path) do
      {:ok, source_code} ->
        validate_otp_behaviors(source_code, opts)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Generates a comprehensive OTP validation report.
  """
  def generate_validation_report(validation_result) do
    report = %{
      summary: generate_summary(validation_result),
      detailed_findings: generate_detailed_findings(validation_result),
      recommendations: generate_recommendations(validation_result),
      compliance_scores: extract_compliance_scores(validation_result),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  @doc """
  Validates OTP compliance against quality thresholds.
  """
  def validate_otp_quality(validation_result, thresholds \\ default_thresholds()) do
    compliance_checks = %{
      genserver_compliant: check_genserver_compliance(validation_result, thresholds),
      supervisor_compliant: check_supervisor_compliance(validation_result, thresholds),
      behavior_compliant: check_behavior_compliance(validation_result, thresholds),
      overall_compliant: validation_result.overall_otp_score >= thresholds.minimum_otp_score
    }

    overall_validation = %{
      passed: Enum.all?(Map.values(compliance_checks)),
      detailed_compliance: compliance_checks,
      overall_score: validation_result.overall_otp_score,
      threshold_score: thresholds.minimum_otp_score
    }

    {:ok, overall_validation}
  end

  # Private helper functions

  defp default_validation_phases do
    [:genserver_validation, :supervisor_analysis, :behavior_compliance, :process_metrics]
  end

  defp parse_source_code(source_code) do
    case Code.string_to_quoted(source_code, warn_on_unnecessary_quotes: false) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {_line, error_description, _token}} ->
        {:error, {:parse_error, error_description}}
    end
  end

  defp extract_module_information(ast) do
    module_info = %{
      ast: ast,
      modules: extract_modules(ast),
      use_statements: extract_use_statements(ast),
      behavior_declarations: extract_behavior_declarations(ast),
      function_definitions: extract_function_definitions(ast)
    }

    {:ok, module_info}
  end

  defp run_validation_phases(module_info, phases, timeout) do
    validation_result = ValidationSchemas.new_validation_result()

    phases
    |> Enum.reduce({:ok, validation_result}, fn
      phase, {:ok, acc_result} ->
        case run_single_validation_phase(phase, module_info, timeout) do
          {:ok, phase_result} ->
            updated_result = merge_phase_result(acc_result, phase, phase_result)
            {:ok, updated_result}

          {:error, reason} ->
            Logger.warning("Validation phase #{phase} failed: #{inspect(reason)}")
            # Continue with other phases even if one fails
            {:ok, acc_result}
        end

      # Handle error case
      {:error, _reason} = error, _phase ->
        error
    end)
  end

  defp run_single_validation_phase(:genserver_validation, module_info, timeout) do
    if has_genserver_usage?(module_info) do
      Task.async(fn -> GenServerValidator.validate_genserver(module_info) end)
      |> Task.await(timeout)
    else
      {:ok, nil}
    end
  end

  defp run_single_validation_phase(:supervisor_analysis, module_info, timeout) do
    if has_supervisor_usage?(module_info) do
      Task.async(fn -> SupervisorAnalyzer.analyze_supervisor(module_info) end)
      |> Task.await(timeout)
    else
      {:ok, nil}
    end
  end

  defp run_single_validation_phase(:behavior_compliance, module_info, timeout) do
    if has_custom_behaviors?(module_info) do
      Task.async(fn -> BehaviorChecker.check_behavior_compliance(module_info) end)
      |> Task.await(timeout)
    else
      {:ok, nil}
    end
  end

  defp run_single_validation_phase(:process_metrics, module_info, timeout) do
    Task.async(fn -> ProcessMetrics.collect_process_metrics(module_info) end)
    |> Task.await(timeout)
  end

  defp run_single_validation_phase(phase, _module_info, _timeout) do
    Logger.warning("Unknown validation phase: #{phase}")
    {:ok, nil}
  end

  defp merge_phase_result(validation_result, :genserver_validation, phase_result) do
    Map.put(validation_result, :genserver, phase_result)
  end

  defp merge_phase_result(validation_result, :supervisor_analysis, phase_result) do
    Map.put(validation_result, :supervisor, phase_result)
  end

  defp merge_phase_result(validation_result, :behavior_compliance, phase_result) do
    Map.put(validation_result, :behaviors, phase_result)
  end

  defp merge_phase_result(validation_result, :process_metrics, phase_result) do
    Map.put(validation_result, :process_metrics, phase_result)
  end

  defp merge_phase_result(validation_result, _phase, _phase_result) do
    validation_result
  end

  # Module detection helpers

  defp extract_modules({:defmodule, _, _} = ast) do
    [extract_module_name(ast)]
  end

  defp extract_modules(ast) when is_list(ast) do
    Enum.flat_map(ast, &extract_modules/1)
  end

  defp extract_modules({_, _, children}) when is_list(children) do
    Enum.flat_map(children, &extract_modules/1)
  end

  defp extract_modules(_), do: []

  defp extract_module_name({:defmodule, _, [{:__aliases__, _, name_parts} | _]}) do
    Module.concat(name_parts)
  end

  defp extract_module_name(_), do: nil

  defp extract_use_statements(ast) do
    find_in_ast(ast, fn
      {:use, _, [{:__aliases__, _, module_parts} | _]} ->
        Module.concat(module_parts)

      _ ->
        nil
    end)
  end

  defp extract_behavior_declarations(ast) do
    find_in_ast(ast, fn
      {:@, _, [{:behaviour, _, [{:__aliases__, _, module_parts}]}]} ->
        Module.concat(module_parts)

      _ ->
        nil
    end)
  end

  defp extract_function_definitions(ast) do
    find_in_ast(ast, fn
      {:def, _, [{name, _, _} | _]} when is_atom(name) -> name
      {:defp, _, [{name, _, _} | _]} when is_atom(name) -> name
      _ -> nil
    end)
  end

  defp find_in_ast(ast, finder_fn) when is_function(finder_fn, 1) do
    find_in_ast(ast, finder_fn, [])
  end

  defp find_in_ast(ast, finder_fn, acc) when is_list(ast) do
    Enum.reduce(ast, acc, fn node, acc -> find_in_ast(node, finder_fn, acc) end)
  end

  defp find_in_ast({_, _, children} = node, finder_fn, acc) when is_list(children) do
    case finder_fn.(node) do
      nil -> find_in_ast(children, finder_fn, acc)
      result -> find_in_ast(children, finder_fn, [result | acc])
    end
  end

  defp find_in_ast(node, finder_fn, acc) do
    case finder_fn.(node) do
      nil -> acc
      result -> [result | acc]
    end
  end

  # Usage detection helpers

  defp has_genserver_usage?(module_info) do
    GenServer in module_info.use_statements or
      Enum.any?(module_info.function_definitions, &genserver_callback?/1)
  end

  defp has_supervisor_usage?(module_info) do
    Supervisor in module_info.use_statements or
      DynamicSupervisor in module_info.use_statements or
      Enum.any?(module_info.function_definitions, &supervisor_callback?/1)
  end

  defp has_custom_behaviors?(module_info) do
    length(module_info.behavior_declarations) > 0
  end

  defp genserver_callback?(function_name) do
    function_name in [:init, :handle_call, :handle_cast, :handle_info, :terminate, :code_change]
  end

  defp supervisor_callback?(function_name) do
    function_name in [:init, :start_link]
  end

  # Report generation helpers

  defp generate_summary(validation_result) do
    %{
      overall_otp_score: validation_result.overall_otp_score,
      genserver_analyzed: not is_nil(validation_result.genserver),
      supervisor_analyzed: not is_nil(validation_result.supervisor),
      behaviors_analyzed: not is_nil(validation_result.behaviors),
      process_metrics_collected: not is_nil(validation_result.process_metrics),
      analysis_duration_ms: validation_result.analysis_duration_ms
    }
  end

  defp generate_detailed_findings(validation_result) do
    %{
      genserver_findings: extract_genserver_findings(validation_result.genserver),
      supervisor_findings: extract_supervisor_findings(validation_result.supervisor),
      behavior_findings: extract_behavior_findings(validation_result.behaviors),
      process_findings: extract_process_findings(validation_result.process_metrics)
    }
  end

  defp generate_recommendations(validation_result) do
    recommendations = []

    recommendations =
      if validation_result.genserver && validation_result.genserver.compliance_score < 80 do
        ["Consider improving GenServer callback implementations" | recommendations]
      else
        recommendations
      end

    recommendations =
      if validation_result.supervisor && not validation_result.supervisor.tree_structure_valid do
        ["Review supervisor tree structure and restart strategies" | recommendations]
      else
        recommendations
      end

    recommendations =
      if validation_result.behaviors && validation_result.behaviors.callback_compliance_score < 70 do
        ["Improve custom behavior callback implementations" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["OTP implementation appears to follow best practices"]
    else
      recommendations
    end
  end

  defp extract_compliance_scores(validation_result) do
    %{
      overall_otp_score: validation_result.overall_otp_score,
      genserver_score: get_in(validation_result, [:genserver, :compliance_score]),
      supervisor_score: get_in(validation_result, [:supervisor, :child_spec_compliance]),
      behavior_score: get_in(validation_result, [:behaviors, :callback_compliance_score]),
      process_efficiency_score:
        get_in(validation_result, [:process_metrics, :memory_efficiency_score])
    }
  end

  defp extract_genserver_findings(nil), do: %{analyzed: false}

  defp extract_genserver_findings(genserver_result) do
    %{
      analyzed: true,
      compliance_score: genserver_result.compliance_score,
      missing_callbacks: genserver_result.missing_callbacks,
      return_value_issues: genserver_result.return_value_issues,
      overall_compliant: genserver_result.overall_otp_compliance
    }
  end

  defp extract_supervisor_findings(nil), do: %{analyzed: false}

  defp extract_supervisor_findings(supervisor_result) do
    %{
      analyzed: true,
      tree_valid: supervisor_result.tree_structure_valid,
      strategy_appropriate: supervisor_result.restart_strategy_appropriate,
      child_count: supervisor_result.child_count,
      issues: supervisor_result.issues
    }
  end

  defp extract_behavior_findings(nil), do: %{analyzed: false}

  defp extract_behavior_findings(behavior_result) do
    %{
      analyzed: true,
      custom_behavior_count: behavior_result.custom_behaviors_count,
      compliance_score: behavior_result.callback_compliance_score,
      missing_callbacks: behavior_result.missing_callbacks,
      issues: behavior_result.issues
    }
  end

  defp extract_process_findings(nil), do: %{analyzed: false}

  defp extract_process_findings(process_result) do
    %{
      analyzed: true,
      process_count: process_result.process_count,
      spawn_rate: process_result.spawn_rate,
      memory_usage_mb: process_result.memory_usage_mb,
      efficiency_score: process_result.memory_efficiency_score
    }
  end

  # Compliance checking helpers

  defp check_genserver_compliance(validation_result, thresholds) do
    case validation_result.genserver do
      # No GenServer to validate
      nil -> true
      genserver -> genserver.compliance_score >= thresholds.minimum_genserver_score
    end
  end

  defp check_supervisor_compliance(validation_result, thresholds) do
    case validation_result.supervisor do
      # No Supervisor to validate
      nil -> true
      supervisor -> supervisor.child_spec_compliance >= thresholds.minimum_supervisor_score
    end
  end

  defp check_behavior_compliance(validation_result, thresholds) do
    case validation_result.behaviors do
      # No custom behaviors to validate
      nil -> true
      behaviors -> behaviors.callback_compliance_score >= thresholds.minimum_behavior_score
    end
  end

  defp default_thresholds do
    %{
      minimum_otp_score: 70,
      minimum_genserver_score: 75,
      minimum_supervisor_score: 80,
      minimum_behavior_score: 70
    }
  end
end
