defmodule SweBench.FunctionalAnalysis.FunctionPurityChecker do
  @moduledoc """
  Analyzes function purity and side effects in functional code.

  Identifies pure vs impure functions, detects hidden side effects,
  analyzes function composability, checks referential transparency,
  and calculates purity percentage for functional programming evaluation.
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
    :os,
    :timer,
    Logger
  ]

  @state_modules [
    Agent,
    GenServer,
    Registry,
    :ets,
    :dets,
    :mnesia
  ]

  @io_operations [
    :puts,
    :inspect,
    :write,
    :read,
    :gets,
    :open,
    :close,
    :print,
    :warn,
    :debug,
    :info,
    :error
  ]

  @doc """
  Analyzes function purity and side effects in source code.

  ## Parameters
    - source_code: Elixir source code as string
    - opts: Analysis options including purity strictness level

  ## Returns
    - {:ok, purity_analysis} - Successful analysis with purity percentages
    - {:error, reason} - Analysis error
  """
  def analyze_function_purity(source_code, _opts \\ []) do
    Logger.info("Starting function purity analysis")

    with {:ok, ast} <- parse_source_code(source_code),
         {:ok, function_classifications} <- identify_pure_vs_impure_functions(ast),
         {:ok, side_effect_analysis} <- detect_hidden_side_effects(ast),
         {:ok, composability_analysis} <-
           analyze_function_composability(ast, function_classifications),
         {:ok, transparency_analysis} <-
           check_referential_transparency(ast, function_classifications),
         {:ok, purity_percentage} <-
           calculate_purity_percentage(
             function_classifications,
             side_effect_analysis,
             composability_analysis,
             transparency_analysis
           ) do
      purity_analysis = %{
        source_code_analyzed: true,
        function_classifications: function_classifications,
        side_effect_analysis: side_effect_analysis,
        composability_analysis: composability_analysis,
        transparency_analysis: transparency_analysis,
        purity_percentage: purity_percentage,
        purity_level: classify_purity_level(purity_percentage),
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Function purity analysis complete: #{purity_percentage}% pure")
      {:ok, purity_analysis}
    else
      {:error, reason} ->
        Logger.warning("Function purity analysis failed: #{inspect(reason)}")
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

  # Task 2.5.4.1: Identify pure vs impure functions
  defp identify_pure_vs_impure_functions(ast) do
    Logger.debug("Identifying pure vs impure functions")

    all_functions = find_function_definitions(ast)

    function_classifications =
      all_functions
      |> Enum.map(fn {name, arity, body} ->
        purity_analysis = analyze_single_function_purity(body, name)

        %{
          function_name: name,
          arity: arity,
          purity_classification: purity_analysis.classification,
          purity_score: purity_analysis.score,
          impurity_reasons: purity_analysis.impurity_reasons,
          side_effect_types: purity_analysis.side_effect_types
        }
      end)

    pure_functions =
      Enum.filter(function_classifications, fn func -> func.purity_classification == :pure end)

    impure_functions =
      Enum.filter(function_classifications, fn func -> func.purity_classification != :pure end)

    classifications = %{
      all_functions: function_classifications,
      pure_functions: pure_functions,
      impure_functions: impure_functions,
      total_function_count: length(all_functions),
      pure_function_count: length(pure_functions),
      impure_function_count: length(impure_functions),
      purity_ratio: calculate_purity_ratio(length(pure_functions), length(all_functions))
    }

    {:ok, classifications}
  end

  defp analyze_single_function_purity(body, _function_name) do
    side_effects = find_side_effects_in_function(body)
    state_operations = find_state_operations_in_function(body)
    io_operations = find_io_operations_in_function(body)

    impurity_reasons = []
    side_effect_types = []

    {impurity_reasons, side_effect_types} =
      if Enum.empty?(side_effects) do
        {impurity_reasons, side_effect_types}
      else
        {["contains_side_effects" | impurity_reasons], [:side_effects | side_effect_types]}
      end

    {impurity_reasons, side_effect_types} =
      if Enum.empty?(state_operations) do
        {impurity_reasons, side_effect_types}
      else
        {["modifies_external_state" | impurity_reasons],
         [:state_modification | side_effect_types]}
      end

    {impurity_reasons, side_effect_types} =
      if Enum.empty?(io_operations) do
        {impurity_reasons, side_effect_types}
      else
        {["performs_io_operations" | impurity_reasons], [:io_operations | side_effect_types]}
      end

    classification =
      if Enum.empty?(impurity_reasons) do
        :pure
      else
        case length(impurity_reasons) do
          1 -> :mostly_pure
          2 -> :impure
          _ -> :highly_impure
        end
      end

    score = calculate_function_purity_score(impurity_reasons, side_effect_types)

    %{
      classification: classification,
      score: score,
      impurity_reasons: impurity_reasons,
      side_effect_types: side_effect_types
    }
  end

  defp find_side_effects_in_function(body) do
    find_in_ast(body, fn
      {{:., _, [module, _function]}, _, _} when module in @side_effect_modules ->
        :side_effect_call

      {module, _, _} when module in @side_effect_modules ->
        :side_effect_call

      _ ->
        nil
    end)
  end

  defp find_state_operations_in_function(body) do
    find_in_ast(body, fn
      {{:., _, [module, function]}, _, _} when module in @state_modules ->
        %{module: module, function: function, type: :state_operation}

      _ ->
        nil
    end)
  end

  defp find_io_operations_in_function(body) do
    find_in_ast(body, fn
      {{:., _, [:IO, function]}, _, _} when function in @io_operations ->
        %{module: :IO, function: function, type: :io_operation}

      {{:., _, [:Logger, function]}, _, _} when function in [:debug, :info, :warn, :error] ->
        %{module: :Logger, function: function, type: :logging_operation}

      _ ->
        nil
    end)
  end

  defp calculate_function_purity_score(impurity_reasons, side_effect_types) do
    base_score = 100

    # Penalty based on types of impurity
    impurity_penalty = length(impurity_reasons) * 25

    # Additional penalty for severe side effects
    severe_penalty =
      side_effect_types
      |> Enum.map(fn type ->
        case type do
          :state_modification -> 15
          :io_operations -> 10
          :side_effects -> 12
          _ -> 5
        end
      end)
      |> Enum.sum()

    total_penalty = impurity_penalty + severe_penalty
    max(0, base_score - total_penalty)
  end

  defp calculate_purity_ratio(pure_count, total_count) when total_count > 0 do
    pure_count / total_count * 100
  end

  defp calculate_purity_ratio(_pure_count, 0), do: 100

  # Task 2.5.4.2: Detect hidden side effects
  defp detect_hidden_side_effects(ast) do
    Logger.debug("Detecting hidden side effects")

    hidden_effects = find_hidden_side_effects(ast)
    global_state_access = find_global_state_access(ast)
    external_dependencies = find_external_dependencies(ast)

    side_effect_analysis = %{
      hidden_effects: hidden_effects,
      hidden_effect_count: length(hidden_effects),
      global_state_access: global_state_access,
      global_access_count: length(global_state_access),
      external_dependencies: external_dependencies,
      external_dependency_count: length(external_dependencies),
      hidden_side_effect_score:
        calculate_hidden_side_effect_score(
          hidden_effects,
          global_state_access,
          external_dependencies
        )
    }

    {:ok, side_effect_analysis}
  end

  defp find_hidden_side_effects(ast) do
    # Look for less obvious side effects
    find_in_ast(ast, fn
      # Process dictionary usage
      {{:., _, [:Process, :put]}, _, _} ->
        %{type: :process_dictionary, operation: :put}

      {{:., _, [:Process, :get]}, _, _} ->
        %{type: :process_dictionary, operation: :get}

      # Node operations
      {{:., _, [:Node, _]}, _, _} ->
        %{type: :node_operation}

      # System operations
      {{:., _, [:System, function]}, _, _} when function in [:cmd, :shell] ->
        %{type: :system_command, function: function}

      # Time-dependent operations
      {{:., _, [:DateTime, :utc_now]}, _, _} ->
        %{type: :time_dependent}

      {{:., _, [:System, :monotonic_time]}, _, _} ->
        %{type: :time_dependent}

      _ ->
        nil
    end)
  end

  defp find_global_state_access(ast) do
    find_in_ast(ast, fn
      # Application environment access
      {{:., _, [:Application, :get_env]}, _, _} ->
        %{type: :application_env, operation: :get}

      {{:., _, [:Application, :put_env]}, _, _} ->
        %{type: :application_env, operation: :put}

      # Module attribute access (can be side-effectful)
      {:@, _, [{attr_name, _, _}]} when is_atom(attr_name) ->
        %{type: :module_attribute, attribute: attr_name}

      _ ->
        nil
    end)
  end

  defp find_external_dependencies(ast) do
    # Find dependencies on external modules that may have side effects
    external_calls =
      find_in_ast(ast, fn
        {{:., _, [module, function]}, _, _} when is_atom(module) and is_atom(function) ->
          if external_module?(module) do
            %{type: :external_call, module: module, function: function}
          else
            nil
          end

        _ ->
          nil
      end)

    # Group by module for analysis
    Enum.group_by(external_calls, & &1.module)
  end

  defp external_module?(module) do
    # Modules that are likely external and potentially side-effectful
    external_modules = [
      # HTTP clients
      :HTTPoison,
      :Hackney,
      :Tesla,
      # Database
      :Ecto,
      :Repo,
      # Web framework
      :Phoenix,
      :Plug,
      # JSON libraries
      :Jason,
      :Poison,
      # Stream processing
      :GenStage,
      :Flow
    ]

    module in external_modules or
      (is_atom(module) and String.starts_with?(Atom.to_string(module), "Elixir."))
  end

  defp calculate_hidden_side_effect_score(hidden_effects, global_access, external_deps) do
    base_score = 100

    # Penalty for hidden side effects
    hidden_penalty = length(hidden_effects) * 12

    # Penalty for global state access
    global_penalty = length(global_access) * 15

    # Penalty for external dependencies (less severe)
    external_penalty = map_size(external_deps) * 8

    total_penalty = hidden_penalty + global_penalty + external_penalty
    max(0, base_score - total_penalty)
  end

  # Task 2.5.4.3: Analyze function composability
  defp analyze_function_composability(ast, function_classifications) do
    Logger.debug("Analyzing function composability")

    pure_functions = function_classifications.pure_functions

    composability_metrics =
      pure_functions
      |> Enum.map(fn func ->
        analyze_single_function_composability(func, ast)
      end)

    composability_analysis = %{
      composable_functions: composability_metrics,
      composable_function_count: length(composability_metrics),
      average_composability_score: calculate_average_composability(composability_metrics),
      composition_patterns: find_composition_patterns(ast),
      composability_score: calculate_overall_composability_score(composability_metrics)
    }

    {:ok, composability_analysis}
  end

  defp analyze_single_function_composability(func, ast) do
    function_body = extract_function_body(ast, func.function_name)

    return_type_consistency = analyze_return_type_consistency(function_body)
    argument_dependency = analyze_argument_dependency(function_body)
    composition_usage = find_function_compositions(function_body, func.function_name)

    %{
      function_name: func.function_name,
      return_type_consistent: return_type_consistency.consistent,
      depends_only_on_arguments: argument_dependency.depends_only_on_args,
      used_in_compositions: composition_usage.used_in_compositions,
      composability_score:
        calculate_function_composability_score(
          return_type_consistency,
          argument_dependency,
          composition_usage
        )
    }
  end

  defp analyze_return_type_consistency(body) do
    # Analyze if function returns consistent types
    return_expressions = find_return_expressions(body)

    return_types =
      return_expressions
      |> Enum.map(&classify_return_type/1)
      |> Enum.uniq()

    %{
      return_expressions: return_expressions,
      return_types: return_types,
      consistent: length(return_types) <= 1,
      type_count: length(return_types)
    }
  end

  defp find_return_expressions(body) do
    # Find expressions that represent function returns
    case body do
      {:__block__, _, statements} when is_list(statements) ->
        [List.last(statements)]

      {:case, _, [_, [do: clauses]]} ->
        Enum.map(clauses, fn
          {:->, _, [_, clause_body]} -> clause_body
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      {:if, _, [_, [do: if_body, else: else_body]]} ->
        [if_body, else_body]

      single_expression ->
        [single_expression]
    end
  end

  defp classify_return_type(expression) do
    cond do
      primitive_type?(expression) -> classify_primitive_type(expression)
      tuple_type?(expression) -> classify_tuple_type(expression)
      true -> :unknown
    end
  end

  defp primitive_type?(expression) do
    is_atom(expression) or is_number(expression) or is_binary(expression) or
      is_list(expression) or is_map(expression)
  end

  defp classify_primitive_type(expression) do
    cond do
      is_atom(expression) -> :atom
      is_number(expression) -> :number
      is_binary(expression) -> :string
      is_list(expression) -> :list
      is_map(expression) -> :map
    end
  end

  defp tuple_type?(expression) do
    case expression do
      {:ok, _} -> true
      {:error, _} -> true
      {_, _} -> true
      _ -> false
    end
  end

  defp classify_tuple_type(expression) do
    case expression do
      {:ok, _} -> :ok_tuple
      {:error, _} -> :error_tuple
      {_, _} -> :tuple
    end
  end

  defp analyze_argument_dependency(body) do
    # Check if function depends only on its arguments (no external state)
    external_references = find_external_references(body)

    %{
      external_references: external_references,
      external_reference_count: length(external_references),
      depends_only_on_args: Enum.empty?(external_references)
    }
  end

  defp find_external_references(body) do
    find_in_ast(body, fn
      # Module attribute access
      {:@, _, [{attr_name, _, _}]} when is_atom(attr_name) -> {:module_attribute, attr_name}
      # Application environment
      {{:., _, [:Application, :get_env]}, _, _} -> :application_env
      # Process dictionary
      {{:., _, [:Process, :get]}, _, _} -> :process_dictionary
      # External module calls that might depend on external state
      {{:., _, [module, _]}, _, _} when module in @state_modules -> {:external_state, module}
      _ -> nil
    end)
  end

  defp find_function_compositions(body, function_name) do
    # Look for patterns where this function is used in composition
    compositions =
      find_in_ast(body, fn
        # Function used in pipeline
        {:|>, _, [_, {^function_name, _, _}]} ->
          :pipeline_composition

        # Function passed as argument to higher-order functions
        {{:., _, [:Enum, _]}, _, args} when is_list(args) ->
          if function_referenced_in_args?(args, function_name) do
            :higher_order_composition
          else
            nil
          end

        _ ->
          nil
      end)

    %{
      compositions: compositions,
      composition_count: length(compositions),
      used_in_compositions: not Enum.empty?(compositions)
    }
  end

  defp function_referenced_in_args?(args, function_name) do
    Enum.any?(args, fn
      {^function_name, _, _} -> true
      # &function_name/arity
      {:&, _, [{:/, _, [{^function_name, _, _}, _]}]} -> true
      _ -> false
    end)
  end

  defp calculate_function_composability_score(
         return_consistency,
         argument_dependency,
         composition_usage
       ) do
    base_score = 100

    # Penalty for inconsistent return types
    consistency_penalty = if return_consistency.consistent, do: 0, else: 20

    # Penalty for external dependencies
    dependency_penalty = if argument_dependency.depends_only_on_args, do: 0, else: 25

    # Bonus for being used in compositions
    composition_bonus = if composition_usage.used_in_compositions, do: 10, else: 0

    final_score = base_score - consistency_penalty - dependency_penalty + composition_bonus
    max(0, min(100, final_score))
  end

  defp find_composition_patterns(ast) do
    find_in_ast(ast, fn
      # Pipeline compositions
      {:|>, _, _} -> :pipeline
      # Function composition with Enum
      {{:., _, [:Enum, :map]}, _, _} -> :enum_map_composition
      {{:., _, [:Enum, :filter]}, _, _} -> :enum_filter_composition
      {{:., _, [:Enum, :reduce]}, _, _} -> :enum_reduce_composition
      # with expressions for composition
      {:with, _, _} -> :with_composition
      _ -> nil
    end)
  end

  defp calculate_average_composability(composability_metrics) do
    if Enum.empty?(composability_metrics) do
      100
    else
      scores = Enum.map(composability_metrics, & &1.composability_score)
      Enum.sum(scores) / length(scores)
    end
  end

  defp calculate_overall_composability_score(composability_metrics) do
    if Enum.empty?(composability_metrics) do
      # No functions to evaluate
      100
    else
      average_score = calculate_average_composability(composability_metrics)

      # Bonus for high percentage of composable functions
      composable_count =
        Enum.count(composability_metrics, fn metric ->
          metric.composability_score >= 80
        end)

      composability_percentage = composable_count / length(composability_metrics) * 100

      percentage_bonus =
        case composability_percentage do
          p when p >= 80 -> 10
          p when p >= 60 -> 5
          _ -> 0
        end

      final_score = average_score + percentage_bonus
      min(100, round(final_score))
    end
  end

  # Task 2.5.4.4: Check referential transparency
  defp check_referential_transparency(ast, function_classifications) do
    Logger.debug("Checking referential transparency")

    pure_functions = function_classifications.pure_functions

    transparency_analysis =
      pure_functions
      |> Enum.map(fn func ->
        analyze_function_transparency(func, ast)
      end)

    analysis = %{
      transparent_functions: transparency_analysis,
      fully_transparent_count: count_fully_transparent(transparency_analysis),
      partially_transparent_count: count_partially_transparent(transparency_analysis),
      transparency_percentage: calculate_transparency_percentage(transparency_analysis),
      transparency_score: calculate_transparency_score(transparency_analysis)
    }

    {:ok, analysis}
  end

  defp analyze_function_transparency(func, ast) do
    function_body = extract_function_body(ast, func.function_name)

    # Check for referential transparency violations
    time_dependencies = find_time_dependencies(function_body)
    random_dependencies = find_random_dependencies(function_body)
    external_state_reads = find_external_state_reads(function_body)

    transparency_violations = time_dependencies ++ random_dependencies ++ external_state_reads

    transparency_level =
      case length(transparency_violations) do
        0 -> :fully_transparent
        n when n <= 2 -> :mostly_transparent
        n when n <= 5 -> :partially_transparent
        _ -> :not_transparent
      end

    %{
      function_name: func.function_name,
      transparency_level: transparency_level,
      transparency_violations: transparency_violations,
      violation_count: length(transparency_violations),
      transparency_score: calculate_individual_transparency_score(transparency_violations)
    }
  end

  defp find_time_dependencies(body) do
    find_in_ast(body, fn
      {{:., _, [:DateTime, :utc_now]}, _, _} -> :datetime_dependency
      {{:., _, [:System, :system_time]}, _, _} -> :system_time_dependency
      {{:., _, [:System, :monotonic_time]}, _, _} -> :monotonic_time_dependency
      _ -> nil
    end)
  end

  defp find_random_dependencies(body) do
    find_in_ast(body, fn
      {{:., _, [:Enum, :random]}, _, _} -> :enum_random
      {{:., _, [:Enum, :take_random]}, _, _} -> :enum_take_random
      {:rand, _, _} -> :rand_module
      _ -> nil
    end)
  end

  defp find_external_state_reads(body) do
    find_in_ast(body, fn
      {{:., _, [:Application, :get_env]}, _, _} -> :application_env_read
      {{:., _, [:Process, :get]}, _, _} -> :process_dictionary_read
      {{:., _, [:System, :get_env]}, _, _} -> :system_env_read
      _ -> nil
    end)
  end

  defp count_fully_transparent(transparency_analysis) do
    Enum.count(transparency_analysis, fn analysis ->
      analysis.transparency_level == :fully_transparent
    end)
  end

  defp count_partially_transparent(transparency_analysis) do
    Enum.count(transparency_analysis, fn analysis ->
      analysis.transparency_level in [:mostly_transparent, :partially_transparent]
    end)
  end

  defp calculate_transparency_percentage(transparency_analysis) do
    if Enum.empty?(transparency_analysis) do
      100
    else
      transparent_count = count_fully_transparent(transparency_analysis)
      transparent_count / length(transparency_analysis) * 100
    end
  end

  defp calculate_individual_transparency_score(violations) do
    base_score = 100

    violation_penalty =
      violations
      |> Enum.map(fn violation ->
        case violation do
          :datetime_dependency -> 15
          :system_time_dependency -> 15
          :enum_random -> 20
          :application_env_read -> 10
          :process_dictionary_read -> 25
          _ -> 8
        end
      end)
      |> Enum.sum()

    max(0, base_score - violation_penalty)
  end

  defp calculate_transparency_score(transparency_analysis) do
    if Enum.empty?(transparency_analysis) do
      100
    else
      scores = Enum.map(transparency_analysis, & &1.transparency_score)
      round(Enum.sum(scores) / length(scores))
    end
  end

  # Task 2.5.4.5: Calculate purity percentage
  defp calculate_purity_percentage(
         function_classifications,
         side_effect_analysis,
         composability_analysis,
         transparency_analysis
       ) do
    # Comprehensive purity calculation combining all dimensions
    weights = %{
      function_purity: 0.35,
      side_effect_absence: 0.25,
      composability: 0.2,
      transparency: 0.2
    }

    function_purity_score = function_classifications.purity_ratio
    side_effect_score = side_effect_analysis.hidden_side_effect_score
    composability_score = composability_analysis.composability_score
    transparency_score = transparency_analysis.transparency_score

    overall_purity =
      function_purity_score * weights.function_purity +
        side_effect_score * weights.side_effect_absence +
        composability_score * weights.composability +
        transparency_score * weights.transparency

    purity_percentage = round(overall_purity)

    {:ok, purity_percentage}
  end

  # Utility functions

  defp find_function_definitions(ast) do
    find_in_ast(ast, fn
      {:def, _, [{name, _, args}, [do: body]]} when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, body}

      {:defp, _, [{name, _, args}, [do: body]]} when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, body}

      _ ->
        nil
    end)
  end

  defp extract_function_body(ast, function_name) do
    find_in_ast(ast, fn
      {:def, _, [{^function_name, _, _}, [do: body]]} -> body
      {:defp, _, [{^function_name, _, _}, [do: body]]} -> body
      _ -> nil
    end)
    |> List.first()
  end

  defp classify_purity_level(purity_percentage) do
    cond do
      purity_percentage >= 95 -> :highly_pure
      purity_percentage >= 85 -> :mostly_pure
      purity_percentage >= 70 -> :moderately_pure
      purity_percentage >= 50 -> :mixed_purity
      true -> :impure
    end
  end

  # AST utility functions

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
  Generates function purity analysis report with recommendations.
  """
  def generate_purity_report(purity_analysis) do
    report = %{
      summary: %{
        purity_percentage: purity_analysis.purity_percentage,
        purity_level: purity_analysis.purity_level,
        pure_function_count: purity_analysis.function_classifications.pure_function_count,
        impure_function_count: purity_analysis.function_classifications.impure_function_count,
        composability_score: purity_analysis.composability_analysis.composability_score
      },
      detailed_analysis: %{
        function_classifications: purity_analysis.function_classifications,
        side_effects: purity_analysis.side_effect_analysis,
        composability: purity_analysis.composability_analysis,
        transparency: purity_analysis.transparency_analysis
      },
      recommendations: generate_purity_recommendations(purity_analysis),
      purity_grade: classify_purity_level(purity_analysis.purity_percentage),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_purity_recommendations(analysis) do
    recommendations = []

    recommendations =
      if analysis.function_classifications.impure_function_count >
           analysis.function_classifications.pure_function_count do
        [
          "Increase proportion of pure functions for better functional programming compliance"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.side_effect_analysis.hidden_effect_count > 3 do
        [
          "Address #{analysis.side_effect_analysis.hidden_effect_count} hidden side effects"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.composability_analysis.composability_score < 70 do
        [
          "Improve function composability - current score: #{analysis.composability_analysis.composability_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.transparency_analysis.transparency_percentage < 80 do
        [
          "Enhance referential transparency - current: #{analysis.transparency_analysis.transparency_percentage}%"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Function purity demonstrates excellent functional programming practices"]
    else
      recommendations
    end
  end

  @doc """
  Validates function purity results against quality thresholds.
  """
  def validate_purity_results(analysis, thresholds \\ default_purity_thresholds()) do
    validation = %{
      purity_acceptable: analysis.purity_percentage >= thresholds.minimum_purity_percentage,
      composability_acceptable:
        analysis.composability_analysis.composability_score >=
          thresholds.minimum_composability_score,
      transparency_acceptable:
        analysis.transparency_analysis.transparency_percentage >=
          thresholds.minimum_transparency_percentage,
      side_effects_acceptable:
        analysis.side_effect_analysis.hidden_effect_count <= thresholds.max_hidden_side_effects
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_purity_validation_issues(validation, analysis)
    }
  end

  defp default_purity_thresholds do
    %{
      minimum_purity_percentage: 80,
      minimum_composability_score: 75,
      minimum_transparency_percentage: 85,
      max_hidden_side_effects: 3
    }
  end

  defp collect_purity_validation_issues(validation, analysis) do
    issues = []

    issues =
      if validation.purity_acceptable do
        issues
      else
        ["Function purity below threshold: #{analysis.purity_percentage}%" | issues]
      end

    issues =
      if validation.composability_acceptable do
        issues
      else
        [
          "Composability score below threshold: #{analysis.composability_analysis.composability_score}"
          | issues
        ]
      end

    issues =
      if validation.transparency_acceptable do
        issues
      else
        [
          "Referential transparency below threshold: #{analysis.transparency_analysis.transparency_percentage}%"
          | issues
        ]
      end

    issues =
      if validation.side_effects_acceptable do
        issues
      else
        [
          "Too many hidden side effects: #{analysis.side_effect_analysis.hidden_effect_count}"
          | issues
        ]
      end

    issues
  end
end
