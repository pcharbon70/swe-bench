defmodule SweBench.PatternAnalysis.OTP.BehaviorChecker do
  @moduledoc """
  Checks behavior compliance for custom and standard OTP behaviors.

  Validates behavior declarations, callback function signatures, optional
  callback implementations, custom behavior definitions, and behavior
  composition patterns.
  """

  require Logger

  alias SweBench.PatternAnalysis.OTP.ValidationSchemas

  @standard_otp_behaviors [
    GenServer,
    Supervisor,
    DynamicSupervisor,
    GenStateMachine,
    Application,
    :gen_server,
    :supervisor,
    :application
  ]

  @doc """
  Checks behavior compliance for a module.

  ## Parameters
    - module_info: Parsed module information containing AST and function definitions

  ## Returns
    - {:ok, behavior_validation()} - Successful compliance check result  
    - {:error, reason} - Compliance check error
  """
  def check_behavior_compliance(module_info) do
    Logger.debug("Starting behavior compliance check")

    validation_result = ValidationSchemas.new_behavior_validation()

    with {:ok, declared_behaviors} <- extract_behavior_declarations(module_info),
         {:ok, implemented_callbacks} <- extract_implemented_callbacks(module_info),
         {:ok, behavior_specs} <- analyze_behavior_specifications(declared_behaviors),
         {:ok, compliance_analysis} <-
           analyze_callback_compliance(behavior_specs, implemented_callbacks),
         {:ok, composition_patterns} <-
           detect_composition_patterns(module_info, declared_behaviors) do
      compliance_score = calculate_behavior_compliance_score(compliance_analysis)
      missing_callbacks = find_missing_callbacks(compliance_analysis)
      custom_behavior_count = count_custom_behaviors(declared_behaviors)

      final_result = %{
        validation_result
        | custom_behaviors_count: custom_behavior_count,
          callback_compliance_score: compliance_score,
          behavior_declarations: declared_behaviors,
          implemented_callbacks: implemented_callbacks,
          missing_callbacks: missing_callbacks,
          optional_callbacks_implemented:
            find_optional_callbacks_implemented(compliance_analysis),
          composition_patterns: composition_patterns,
          issues: collect_behavior_issues(compliance_analysis)
      }

      Logger.debug("Behavior compliance check complete: score #{compliance_score}")
      {:ok, final_result}
    else
      {:error, reason} ->
        Logger.warning("Behavior compliance check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.2.3.1: Detect behavior declarations and implementations
  defp extract_behavior_declarations(module_info) do
    # Extract @behaviour declarations from AST
    behavior_declarations =
      module_info.behavior_declarations
      |> Enum.uniq()

    Logger.debug("Found behavior declarations: #{inspect(behavior_declarations)}")
    {:ok, behavior_declarations}
  end

  defp extract_implemented_callbacks(module_info) do
    # All function definitions are potential callback implementations
    implemented_callbacks =
      module_info.function_definitions
      |> Enum.uniq()

    {:ok, implemented_callbacks}
  end

  # Task 2.2.3.2: Verify callback function signatures
  defp analyze_behavior_specifications(declared_behaviors) do
    behavior_specs =
      declared_behaviors
      |> Enum.map(fn behavior ->
        {behavior, get_behavior_specification(behavior)}
      end)
      |> Enum.into(%{})

    {:ok, behavior_specs}
  end

  defp get_behavior_specification(behavior) when behavior in @standard_otp_behaviors do
    case behavior do
      GenServer ->
        %{
          required_callbacks: [:init],
          optional_callbacks: [
            :handle_call,
            :handle_cast,
            :handle_info,
            :terminate,
            :code_change,
            :format_status
          ],
          callback_specs: %{
            init: {1, [{:ok, :any}, :ignore, {:error, :any}]},
            handle_call: {3, [{:reply, :any, :any}, {:noreply, :any}, {:stop, :any, :any}]},
            handle_cast: {2, [{:noreply, :any}, {:stop, :any, :any}]},
            handle_info: {2, [{:noreply, :any}, {:stop, :any, :any}]},
            terminate: {2, [:ok]},
            code_change: {3, [{:ok, :any}]},
            format_status: {2, [:any]}
          }
        }

      Supervisor ->
        %{
          required_callbacks: [:init],
          optional_callbacks: [],
          callback_specs: %{
            init: {1, [{:ok, :any}, :ignore]}
          }
        }

      DynamicSupervisor ->
        %{
          required_callbacks: [:init],
          optional_callbacks: [],
          callback_specs: %{
            init: {1, [{:ok, :any}, :ignore]}
          }
        }

      Application ->
        %{
          required_callbacks: [:start],
          optional_callbacks: [:stop, :prep_stop, :config_change],
          callback_specs: %{
            start: {2, [{:ok, :any}, {:error, :any}]},
            stop: {1, [:ok]},
            prep_stop: {1, [:any]},
            config_change: {3, [:ok]}
          }
        }

      _ ->
        # Handle atom-based behaviors (like :gen_server)
        get_atom_behavior_spec(behavior)
    end
  end

  defp get_behavior_specification(_custom_behavior) do
    # For custom behaviors, we can't know the specification without inspecting the behavior module
    # This would require loading and introspecting the behavior module
    %{
      required_callbacks: [],
      optional_callbacks: [],
      callback_specs: %{},
      custom: true
    }
  end

  defp get_atom_behavior_spec(:gen_server) do
    get_behavior_specification(GenServer)
  end

  defp get_atom_behavior_spec(:supervisor) do
    get_behavior_specification(Supervisor)
  end

  defp get_atom_behavior_spec(:application) do
    get_behavior_specification(Application)
  end

  defp get_atom_behavior_spec(_),
    do: %{required_callbacks: [], optional_callbacks: [], callback_specs: %{}}

  # Task 2.2.3.3: Check optional callback implementations
  defp analyze_callback_compliance(behavior_specs, implemented_callbacks) do
    compliance_analysis =
      behavior_specs
      |> Enum.map(fn {behavior, spec} ->
        analysis = analyze_single_behavior_compliance(behavior, spec, implemented_callbacks)
        {behavior, analysis}
      end)
      |> Enum.into(%{})

    {:ok, compliance_analysis}
  end

  defp analyze_single_behavior_compliance(behavior, spec, implemented_callbacks) do
    required_implemented =
      spec.required_callbacks
      |> Enum.map(fn callback ->
        {callback, callback in implemented_callbacks}
      end)
      |> Enum.into(%{})

    optional_implemented =
      spec.optional_callbacks
      |> Enum.map(fn callback ->
        {callback, callback in implemented_callbacks}
      end)
      |> Enum.into(%{})

    missing_required =
      spec.required_callbacks
      |> Enum.filter(fn callback -> callback not in implemented_callbacks end)

    implemented_optional =
      spec.optional_callbacks
      |> Enum.filter(fn callback -> callback in implemented_callbacks end)

    compliance_score = calculate_single_behavior_score(required_implemented, optional_implemented)

    %{
      behavior: behavior,
      required_implemented: required_implemented,
      optional_implemented: optional_implemented,
      missing_required: missing_required,
      implemented_optional: implemented_optional,
      compliance_score: compliance_score,
      fully_compliant: Enum.empty?(missing_required),
      spec: spec
    }
  end

  defp calculate_single_behavior_score(required_implemented, optional_implemented) do
    # Required callbacks are worth 80% of the score
    required_count = map_size(required_implemented)

    required_implemented_count =
      required_implemented
      |> Enum.count(fn {_callback, implemented} -> implemented end)

    required_score =
      if required_count > 0 do
        required_implemented_count / required_count * 80
      else
        # No required callbacks means full score for required portion
        80
      end

    # Optional callbacks are worth 20% of the score
    optional_count = map_size(optional_implemented)

    optional_implemented_count =
      optional_implemented
      |> Enum.count(fn {_callback, implemented} -> implemented end)

    optional_score =
      if optional_count > 0 do
        optional_implemented_count / optional_count * 20
      else
        # No optional callbacks means full score for optional portion
        20
      end

    round(required_score + optional_score)
  end

  # Task 2.2.3.4: Validate custom behavior definitions
  defp count_custom_behaviors(declared_behaviors) do
    declared_behaviors
    |> Enum.count(fn behavior -> behavior not in @standard_otp_behaviors end)
  end

  # Task 2.2.3.5: Analyze behavior composition patterns
  defp detect_composition_patterns(module_info, declared_behaviors) do
    patterns = []

    patterns = maybe_add_multiple_behaviors(patterns, declared_behaviors)
    patterns = maybe_add_genserver_composition(patterns, declared_behaviors)
    patterns = maybe_add_use_with_behavior(patterns, module_info, declared_behaviors)
    patterns = maybe_add_supervisor_composition(patterns, declared_behaviors)

    final_patterns =
      if Enum.empty?(patterns) do
        ["single_behavior"]
      else
        patterns
      end

    {:ok, final_patterns}
  end

  defp maybe_add_multiple_behaviors(patterns, declared_behaviors) do
    if length(declared_behaviors) > 1 do
      ["multiple_behaviors" | patterns]
    else
      patterns
    end
  end

  defp maybe_add_genserver_composition(patterns, declared_behaviors) do
    if GenServer in declared_behaviors and length(declared_behaviors) > 1 do
      ["genserver_composition" | patterns]
    else
      patterns
    end
  end

  defp maybe_add_use_with_behavior(patterns, module_info, declared_behaviors) do
    has_use_statements = not Enum.empty?(module_info.use_statements)
    has_behaviors = not Enum.empty?(declared_behaviors)

    if has_use_statements and has_behaviors do
      ["use_with_behavior" | patterns]
    else
      patterns
    end
  end

  defp maybe_add_supervisor_composition(patterns, declared_behaviors) do
    supervisor_behaviors = [Supervisor, DynamicSupervisor]
    has_supervisor = Enum.any?(supervisor_behaviors, &(&1 in declared_behaviors))

    if has_supervisor and length(declared_behaviors) > 1 do
      ["supervisor_composition" | patterns]
    else
      patterns
    end
  end

  # Helper functions for result aggregation

  defp calculate_behavior_compliance_score(compliance_analysis) do
    if map_size(compliance_analysis) == 0 do
      # No behaviors to validate
      100
    else
      scores =
        compliance_analysis
        |> Enum.map(fn {_behavior, analysis} -> analysis.compliance_score end)

      round(Enum.sum(scores) / length(scores))
    end
  end

  defp find_missing_callbacks(compliance_analysis) do
    compliance_analysis
    |> Enum.flat_map(fn {_behavior, analysis} -> analysis.missing_required end)
    |> Enum.uniq()
  end

  defp find_optional_callbacks_implemented(compliance_analysis) do
    compliance_analysis
    |> Enum.flat_map(fn {_behavior, analysis} -> analysis.implemented_optional end)
    |> Enum.uniq()
  end

  defp collect_behavior_issues(compliance_analysis) do
    issues = []

    # Collect issues for each behavior
    behavior_issues =
      compliance_analysis
      |> Enum.flat_map(fn {behavior, analysis} ->
        behavior_specific_issues(behavior, analysis)
      end)

    issues ++ behavior_issues
  end

  defp behavior_specific_issues(behavior, analysis) do
    issues = []

    # Missing required callbacks
    issues =
      if Enum.empty?(analysis.missing_required) do
        issues
      else
        missing_list = Enum.join(analysis.missing_required, ", ")
        ["#{behavior}: Missing required callbacks: #{missing_list}" | issues]
      end

    # Low compliance score
    issues =
      if analysis.compliance_score < 70 do
        ["#{behavior}: Low compliance score (#{analysis.compliance_score}%)" | issues]
      else
        issues
      end

    issues
  end

  @doc """
  Generates detailed recommendations for behavior compliance improvement.
  """
  def generate_recommendations(behavior_validation) do
    recommendations = []

    # Missing callbacks recommendations
    recommendations =
      if Enum.empty?(behavior_validation.missing_callbacks) do
        recommendations
      else
        missing_list = Enum.join(behavior_validation.missing_callbacks, ", ")
        ["Implement missing required callbacks: #{missing_list}" | recommendations]
      end

    # Compliance score recommendations
    recommendations =
      if behavior_validation.callback_compliance_score < 80 do
        ["Improve callback implementations to meet behavior specifications" | recommendations]
      else
        recommendations
      end

    # Custom behavior recommendations
    recommendations =
      if behavior_validation.custom_behaviors_count > 0 do
        [
          "Review custom behavior implementations for proper callback specifications"
          | recommendations
        ]
      else
        recommendations
      end

    # Composition pattern recommendations
    recommendations =
      if "multiple_behaviors" in behavior_validation.composition_patterns do
        [
          "Consider the complexity of implementing multiple behaviors in one module"
          | recommendations
        ]
      else
        recommendations
      end

    # Issue-specific recommendations
    recommendations =
      if Enum.empty?(behavior_validation.issues) do
        recommendations
      else
        ["Address specific behavior compliance issues" | recommendations]
      end

    if recommendations == [] do
      ["Behavior implementations follow OTP specifications correctly"]
    else
      recommendations
    end
  end

  @doc """
  Checks if a module implements any behaviors.
  """
  def implements_behaviors?(module_info) do
    not Enum.empty?(module_info.behavior_declarations)
  end

  @doc """
  Analyzes callback implementation completeness across all declared behaviors.
  """
  def analyze_implementation_completeness(behavior_validation) do
    total_behaviors = length(behavior_validation.behavior_declarations)

    if total_behaviors == 0 do
      %{completeness: 100, status: :no_behaviors}
    else
      %{
        completeness: behavior_validation.callback_compliance_score,
        status: classify_completeness(behavior_validation.callback_compliance_score),
        missing_count: length(behavior_validation.missing_callbacks),
        optional_count: length(behavior_validation.optional_callbacks_implemented)
      }
    end
  end

  defp classify_completeness(score) do
    cond do
      score >= 95 -> :excellent
      score >= 85 -> :good
      score >= 70 -> :acceptable
      score >= 50 -> :poor
      true -> :critical
    end
  end

  @doc """
  Validates callback signatures against behavior specifications.
  """
  def validate_callback_signatures(_module_info, behavior_validation) do
    # This would require more sophisticated AST analysis to extract actual function signatures
    # For now, return a basic validation structure
    %{
      signatures_validated: length(behavior_validation.implemented_callbacks),
      # Placeholder
      signatures_valid: true,
      arity_mismatches: [],
      return_type_issues: []
    }
  end
end
