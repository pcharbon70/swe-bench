defmodule SweBench.FunctionalAnalysis.RecursionAnalyzer do
  @moduledoc """
  Analyzes recursion patterns and appropriateness in functional code.

  Detects recursive function implementations, identifies tail recursion
  optimization opportunities, compares with iteration alternatives,
  analyzes recursion termination conditions, and scores recursion
  appropriateness for functional programming evaluation.
  """

  require Logger

  @iteration_function_names [
    :map,
    :filter,
    :reduce,
    :each
  ]

  @stream_function_names [
    :map,
    :filter,
    :reduce
  ]

  @doc """
  Analyzes recursion patterns and their appropriateness in source code.

  ## Parameters
    - source_code: Elixir source code as string
    - opts: Analysis options including recursion preferences

  ## Returns
    - {:ok, recursion_analysis} - Successful analysis with appropriateness scores
    - {:error, reason} - Analysis error
  """
  def analyze_recursion_patterns(source_code, _opts \\ []) do
    Logger.info("Starting recursion pattern analysis")

    with {:ok, ast} <- parse_source_code(source_code),
         {:ok, recursive_functions} <- detect_recursive_implementations(ast),
         {:ok, tail_recursion_analysis} <-
           identify_tail_recursion_optimization(recursive_functions, ast),
         {:ok, iteration_comparison} <- compare_with_iteration_alternatives(ast),
         {:ok, termination_analysis} <- analyze_termination_conditions(recursive_functions, ast),
         {:ok, appropriateness_score} <-
           score_recursion_appropriateness(
             recursive_functions,
             tail_recursion_analysis,
             iteration_comparison,
             termination_analysis
           ) do
      recursion_analysis = %{
        source_code_analyzed: true,
        recursive_functions: recursive_functions,
        tail_recursion_analysis: tail_recursion_analysis,
        iteration_comparison: iteration_comparison,
        termination_analysis: termination_analysis,
        appropriateness_score: appropriateness_score,
        recursion_level: classify_recursion_level(recursive_functions, appropriateness_score),
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Recursion analysis complete: score #{appropriateness_score}")
      {:ok, recursion_analysis}
    else
      {:error, reason} ->
        Logger.warning("Recursion analysis failed: #{inspect(reason)}")
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

  # Task 2.5.3.1: Detect recursive function implementations
  defp detect_recursive_implementations(ast) do
    Logger.debug("Detecting recursive function implementations")

    all_functions = find_function_definitions(ast)

    recursive_functions =
      all_functions
      |> Enum.filter(fn {name, _arity, body} ->
        function_calls_itself?(body, name)
      end)
      |> Enum.map(fn {name, arity, body} ->
        %{
          function_name: name,
          arity: arity,
          recursion_type: classify_recursion_type(body, name),
          recursive_call_count: count_recursive_calls(body, name),
          has_base_case: has_base_case?(body, name)
        }
      end)

    analysis = %{
      recursive_functions: recursive_functions,
      recursive_function_count: length(recursive_functions),
      total_functions: length(all_functions),
      recursion_percentage:
        calculate_recursion_percentage(length(recursive_functions), length(all_functions))
    }

    {:ok, analysis}
  end

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

  defp function_calls_itself?(body, function_name) do
    recursive_calls =
      find_in_ast(body, fn
        {^function_name, _, _} -> :recursive_call
        _ -> nil
      end)

    not Enum.empty?(recursive_calls)
  end

  defp classify_recursion_type(body, function_name) do
    # Check if it's tail recursive by analyzing call position
    tail_recursive = tail_recursive?(body, function_name)

    # Check if it uses accumulator pattern
    has_accumulator = has_accumulator_pattern?(body)

    cond do
      tail_recursive and has_accumulator -> :tail_recursive_with_accumulator
      tail_recursive -> :tail_recursive
      has_accumulator -> :recursive_with_accumulator
      true -> :standard_recursive
    end
  end

  defp tail_recursive?(body, function_name) do
    # Check if recursive calls are in tail position
    tail_expressions = find_tail_expressions(body)

    Enum.any?(tail_expressions, fn expr ->
      case expr do
        {^function_name, _, _} -> true
        _ -> false
      end
    end)
  end

  defp find_tail_expressions(body) do
    # Find expressions that are in tail position
    case body do
      {:__block__, _, statements} when is_list(statements) ->
        [List.last(statements)]

      {:case, _, [_, [do: clauses]]} ->
        Enum.flat_map(clauses, fn
          {:->, _, [_, clause_body]} -> find_tail_expressions(clause_body)
          _ -> []
        end)

      {:if, _, [_, [do: if_body, else: else_body]]} ->
        find_tail_expressions(if_body) ++ find_tail_expressions(else_body)

      single_expression ->
        [single_expression]
    end
  end

  defp has_accumulator_pattern?(body) do
    # Look for accumulator variables passed through recursive calls
    find_in_ast(body, fn
      {_, _, args} when is_list(args) ->
        # Check if arguments suggest accumulator pattern
        length(args) > 1 and accumulator_variable_present?(args)

      _ ->
        nil
    end)
    |> Enum.any?()
  end

  defp accumulator_variable_present?(args) do
    # Look for variable names that suggest accumulators
    Enum.any?(args, &accumulator_variable?/1)
  end

  defp accumulator_variable?({var_name, _, _}) when is_atom(var_name) do
    var_name in [:acc, :accumulator, :result, :collected]
  end

  defp accumulator_variable?(_), do: false

  defp count_recursive_calls(body, function_name) do
    recursive_calls =
      find_in_ast(body, fn
        {^function_name, _, _} -> :recursive_call
        _ -> nil
      end)

    length(recursive_calls)
  end

  defp has_base_case?(body, function_name) do
    # Check if function has non-recursive clauses (base cases)
    non_recursive_paths =
      find_in_ast(body, fn
        {:case, _, [_, [do: clauses]]} ->
          non_recursive_clauses =
            Enum.filter(clauses, fn
              {:->, _, [_, clause_body]} ->
                not function_calls_itself?(clause_body, function_name)

              _ ->
                false
            end)

          if Enum.empty?(non_recursive_clauses), do: nil, else: :has_base_case

        # Pattern matching in function heads also provides base cases
        expr when not is_tuple(expr) ->
          :potential_base_case

        _ ->
          nil
      end)

    not Enum.empty?(non_recursive_paths)
  end

  defp calculate_recursion_percentage(recursive_count, total_count) when total_count > 0 do
    recursive_count / total_count * 100
  end

  defp calculate_recursion_percentage(_recursive_count, 0), do: 0

  # Task 2.5.3.2: Identify tail recursion optimization
  defp identify_tail_recursion_optimization(recursive_functions, ast) do
    Logger.debug("Identifying tail recursion optimization opportunities")

    tail_recursive_functions =
      recursive_functions.recursive_functions
      |> Enum.filter(fn func ->
        func.recursion_type in [:tail_recursive, :tail_recursive_with_accumulator]
      end)

    optimization_opportunities =
      recursive_functions.recursive_functions
      |> Enum.filter(fn func ->
        func.recursion_type == :standard_recursive and
          can_be_tail_optimized?(func, ast)
      end)

    tail_analysis = %{
      tail_recursive_functions: tail_recursive_functions,
      tail_recursive_count: length(tail_recursive_functions),
      optimization_opportunities: optimization_opportunities,
      optimization_opportunity_count: length(optimization_opportunities),
      tail_recursion_percentage:
        calculate_tail_recursion_percentage(
          tail_recursive_functions,
          recursive_functions.recursive_functions
        ),
      tail_optimization_score:
        calculate_tail_optimization_score(tail_recursive_functions, optimization_opportunities)
    }

    {:ok, tail_analysis}
  end

  defp can_be_tail_optimized?(recursive_func, ast) do
    # Analyze if the function can be converted to tail recursion
    function_body = extract_function_body(ast, recursive_func.function_name)

    if function_body do
      # Check if recursive calls are not in tail position but could be moved there
      non_tail_calls = find_non_tail_recursive_calls(function_body, recursive_func.function_name)

      # If there are non-tail calls, check if they're in simple arithmetic operations
      Enum.any?(non_tail_calls, &simple_arithmetic_context?/1)
    else
      false
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

  defp find_non_tail_recursive_calls(body, function_name) do
    find_in_ast(body, fn
      # Look for recursive calls that are not in tail position
      {:+, _, [left, {^function_name, _, _}]} -> {:arithmetic_context, :addition, left}
      {:*, _, [left, {^function_name, _, _}]} -> {:arithmetic_context, :multiplication, left}
      {:-, _, [left, {^function_name, _, _}]} -> {:arithmetic_context, :subtraction, left}
      _ -> nil
    end)
  end

  defp simple_arithmetic_context?({:arithmetic_context, operation, _operand}) do
    # These can often be converted to accumulator style
    operation in [:addition, :multiplication]
  end

  defp simple_arithmetic_context?(_), do: false

  defp calculate_tail_recursion_percentage(tail_recursive_functions, all_recursive_functions) do
    total_recursive = length(all_recursive_functions)

    if total_recursive > 0 do
      length(tail_recursive_functions) / total_recursive * 100
    else
      # No recursion means no tail recursion issues
      100
    end
  end

  defp calculate_tail_optimization_score(tail_recursive_functions, optimization_opportunities) do
    base_score = 100

    # Bonus for existing tail recursion
    tail_recursive_count = length(tail_recursive_functions)
    tail_bonus = min(30, tail_recursive_count * 10)

    # Penalty for missed optimization opportunities
    missed_opportunities = length(optimization_opportunities)
    optimization_penalty = missed_opportunities * 15

    final_score = base_score + tail_bonus - optimization_penalty
    max(0, min(100, final_score))
  end

  # Task 2.5.3.3: Compare with iteration alternatives
  defp compare_with_iteration_alternatives(ast) do
    Logger.debug("Comparing recursion with iteration alternatives")

    recursive_functions = find_recursive_functions_in_ast(ast)
    iteration_usage = find_iteration_usage(ast)

    comparison_analysis =
      recursive_functions
      |> Enum.map(fn func ->
        alternative_analysis = analyze_iteration_alternative(func, ast)

        %{
          function_name: func.function_name,
          recursion_type: func.recursion_type,
          iteration_alternative: alternative_analysis.suggested_alternative,
          appropriateness: alternative_analysis.recursion_appropriateness,
          performance_consideration: alternative_analysis.performance_impact
        }
      end)

    comparison = %{
      recursive_vs_iterative: comparison_analysis,
      total_recursive_functions: length(recursive_functions),
      iteration_functions_used: length(iteration_usage),
      iteration_usage_score:
        calculate_iteration_usage_score(iteration_usage, recursive_functions),
      balance_score: calculate_recursion_iteration_balance(recursive_functions, iteration_usage)
    }

    {:ok, comparison}
  end

  defp find_recursive_functions_in_ast(ast) do
    all_functions = find_function_definitions(ast)

    Enum.filter(all_functions, fn {name, _arity, body} ->
      function_calls_itself?(body, name)
    end)
    |> Enum.map(fn {name, arity, body} ->
      %{
        function_name: name,
        arity: arity,
        recursion_type: classify_recursion_type(body, name)
      }
    end)
  end

  defp find_iteration_usage(ast) do
    find_in_ast(ast, fn
      {{:., _, [:Enum, function]}, _, _} when function in @iteration_function_names ->
        {:enum_function, function}

      {{:., _, [:Stream, function]}, _, _} when function in @stream_function_names ->
        {:stream_function, function}

      {:for, _, _} ->
        :comprehension

      _ ->
        nil
    end)
  end

  defp analyze_iteration_alternative(recursive_func, ast) do
    function_body = extract_function_body(ast, recursive_func.function_name)

    # Analyze what the recursive function does to suggest alternatives
    function_purpose = analyze_function_purpose(function_body)

    suggested_alternative =
      suggest_iteration_alternative(function_purpose, recursive_func.recursion_type)

    recursion_appropriateness =
      assess_recursion_appropriateness(function_purpose, recursive_func.recursion_type)

    performance_impact =
      assess_performance_impact(recursive_func.recursion_type, suggested_alternative)

    %{
      suggested_alternative: suggested_alternative,
      recursion_appropriateness: recursion_appropriateness,
      performance_impact: performance_impact
    }
  end

  defp analyze_function_purpose(body) do
    # Analyze what the function does to determine if recursion is appropriate
    cond do
      contains_list_processing?(body) -> :list_processing
      contains_tree_traversal?(body) -> :tree_traversal
      contains_accumulation?(body) -> :accumulation
      contains_transformation?(body) -> :transformation
      true -> :unknown
    end
  end

  defp contains_list_processing?(body) do
    find_in_ast(body, fn
      # List construction [head | tail]
      {:|, _, _} -> :list_operation
      {:hd, _, _} -> :list_operation
      {:tl, _, _} -> :list_operation
      _ -> nil
    end)
    |> Enum.any?()
  end

  defp contains_tree_traversal?(body) do
    # Look for patterns that suggest tree or nested structure traversal
    find_in_ast(body, fn
      # Accessing nested map/tuple elements
      {{:., _, [:Map, :get]}, _, _} -> :map_traversal
      {:elem, _, _} -> :tuple_traversal
      _ -> nil
    end)
    |> Enum.any?()
  end

  defp contains_accumulation?(body) do
    # Look for accumulator patterns
    find_in_ast(body, fn
      {var_name, _, _} when var_name in [:acc, :accumulator, :result] -> :accumulator
      _ -> nil
    end)
    |> Enum.any?()
  end

  defp contains_transformation?(body) do
    # Look for data transformation patterns
    find_in_ast(body, fn
      {{:., _, [:Map, :put]}, _, _} -> :transformation
      {{:., _, [:Map, :update]}, _, _} -> :transformation
      _ -> nil
    end)
    |> Enum.any?()
  end

  defp suggest_iteration_alternative(function_purpose, recursion_type) do
    case {function_purpose, recursion_type} do
      {:list_processing, _} -> :enum_reduce_or_map
      {:accumulation, :standard_recursive} -> :enum_reduce_with_accumulator
      {:transformation, _} -> :enum_map_or_transform
      # Recursion is often best for trees
      {:tree_traversal, _} -> :recursion_appropriate
      _ -> :enum_functions_general
    end
  end

  defp assess_recursion_appropriateness(function_purpose, recursion_type) do
    case function_purpose do
      :tree_traversal ->
        :highly_appropriate

      :accumulation when recursion_type in [:tail_recursive, :tail_recursive_with_accumulator] ->
        :appropriate

      :list_processing
      when recursion_type in [:tail_recursive, :tail_recursive_with_accumulator] ->
        :somewhat_appropriate

      :transformation ->
        :iteration_preferred

      _ ->
        :neutral
    end
  end

  defp assess_performance_impact(recursion_type, suggested_alternative) do
    case {recursion_type, suggested_alternative} do
      {:tail_recursive_with_accumulator, _} -> :optimal
      {:tail_recursive, _} -> :good
      {:standard_recursive, :enum_reduce_or_map} -> :iteration_faster
      {:standard_recursive, :enum_reduce_with_accumulator} -> :iteration_much_faster
      _ -> :neutral
    end
  end

  defp calculate_iteration_usage_score(iteration_usage, recursive_functions) do
    iteration_count = length(iteration_usage)
    recursive_count = length(recursive_functions)

    total_operations = iteration_count + recursive_count

    if total_operations > 0 do
      # Score based on appropriate balance
      iteration_ratio = iteration_count / total_operations

      case iteration_ratio do
        # High iteration usage is good
        ratio when ratio >= 0.8 -> 100
        ratio when ratio >= 0.6 -> 90
        ratio when ratio >= 0.4 -> 80
        ratio when ratio >= 0.2 -> 70
        # Too much recursion for simple operations
        _ -> 60
      end
    else
      # No operations to evaluate
      100
    end
  end

  defp calculate_recursion_iteration_balance(recursive_functions, iteration_usage) do
    # Score based on whether recursion and iteration are used appropriately
    appropriate_recursion =
      recursive_functions
      |> Enum.count(fn func ->
        func.recursion_type in [:tail_recursive, :tail_recursive_with_accumulator]
      end)

    total_recursive = length(recursive_functions)
    total_iteration = length(iteration_usage)

    # Good balance considers both appropriate recursion and iteration usage
    recursion_quality =
      if total_recursive > 0 do
        appropriate_recursion / total_recursive * 100
      else
        100
      end

    iteration_presence = if total_iteration > 0, do: 100, else: 80

    # Weighted balance score
    balance_score = recursion_quality * 0.6 + iteration_presence * 0.4
    round(balance_score)
  end

  # Task 2.5.3.4: Analyze recursion termination conditions
  defp analyze_termination_conditions(recursive_functions, ast) do
    Logger.debug("Analyzing recursion termination conditions")

    termination_analysis =
      recursive_functions.recursive_functions
      |> Enum.map(fn func ->
        analyze_function_termination(func, ast)
      end)

    analysis = %{
      function_termination_analysis: termination_analysis,
      functions_with_proper_termination: count_proper_termination(termination_analysis),
      functions_with_questionable_termination:
        count_questionable_termination(termination_analysis),
      termination_safety_score: calculate_termination_safety_score(termination_analysis)
    }

    {:ok, analysis}
  end

  defp analyze_function_termination(recursive_func, ast) do
    function_body = extract_function_body(ast, recursive_func.function_name)

    termination_patterns = find_termination_patterns(function_body)

    infinite_recursion_risk =
      assess_infinite_recursion_risk(function_body, recursive_func.function_name)

    %{
      function_name: recursive_func.function_name,
      has_base_case: recursive_func.has_base_case,
      termination_patterns: termination_patterns,
      termination_pattern_count: length(termination_patterns),
      infinite_recursion_risk: infinite_recursion_risk,
      termination_safety:
        classify_termination_safety(
          recursive_func.has_base_case,
          termination_patterns,
          infinite_recursion_risk
        )
    }
  end

  defp find_termination_patterns(body) do
    # Look for patterns that ensure termination
    patterns = []

    # Base case patterns
    base_case_patterns =
      find_in_ast(body, fn
        # Empty list pattern []
        {:->, _, [[[]], _]} -> :empty_list_base_case
        # Zero/one pattern
        {:->, _, [[0], _]} -> :zero_base_case
        {:->, _, [[1], _]} -> :one_base_case
        # nil pattern
        {:->, _, [[nil], _]} -> :nil_base_case
        _ -> nil
      end)

    # Decreasing patterns
    decreasing_patterns =
      find_in_ast(body, fn
        # n - 1 pattern
        {:-, _, [{var, _, _}, 1]} when is_atom(var) -> :decrement_pattern
        # tl(list) pattern
        {:tl, _, _} -> :list_tail_pattern
        _ -> nil
      end)

    patterns ++ base_case_patterns ++ decreasing_patterns
  end

  defp assess_infinite_recursion_risk(body, function_name) do
    # Look for potential infinite recursion patterns
    recursive_calls =
      find_in_ast(body, fn
        {^function_name, _, args} when is_list(args) -> {:recursive_call, args}
        _ -> nil
      end)

    # Check if all recursive calls modify arguments appropriately
    risky_calls =
      recursive_calls
      |> Enum.filter(fn {:recursive_call, args} ->
        not arguments_decrease_toward_base_case?(args)
      end)

    case length(risky_calls) do
      0 -> :low
      n when n <= 2 -> :medium
      _ -> :high
    end
  end

  defp arguments_decrease_toward_base_case?(args) do
    # Simple heuristic: check if arguments suggest progress toward termination
    Enum.any?(args, fn
      # Subtraction suggests decreasing
      {:-, _, _} -> true
      # Tail suggests list shrinking
      {:tl, _, _} -> true
      # Division suggests decreasing
      {:div, _, _} -> true
      _ -> false
    end)
  end

  defp count_proper_termination(termination_analysis) do
    Enum.count(termination_analysis, fn analysis ->
      analysis.termination_safety in [:safe, :very_safe]
    end)
  end

  defp count_questionable_termination(termination_analysis) do
    Enum.count(termination_analysis, fn analysis ->
      analysis.termination_safety in [:risky, :unsafe]
    end)
  end

  defp classify_termination_safety(has_base_case, termination_patterns, infinite_recursion_risk) do
    case has_base_case do
      false -> :unsafe
      true -> classify_safe_termination(termination_patterns, infinite_recursion_risk)
    end
  end

  defp classify_safe_termination(termination_patterns, infinite_recursion_risk) do
    pattern_count = length(termination_patterns)

    cond do
      strong_termination_guarantees?(pattern_count, infinite_recursion_risk) -> :very_safe
      adequate_termination_guarantees?(pattern_count, infinite_recursion_risk) -> :safe
      risky_termination_pattern?(infinite_recursion_risk) -> :risky
      true -> :questionable
    end
  end

  defp strong_termination_guarantees?(pattern_count, risk) do
    pattern_count > 2 and risk == :low
  end

  defp adequate_termination_guarantees?(pattern_count, risk) do
    pattern_count > 0 and risk in [:low, :medium]
  end

  defp risky_termination_pattern?(risk) do
    risk == :high
  end

  defp calculate_termination_safety_score(termination_analysis) do
    if Enum.empty?(termination_analysis) do
      # No recursive functions to analyze
      100
    else
      safety_scores =
        termination_analysis
        |> Enum.map(&termination_safety_to_score/1)

      round(Enum.sum(safety_scores) / length(safety_scores))
    end
  end

  defp termination_safety_to_score(analysis) do
    case analysis.termination_safety do
      :very_safe -> 100
      :safe -> 90
      :questionable -> 70
      :risky -> 40
      :unsafe -> 10
    end
  end

  # Task 2.5.3.5: Score recursion appropriateness
  defp score_recursion_appropriateness(
         _recursive_functions,
         tail_recursion_analysis,
         iteration_comparison,
         termination_analysis
       ) do
    # Weighted scoring across recursion quality dimensions
    weights = %{
      tail_optimization: 0.3,
      iteration_balance: 0.25,
      termination_safety: 0.25,
      appropriateness: 0.2
    }

    tail_score = tail_recursion_analysis.tail_optimization_score
    balance_score = iteration_comparison.balance_score
    safety_score = termination_analysis.termination_safety_score
    appropriateness_score = calculate_context_appropriateness_score(iteration_comparison)

    weighted_score =
      tail_score * weights.tail_optimization +
        balance_score * weights.iteration_balance +
        safety_score * weights.termination_safety +
        appropriateness_score * weights.appropriateness

    appropriateness_score = round(weighted_score)

    {:ok, appropriateness_score}
  end

  defp calculate_context_appropriateness_score(iteration_comparison) do
    # Score based on whether recursion is used in appropriate contexts
    if Enum.empty?(iteration_comparison.recursive_vs_iterative) do
      100
    else
      appropriate_count =
        iteration_comparison.recursive_vs_iterative
        |> Enum.count(fn comparison ->
          comparison.appropriateness in [:highly_appropriate, :appropriate, :somewhat_appropriate]
        end)

      total_count = length(iteration_comparison.recursive_vs_iterative)

      round(appropriate_count / total_count * 100)
    end
  end

  # Utility functions (duplicates removed - using existing definitions above)

  defp classify_recursion_level(recursive_functions, appropriateness_score) do
    recursive_count = recursive_functions.recursive_function_count

    cond do
      recursive_count == 0 -> :no_recursion
      appropriateness_score >= 90 -> :excellent_recursion
      appropriateness_score >= 80 -> :good_recursion
      appropriateness_score >= 70 -> :acceptable_recursion
      appropriateness_score >= 60 -> :questionable_recursion
      true -> :poor_recursion
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
  Generates recursion analysis report with recommendations.
  """
  def generate_recursion_report(recursion_analysis) do
    report = %{
      summary: %{
        appropriateness_score: recursion_analysis.appropriateness_score,
        recursive_function_count: recursion_analysis.recursive_functions.recursive_function_count,
        tail_recursive_count: recursion_analysis.tail_recursion_analysis.tail_recursive_count,
        recursion_level: recursion_analysis.recursion_level
      },
      detailed_analysis: %{
        recursive_functions: recursion_analysis.recursive_functions,
        tail_recursion: recursion_analysis.tail_recursion_analysis,
        iteration_comparison: recursion_analysis.iteration_comparison,
        termination_safety: recursion_analysis.termination_analysis
      },
      recommendations: generate_recursion_recommendations(recursion_analysis),
      appropriateness_grade:
        classify_recursion_appropriateness(recursion_analysis.appropriateness_score),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_recursion_recommendations(analysis) do
    recommendations = []

    recommendations =
      if analysis.tail_recursion_analysis.optimization_opportunity_count > 0 do
        count = analysis.tail_recursion_analysis.optimization_opportunity_count

        [
          "Convert #{count} recursive functions to tail recursion for better performance"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.iteration_comparison.iteration_usage_score < 70 do
        [
          "Consider using Enum functions instead of recursion for simple list operations"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.termination_analysis.functions_with_questionable_termination > 0 do
        count = analysis.termination_analysis.functions_with_questionable_termination
        ["Review termination conditions for #{count} recursive functions" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["Recursion usage demonstrates excellent functional programming practices"]
    else
      recommendations
    end
  end

  defp classify_recursion_appropriateness(score) do
    cond do
      score >= 90 -> :excellent
      score >= 80 -> :good
      score >= 70 -> :acceptable
      score >= 60 -> :needs_improvement
      true -> :poor
    end
  end
end
