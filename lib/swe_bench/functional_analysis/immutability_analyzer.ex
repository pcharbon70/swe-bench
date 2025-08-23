defmodule SweBench.FunctionalAnalysis.ImmutabilityAnalyzer do
  @moduledoc """
  Analyzes code for immutability compliance and functional programming patterns.

  Detects variable reassignment attempts, identifies data structure mutations,
  validates proper use of Agent/GenServer for state management, checks for
  side effects in functions, and scores immutability compliance.
  """

  require Logger

  @side_effect_modules [
    IO,
    File,
    Process,
    Agent,
    GenServer,
    ETS,
    :ets,
    :dets,
    System,
    Node,
    :erlang,
    :os
  ]

  @mutable_operation_names [
    :put_in,
    :update_in,
    :get_and_update_in
  ]

  @map_mutation_functions [
    :put,
    :update,
    :delete
  ]

  @list_mutation_functions [
    :replace_at,
    :update_at,
    :delete_at
  ]

  @doc """
  Analyzes source code for immutability compliance and functional patterns.

  ## Parameters
    - source_code: Elixir source code as string
    - opts: Analysis options including strictness level

  ## Returns
    - {:ok, immutability_analysis} - Successful analysis with compliance scores
    - {:error, reason} - Analysis error
  """
  def analyze_immutability(source_code, _opts \\ []) do
    Logger.info("Starting immutability analysis")

    with {:ok, ast} <- parse_source_code(source_code),
         {:ok, variable_analysis} <- detect_variable_reassignments(ast),
         {:ok, mutation_analysis} <- identify_data_structure_mutations(ast),
         {:ok, state_analysis} <- validate_state_management_usage(ast),
         {:ok, side_effect_analysis} <- check_for_side_effects(ast),
         {:ok, compliance_score} <-
           score_immutability_compliance(
             variable_analysis,
             mutation_analysis,
             state_analysis,
             side_effect_analysis
           ) do
      immutability_analysis = %{
        source_code_analyzed: true,
        variable_analysis: variable_analysis,
        mutation_analysis: mutation_analysis,
        state_management_analysis: state_analysis,
        side_effect_analysis: side_effect_analysis,
        compliance_score: compliance_score,
        overall_immutable: compliance_score >= 80,
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Immutability analysis complete: score #{compliance_score}")
      {:ok, immutability_analysis}
    else
      {:error, reason} ->
        Logger.warning("Immutability analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_source_code(source_code) do
    case Code.string_to_quoted(source_code) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {_line, error_description, _token}} ->
        {:error, {:parse_error, error_description}}
    end
  end

  # Task 2.5.1.1: Detect variable reassignment attempts
  defp detect_variable_reassignments(ast) do
    Logger.debug("Detecting variable reassignment patterns")

    reassignments = find_variable_reassignments(ast)
    rebinding_patterns = find_variable_rebinding(ast)

    variable_analysis = %{
      reassignments: reassignments,
      reassignment_count: length(reassignments),
      rebinding_patterns: rebinding_patterns,
      rebinding_count: length(rebinding_patterns),
      variables_analyzed: count_total_variables(ast),
      reassignment_score: calculate_reassignment_score(reassignments, rebinding_patterns)
    }

    {:ok, variable_analysis}
  end

  defp find_variable_reassignments(ast) do
    # Look for variable assignment patterns that suggest mutation
    find_in_ast(ast, fn
      # Pattern: variable = some_operation(variable)
      {:=, _, [{var_name, _, _}, {operation, _, args}]} when is_atom(var_name) and is_list(args) ->
        if variable_used_in_operation?(var_name, args) do
          %{
            type: :reassignment,
            variable: var_name,
            operation: operation,
            context: :function_body
          }
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp variable_used_in_operation?(var_name, args) do
    Enum.any?(args, fn arg ->
      contains_variable?(arg, var_name)
    end)
  end

  defp contains_variable?({var_name, _, _}, target_var) when is_atom(var_name),
    do: var_name == target_var

  defp contains_variable?({_, _, args}, target_var) when is_list(args) do
    Enum.any?(args, &contains_variable?(&1, target_var))
  end

  defp contains_variable?(_, _), do: false

  defp find_variable_rebinding(ast) do
    # Look for variable rebinding within the same scope
    find_in_ast(ast, fn
      {:=, _, [{var_name, _, _}, _]} when is_atom(var_name) ->
        %{
          type: :rebinding,
          variable: var_name,
          context: :scope_rebinding
        }

      _ ->
        nil
    end)
  end

  defp count_total_variables(ast) do
    variables =
      find_in_ast(ast, fn
        {var_name, _, _} when is_atom(var_name) and var_name != :_ -> var_name
        _ -> nil
      end)

    Enum.uniq(variables) |> length()
  end

  defp calculate_reassignment_score(reassignments, rebinding_patterns) do
    base_score = 100

    # Penalty for reassignments
    reassignment_penalty = length(reassignments) * 15

    # Penalty for rebinding (less severe)
    rebinding_penalty = length(rebinding_patterns) * 8

    total_penalty = reassignment_penalty + rebinding_penalty
    max(0, base_score - total_penalty)
  end

  # Task 2.5.1.2: Identify data structure mutations
  defp identify_data_structure_mutations(ast) do
    Logger.debug("Identifying data structure mutation patterns")

    mutations = find_mutation_operations(ast)
    in_place_modifications = find_in_place_modifications(ast)

    mutation_analysis = %{
      mutations: mutations,
      mutation_count: length(mutations),
      in_place_modifications: in_place_modifications,
      in_place_count: length(in_place_modifications),
      mutation_score: calculate_mutation_score(mutations, in_place_modifications)
    }

    {:ok, mutation_analysis}
  end

  defp find_mutation_operations(ast) do
    find_in_ast(ast, fn
      {operation, _, _} when operation in @mutable_operation_names ->
        %{
          type: :mutable_operation,
          operation: operation,
          severity: classify_mutation_severity(operation)
        }

      {{:., _, [:Map, function]}, _, _} when function in @map_mutation_functions ->
        %{
          type: :map_mutation,
          operation: function,
          severity: :medium
        }

      {{:., _, [:List, function]}, _, _} when function in @list_mutation_functions ->
        %{
          type: :list_mutation,
          operation: function,
          severity: :medium
        }

      _ ->
        nil
    end)
  end

  defp find_in_place_modifications(ast) do
    # Look for patterns that suggest in-place modification
    find_in_ast(ast, fn
      # Pattern: Map.put(map, key, Map.get(map, key) + 1) - suggests mutation intent
      {{:., _, [:Map, :put]}, _, [map_var, _key, {operation, _, args}]} ->
        if contains_variable?(args, extract_var_name(map_var)) do
          %{
            type: :in_place_modification,
            target: extract_var_name(map_var),
            operation: operation
          }
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp extract_var_name({var_name, _, _}) when is_atom(var_name), do: var_name
  defp extract_var_name(_), do: nil

  defp classify_mutation_severity(operation) do
    case operation do
      op when op in [:put_in, :update_in, :get_and_update_in] -> :high
      _ -> :low
    end
  end

  defp calculate_mutation_score(mutations, in_place_modifications) do
    base_score = 100

    # Penalty based on mutation severity
    mutation_penalty =
      mutations
      |> Enum.map(fn mutation ->
        case mutation.severity do
          :high -> 20
          :medium -> 15
          :low -> 10
        end
      end)
      |> Enum.sum()

    # Penalty for in-place modifications
    in_place_penalty = length(in_place_modifications) * 12

    total_penalty = mutation_penalty + in_place_penalty
    max(0, base_score - total_penalty)
  end

  # Task 2.5.1.3: Validate proper use of Agent/GenServer for state
  defp validate_state_management_usage(ast) do
    Logger.debug("Validating state management patterns")

    agent_usage = analyze_agent_usage(ast)
    genserver_usage = analyze_genserver_usage(ast)
    state_patterns = analyze_state_patterns(ast)

    state_analysis = %{
      agent_usage: agent_usage,
      genserver_usage: genserver_usage,
      state_patterns: state_patterns,
      proper_state_management: assess_state_management_quality(agent_usage, genserver_usage),
      state_management_score:
        calculate_state_management_score(agent_usage, genserver_usage, state_patterns)
    }

    {:ok, state_analysis}
  end

  defp analyze_agent_usage(ast) do
    agent_calls =
      find_in_ast(ast, fn
        {:Agent, _, _} -> :agent_reference
        {{:., _, [:Agent, function]}, _, _} when is_atom(function) -> {:agent_call, function}
        _ -> nil
      end)

    proper_agent_usage =
      agent_calls
      |> Enum.filter(fn
        {:agent_call, func} -> func in [:start_link, :get, :update, :get_and_update]
        _ -> false
      end)

    %{
      total_agent_calls: length(agent_calls),
      proper_agent_calls: length(proper_agent_usage),
      agent_functions_used: extract_agent_functions(agent_calls),
      proper_usage_percentage:
        calculate_usage_percentage(length(proper_agent_usage), length(agent_calls))
    }
  end

  defp analyze_genserver_usage(ast) do
    genserver_calls =
      find_in_ast(ast, fn
        {:GenServer, _, _} ->
          :genserver_reference

        {{:., _, [:GenServer, function]}, _, _} when is_atom(function) ->
          {:genserver_call, function}

        _ ->
          nil
      end)

    proper_genserver_usage =
      genserver_calls
      |> Enum.filter(fn
        {:genserver_call, func} -> func in [:start_link, :call, :cast, :stop]
        _ -> false
      end)

    %{
      total_genserver_calls: length(genserver_calls),
      proper_genserver_calls: length(proper_genserver_usage),
      genserver_functions_used: extract_genserver_functions(genserver_calls),
      proper_usage_percentage:
        calculate_usage_percentage(length(proper_genserver_usage), length(genserver_calls))
    }
  end

  defp analyze_state_patterns(ast) do
    # Look for functional state patterns
    functional_patterns =
      find_in_ast(ast, fn
        # Pattern: |> update_state(fn state -> ... end)
        {:|>, _, [_, {{:., _, [_, :update_state]}, _, [_]}]} -> :functional_state_update
        # Pattern: Map.put(state, key, value) instead of mutation
        {{:., _, [:Map, :put]}, _, _} -> :immutable_map_update
        # Pattern: [new_item | existing_list] instead of list mutation
        {:|, _, [_, _]} -> :immutable_list_prepend
        _ -> nil
      end)

    %{
      functional_patterns: functional_patterns,
      pattern_count: length(functional_patterns),
      pattern_types: Enum.frequencies(functional_patterns)
    }
  end

  defp extract_agent_functions(agent_calls) do
    agent_calls
    |> Enum.map(fn
      {:agent_call, func} -> func
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_genserver_functions(genserver_calls) do
    genserver_calls
    |> Enum.map(fn
      {:genserver_call, func} -> func
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp calculate_usage_percentage(proper_count, total_count) when total_count > 0 do
    proper_count / total_count * 100
  end

  defp calculate_usage_percentage(_proper_count, 0), do: 100

  defp assess_state_management_quality(agent_usage, genserver_usage) do
    agent_quality = agent_usage.proper_usage_percentage
    genserver_quality = genserver_usage.proper_usage_percentage

    # If no state management is used, that's also acceptable for functional code
    total_state_calls = agent_usage.total_agent_calls + genserver_usage.total_genserver_calls

    if total_state_calls == 0 do
      # Acceptable for pure functional code
      :no_state_management
    else
      average_quality = (agent_quality + genserver_quality) / 2

      cond do
        average_quality >= 90 -> :excellent
        average_quality >= 75 -> :good
        average_quality >= 60 -> :acceptable
        true -> :poor
      end
    end
  end

  defp calculate_state_management_score(agent_usage, genserver_usage, state_patterns) do
    base_score = 100

    # Penalize improper state management usage
    agent_penalty = (100 - agent_usage.proper_usage_percentage) * 0.1
    genserver_penalty = (100 - genserver_usage.proper_usage_percentage) * 0.1

    # Bonus for functional state patterns
    pattern_bonus = min(20, state_patterns.pattern_count * 3)

    final_score = base_score - agent_penalty - genserver_penalty + pattern_bonus
    max(0, min(100, round(final_score)))
  end

  # Task 2.5.1.4: Check for side effects in functions
  defp check_for_side_effects(ast) do
    Logger.debug("Checking for side effects in functions")

    functions_with_side_effects = find_functions_with_side_effects(ast)
    io_operations = find_io_operations(ast)
    process_operations = find_process_operations(ast)

    side_effect_analysis = %{
      functions_with_side_effects: functions_with_side_effects,
      side_effect_count: length(functions_with_side_effects),
      io_operations: io_operations,
      io_operation_count: length(io_operations),
      process_operations: process_operations,
      process_operation_count: length(process_operations),
      side_effect_score:
        calculate_side_effect_score(
          functions_with_side_effects,
          io_operations,
          process_operations
        )
    }

    {:ok, side_effect_analysis}
  end

  defp find_functions_with_side_effects(ast) do
    functions = find_function_definitions(ast)

    Enum.filter(functions, fn {_function_name, _arity, function_body} ->
      function_has_side_effects?(function_body)
    end)
    |> Enum.map(fn {name, arity, _body} ->
      %{
        function_name: name,
        arity: arity,
        side_effect_types: identify_side_effect_types(ast, name)
      }
    end)
  end

  defp function_has_side_effects?(function_body) do
    side_effect_calls =
      find_in_ast(function_body, fn
        {{:., _, [module, _function]}, _, _} when module in @side_effect_modules -> :side_effect
        {module, _, _} when module in @side_effect_modules -> :side_effect
        _ -> nil
      end)

    not Enum.empty?(side_effect_calls)
  end

  defp identify_side_effect_types(ast, function_name) do
    # Find the specific function and analyze its side effects
    function_body = extract_function_body(ast, function_name)

    if function_body do
      side_effects =
        find_in_ast(function_body, fn
          {{:., _, [:IO, _]}, _, _} -> :io_operation
          {{:., _, [:File, _]}, _, _} -> :file_operation
          {{:., _, [:Process, _]}, _, _} -> :process_operation
          {{:., _, [:Agent, _]}, _, _} -> :agent_operation
          {{:., _, [:GenServer, _]}, _, _} -> :genserver_operation
          _ -> nil
        end)

      Enum.uniq(side_effects)
    else
      []
    end
  end

  defp extract_function_body(ast, function_name) do
    find_in_ast(ast, fn
      {:def, _, [{^function_name, _, _}, [do: body]]} -> body
      {:defp, _, [{^function_name, _, _}, [do: body]]} -> body
      _ -> nil
    end)
    |> List.first()
  end

  defp find_io_operations(ast) do
    find_in_ast(ast, fn
      {{:., _, [:IO, function]}, _, _} when is_atom(function) ->
        %{type: :io_operation, function: function}

      _ ->
        nil
    end)
  end

  defp find_process_operations(ast) do
    find_in_ast(ast, fn
      {{:., _, [:Process, function]}, _, _} when is_atom(function) ->
        %{type: :process_operation, function: function}

      _ ->
        nil
    end)
  end

  defp calculate_side_effect_score(functions_with_side_effects, io_operations, process_operations) do
    base_score = 100

    # Penalty for functions with side effects
    function_penalty = length(functions_with_side_effects) * 12

    # Penalty for specific operation types
    io_penalty = length(io_operations) * 8
    process_penalty = length(process_operations) * 10

    total_penalty = function_penalty + io_penalty + process_penalty
    max(0, base_score - total_penalty)
  end

  # Task 2.5.1.5: Score immutability compliance
  defp score_immutability_compliance(
         variable_analysis,
         mutation_analysis,
         state_analysis,
         side_effect_analysis
       ) do
    # Weighted scoring across all immutability dimensions
    weights = %{
      variable_reassignment: 0.3,
      data_mutations: 0.25,
      state_management: 0.25,
      side_effects: 0.2
    }

    weighted_score =
      variable_analysis.reassignment_score * weights.variable_reassignment +
        mutation_analysis.mutation_score * weights.data_mutations +
        state_analysis.state_management_score * weights.state_management +
        side_effect_analysis.side_effect_score * weights.side_effects

    compliance_score = round(weighted_score)

    {:ok, compliance_score}
  end

  # Utility functions

  defp find_function_definitions(ast) do
    find_in_ast(ast, fn
      {:def, _, [{name, _, args} | _]} when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, ast}

      {:defp, _, [{name, _, args} | _]} when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, ast}

      _ ->
        nil
    end)
  end

  defp find_in_ast(ast, finder_fn, acc \\ [])

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

  @doc """
  Generates immutability analysis report with recommendations.
  """
  def generate_immutability_report(immutability_analysis) do
    report = %{
      summary: %{
        compliance_score: immutability_analysis.compliance_score,
        overall_immutable: immutability_analysis.overall_immutable,
        variable_reassignments: immutability_analysis.variable_analysis.reassignment_count,
        data_mutations: immutability_analysis.mutation_analysis.mutation_count,
        functions_with_side_effects: immutability_analysis.side_effect_analysis.side_effect_count
      },
      detailed_analysis: %{
        variable_analysis: immutability_analysis.variable_analysis,
        mutation_analysis: immutability_analysis.mutation_analysis,
        state_management: immutability_analysis.state_management_analysis,
        side_effects: immutability_analysis.side_effect_analysis
      },
      recommendations: generate_immutability_recommendations(immutability_analysis),
      compliance_grade: classify_immutability_compliance(immutability_analysis.compliance_score),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_immutability_recommendations(analysis) do
    recommendations = []

    recommendations =
      if analysis.variable_analysis.reassignment_count > 0 do
        [
          "Avoid variable reassignments - use pattern matching and function composition instead"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.mutation_analysis.mutation_count > 0 do
        ["Replace data structure mutations with immutable operations" | recommendations]
      else
        recommendations
      end

    recommendations =
      if analysis.side_effect_analysis.side_effect_count > 3 do
        [
          "Minimize side effects - consider functional alternatives or isolate effects"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.state_management_analysis.proper_state_management == :poor do
        ["Improve state management patterns using proper Agent/GenServer usage" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["Code demonstrates excellent immutability and functional programming practices"]
    else
      recommendations
    end
  end

  defp classify_immutability_compliance(score) do
    cond do
      score >= 90 -> :excellent
      score >= 80 -> :good
      score >= 70 -> :acceptable
      score >= 60 -> :needs_improvement
      true -> :poor
    end
  end

  @doc """
  Validates immutability analysis results against quality thresholds.
  """
  def validate_immutability_results(analysis, thresholds \\ default_immutability_thresholds()) do
    validation = %{
      score_acceptable: analysis.compliance_score >= thresholds.minimum_compliance_score,
      reassignments_acceptable:
        analysis.variable_analysis.reassignment_count <= thresholds.max_reassignments,
      mutations_acceptable: analysis.mutation_analysis.mutation_count <= thresholds.max_mutations,
      side_effects_acceptable:
        analysis.side_effect_analysis.side_effect_count <= thresholds.max_side_effects
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_immutability_validation_issues(validation, analysis)
    }
  end

  defp default_immutability_thresholds do
    %{
      minimum_compliance_score: 75,
      max_reassignments: 2,
      max_mutations: 1,
      max_side_effects: 5
    }
  end

  defp collect_immutability_validation_issues(validation, analysis) do
    issues = []

    issues =
      if validation.score_acceptable do
        issues
      else
        ["Immutability compliance score below threshold: #{analysis.compliance_score}" | issues]
      end

    issues =
      if validation.reassignments_acceptable do
        issues
      else
        [
          "Too many variable reassignments: #{analysis.variable_analysis.reassignment_count}"
          | issues
        ]
      end

    issues =
      if validation.mutations_acceptable do
        issues
      else
        [
          "Data structure mutations detected: #{analysis.mutation_analysis.mutation_count}"
          | issues
        ]
      end

    issues =
      if validation.side_effects_acceptable do
        issues
      else
        ["Excessive side effects: #{analysis.side_effect_analysis.side_effect_count}" | issues]
      end

    issues
  end
end
