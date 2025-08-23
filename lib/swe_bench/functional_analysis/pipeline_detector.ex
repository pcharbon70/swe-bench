defmodule SweBench.FunctionalAnalysis.PipelineDetector do
  @moduledoc """
  Detects and analyzes pipeline usage patterns in Elixir code.

  Identifies pipe operator usage patterns, detects opportunities for pipeline
  refactoring, analyzes pipeline readability, checks for anti-patterns,
  and calculates pipeline effectiveness scores.
  """

  require Logger

  # @pipeline_anti_patterns [
  #   :function_call_start,      # Pipeline starts with function call instead of data
  #   :nested_case_in_pipe,      # Case statement within pipeline
  #   :nested_if_in_pipe,        # If statement within pipeline
  #   :single_step_pipe,         # Pipeline with only one step
  #   :assignment_in_pipe        # Variable assignment within pipeline
  # ]

  @doc """
  Analyzes pipeline usage patterns and effectiveness in source code.

  ## Parameters
    - source_code: Elixir source code as string
    - opts: Analysis options including strictness and pattern detection settings

  ## Returns
    - {:ok, pipeline_analysis} - Successful analysis with effectiveness scores
    - {:error, reason} - Analysis error
  """
  def analyze_pipeline_usage(source_code, _opts \\ []) do
    Logger.info("Starting pipeline usage analysis")

    with {:ok, ast} <- parse_source_code(source_code),
         {:ok, pipeline_patterns} <- identify_pipe_operator_patterns(ast),
         {:ok, refactoring_opportunities} <- detect_refactoring_opportunities(ast),
         {:ok, readability_analysis} <- analyze_pipeline_readability(pipeline_patterns),
         {:ok, anti_pattern_analysis} <- check_for_anti_patterns(pipeline_patterns),
         {:ok, effectiveness_score} <-
           calculate_pipeline_effectiveness(
             pipeline_patterns,
             refactoring_opportunities,
             readability_analysis,
             anti_pattern_analysis
           ) do
      pipeline_analysis = %{
        source_code_analyzed: true,
        pipeline_patterns: pipeline_patterns,
        refactoring_opportunities: refactoring_opportunities,
        readability_analysis: readability_analysis,
        anti_pattern_analysis: anti_pattern_analysis,
        effectiveness_score: effectiveness_score,
        pipeline_usage_level: classify_pipeline_usage(pipeline_patterns, effectiveness_score),
        analyzed_at: DateTime.utc_now()
      }

      Logger.info("Pipeline analysis complete: score #{effectiveness_score}")
      {:ok, pipeline_analysis}
    else
      {:error, reason} ->
        Logger.warning("Pipeline analysis failed: #{inspect(reason)}")
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

  # Task 2.5.2.1: Identify pipe operator usage patterns
  defp identify_pipe_operator_patterns(ast) do
    Logger.debug("Identifying pipe operator usage patterns")

    pipelines = find_pipeline_expressions(ast)

    pipeline_analysis =
      pipelines
      |> Enum.map(&analyze_single_pipeline/1)

    patterns = %{
      pipelines: pipeline_analysis,
      pipeline_count: length(pipeline_analysis),
      total_pipeline_steps: count_total_pipeline_steps(pipeline_analysis),
      average_pipeline_length: calculate_average_pipeline_length(pipeline_analysis),
      pipeline_density: calculate_pipeline_density(ast, length(pipeline_analysis))
    }

    {:ok, patterns}
  end

  defp find_pipeline_expressions(ast) do
    find_in_ast(ast, fn
      {:|>, _, _} = pipeline -> extract_full_pipeline(pipeline)
      _ -> nil
    end)
  end

  defp extract_full_pipeline({:|>, _, [_left, _right]} = pipeline) do
    # Recursively extract the full pipeline chain
    steps = collect_pipeline_steps(pipeline, [])

    %{
      full_pipeline: pipeline,
      steps: steps,
      step_count: length(steps),
      starts_with_data: pipeline_starts_with_data?(steps),
      complexity: assess_pipeline_complexity(steps)
    }
  end

  defp collect_pipeline_steps({:|>, _, [left, right]}, acc) do
    left_steps =
      case left do
        {:|>, _, _} -> collect_pipeline_steps(left, [])
        _ -> [left]
      end

    left_steps ++ [right | acc]
  end

  defp collect_pipeline_steps(non_pipeline, acc) do
    [non_pipeline | acc]
  end

  defp pipeline_starts_with_data?(steps) do
    case List.first(steps) do
      # Data literals
      data when is_binary(data) or is_number(data) or is_list(data) or is_map(data) -> true
      # Variables (usually data)
      {var_name, _, _} when is_atom(var_name) -> true
      # Module calls suggest function calls, not data
      {{:., _, _}, _, _} -> false
      # Bare function calls
      {func_name, _, _} when is_atom(func_name) -> false
      _ -> false
    end
  end

  defp assess_pipeline_complexity(steps) do
    complexity_factors =
      steps
      |> Enum.map(&assess_step_complexity/1)
      |> Enum.sum()

    case complexity_factors do
      n when n <= 3 -> :simple
      n when n <= 6 -> :moderate
      n when n <= 10 -> :complex
      _ -> :very_complex
    end
  end

  defp assess_step_complexity(step) do
    case step do
      # Simple function calls
      {func_name, _, []} when is_atom(func_name) -> 1
      {func_name, _, [_]} when is_atom(func_name) -> 1
      # Module function calls
      {{:., _, [_module, _func]}, _, args} when is_list(args) -> 1 + length(args) * 0.2
      # Anonymous functions add complexity
      {:fn, _, _} -> 3
      # Case/if statements in pipeline steps
      {:case, _, _} -> 4
      {:if, _, _} -> 3
      {:cond, _, _} -> 4
      _ -> 1
    end
  end

  defp analyze_single_pipeline(pipeline_info) do
    %{
      step_count: pipeline_info.step_count,
      starts_with_data: pipeline_info.starts_with_data,
      complexity: pipeline_info.complexity,
      readability_score: calculate_pipeline_readability_score(pipeline_info),
      anti_patterns: detect_pipeline_anti_patterns(pipeline_info)
    }
  end

  defp calculate_pipeline_readability_score(pipeline_info) do
    base_score = 100

    # Penalty for not starting with data
    data_start_penalty = if pipeline_info.starts_with_data, do: 0, else: 20

    # Penalty for excessive complexity
    complexity_penalty =
      case pipeline_info.complexity do
        :simple -> 0
        :moderate -> 5
        :complex -> 15
        :very_complex -> 30
      end

    # Penalty for very short or very long pipelines
    length_penalty =
      case pipeline_info.step_count do
        # Too short to be useful
        n when n < 2 -> 10
        # Too long to be readable
        n when n > 8 -> 15
        _ -> 0
      end

    total_penalty = data_start_penalty + complexity_penalty + length_penalty
    max(0, base_score - total_penalty)
  end

  defp detect_pipeline_anti_patterns(pipeline_info) do
    anti_patterns = []

    anti_patterns =
      if pipeline_info.starts_with_data do
        anti_patterns
      else
        [:function_call_start | anti_patterns]
      end

    anti_patterns =
      if pipeline_info.step_count == 1 do
        [:single_step_pipe | anti_patterns]
      else
        anti_patterns
      end

    # Check for nested complexity in steps
    anti_patterns =
      if pipeline_info.complexity in [:complex, :very_complex] do
        [:excessive_complexity | anti_patterns]
      else
        anti_patterns
      end

    anti_patterns
  end

  # Task 2.5.2.2: Detect opportunities for pipeline refactoring
  defp detect_refactoring_opportunities(ast) do
    Logger.debug("Detecting pipeline refactoring opportunities")

    nested_function_calls = find_nested_function_calls(ast)
    sequential_operations = find_sequential_operations(ast)
    transformative_chains = find_transformative_chains(ast)

    opportunities = %{
      nested_calls_to_pipeline: analyze_nested_call_opportunities(nested_function_calls),
      sequential_to_pipeline: analyze_sequential_opportunities(sequential_operations),
      transformation_chains: analyze_transformation_opportunities(transformative_chains),
      total_opportunities:
        length(nested_function_calls) + length(sequential_operations) +
          length(transformative_chains),
      refactoring_score:
        calculate_refactoring_score(
          nested_function_calls,
          sequential_operations,
          transformative_chains
        )
    }

    {:ok, opportunities}
  end

  defp find_nested_function_calls(ast) do
    # Find deeply nested function calls that could be pipelined
    find_in_ast(ast, fn
      {outer_func, _, [inner_call]} when is_atom(outer_func) ->
        case inner_call do
          {inner_func, _, _} when is_atom(inner_func) ->
            %{
              type: :nested_function_call,
              outer: outer_func,
              inner: inner_func,
              nesting_depth: calculate_nesting_depth(inner_call)
            }

          _ ->
            nil
        end

      _ ->
        nil
    end)
    |> Enum.filter(fn opportunity -> opportunity.nesting_depth > 2 end)
  end

  defp calculate_nesting_depth({_, _, [inner]}) when is_tuple(inner) do
    1 + calculate_nesting_depth(inner)
  end

  defp calculate_nesting_depth(_), do: 1

  defp find_sequential_operations(ast) do
    # Find sequential variable assignments that could be pipelined
    find_in_ast(ast, fn
      {:__block__, _, statements} when is_list(statements) ->
        sequential_assigns = find_sequential_assignments(statements)

        if length(sequential_assigns) > 2 do
          %{
            type: :sequential_operations,
            assignments: sequential_assigns,
            count: length(sequential_assigns)
          }
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp find_sequential_assignments(statements) do
    statements
    |> Enum.filter(fn
      {:=, _, [{var_name, _, _}, _]} when is_atom(var_name) -> true
      _ -> false
    end)
  end

  defp find_transformative_chains(ast) do
    # Find chains of Enum operations that could be pipelined
    find_in_ast(ast, fn
      {enum_func1, _, [{enum_func2, _, [_data | _]} | _]}
      when enum_func1 in [:Enum, :Stream] and enum_func2 in [:Enum, :Stream] ->
        %{
          type: :transformative_chain,
          operations: [enum_func1, enum_func2],
          # Could be extended to detect longer chains
          chain_length: 2
        }

      _ ->
        nil
    end)
  end

  defp analyze_nested_call_opportunities(nested_calls) do
    %{
      opportunities: nested_calls,
      count: length(nested_calls),
      average_nesting_depth: calculate_average_nesting_depth(nested_calls),
      refactoring_potential: classify_refactoring_potential(nested_calls)
    }
  end

  defp analyze_sequential_opportunities(sequential_ops) do
    %{
      opportunities: sequential_ops,
      count: length(sequential_ops),
      total_sequential_assignments: count_total_assignments(sequential_ops),
      refactoring_potential: classify_sequential_potential(sequential_ops)
    }
  end

  defp analyze_transformation_opportunities(transformative_chains) do
    %{
      opportunities: transformative_chains,
      count: length(transformative_chains),
      average_chain_length: calculate_average_chain_length(transformative_chains),
      refactoring_potential: classify_transformation_potential(transformative_chains)
    }
  end

  defp calculate_average_nesting_depth(nested_calls) do
    if Enum.empty?(nested_calls) do
      0
    else
      total_depth = Enum.sum(Enum.map(nested_calls, & &1.nesting_depth))
      total_depth / length(nested_calls)
    end
  end

  defp count_total_assignments(sequential_ops) do
    Enum.sum(Enum.map(sequential_ops, & &1.count))
  end

  defp calculate_average_chain_length(chains) do
    if Enum.empty?(chains) do
      0
    else
      total_length = Enum.sum(Enum.map(chains, & &1.chain_length))
      total_length / length(chains)
    end
  end

  defp classify_refactoring_potential(items) do
    count = length(items)

    cond do
      count > 10 -> :high
      count > 5 -> :medium
      count > 0 -> :low
      true -> :none
    end
  end

  defp classify_sequential_potential(sequential_ops) do
    total_assignments = count_total_assignments(sequential_ops)

    cond do
      total_assignments > 15 -> :high
      total_assignments > 8 -> :medium
      total_assignments > 3 -> :low
      true -> :none
    end
  end

  defp classify_transformation_potential(chains) do
    avg_length = calculate_average_chain_length(chains)

    cond do
      avg_length > 3 -> :high
      avg_length > 2 -> :medium
      avg_length > 1 -> :low
      true -> :none
    end
  end

  defp calculate_refactoring_score(nested_calls, sequential_ops, transformative_chains) do
    base_score = 100

    # Penalty for missed opportunities
    nested_penalty = length(nested_calls) * 8
    sequential_penalty = count_total_assignments(sequential_ops) * 3
    transformation_penalty = length(transformative_chains) * 6

    total_penalty = nested_penalty + sequential_penalty + transformation_penalty
    max(0, base_score - total_penalty)
  end

  # Task 2.5.2.3: Analyze pipeline readability
  defp analyze_pipeline_readability(pipeline_patterns) do
    Logger.debug("Analyzing pipeline readability")

    if Enum.empty?(pipeline_patterns.pipelines) do
      {:ok,
       %{
         # No pipelines to analyze
         readability_score: 100,
         readability_issues: [],
         readability_level: :not_applicable
       }}
    else
      readability_scores =
        pipeline_patterns.pipelines
        |> Enum.map(& &1.readability_score)

      average_readability = Enum.sum(readability_scores) / length(readability_scores)

      readability_issues = collect_readability_issues(pipeline_patterns.pipelines)

      readability_analysis = %{
        readability_score: round(average_readability),
        individual_scores: readability_scores,
        readability_issues: readability_issues,
        readability_level: classify_readability_level(average_readability),
        best_pipeline_score: Enum.max(readability_scores, fn -> 0 end),
        worst_pipeline_score: Enum.min(readability_scores, fn -> 100 end)
      }

      {:ok, readability_analysis}
    end
  end

  defp collect_readability_issues(pipelines) do
    pipelines
    |> Enum.flat_map(fn pipeline ->
      issues = []

      issues =
        if pipeline.starts_with_data do
          issues
        else
          ["Pipeline should start with data, not function call" | issues]
        end

      issues =
        if pipeline.complexity in [:complex, :very_complex] do
          ["Pipeline too complex - consider breaking into smaller steps" | issues]
        else
          issues
        end

      issues =
        if pipeline.step_count > 8 do
          ["Pipeline too long - consider extracting intermediate variables" | issues]
        else
          issues
        end

      issues
    end)
  end

  defp classify_readability_level(average_score) do
    cond do
      average_score >= 90 -> :excellent
      average_score >= 80 -> :good
      average_score >= 70 -> :acceptable
      average_score >= 60 -> :needs_improvement
      true -> :poor
    end
  end

  # Task 2.5.2.4: Check for anti-patterns in pipelines
  defp check_for_anti_patterns(pipeline_patterns) do
    Logger.debug("Checking for pipeline anti-patterns")

    if Enum.empty?(pipeline_patterns.pipelines) do
      {:ok,
       %{
         anti_patterns: [],
         anti_pattern_count: 0,
         anti_pattern_score: 100
       }}
    else
      all_anti_patterns =
        pipeline_patterns.pipelines
        |> Enum.flat_map(& &1.anti_patterns)

      anti_pattern_analysis = %{
        anti_patterns: all_anti_patterns,
        anti_pattern_count: length(all_anti_patterns),
        anti_pattern_distribution: Enum.frequencies(all_anti_patterns),
        anti_pattern_score: calculate_anti_pattern_score(all_anti_patterns),
        most_common_anti_pattern: find_most_common_anti_pattern(all_anti_patterns)
      }

      {:ok, anti_pattern_analysis}
    end
  end

  defp calculate_anti_pattern_score(anti_patterns) do
    base_score = 100

    # Different penalties for different anti-patterns
    penalty =
      anti_patterns
      |> Enum.map(fn pattern ->
        case pattern do
          :function_call_start -> 15
          :nested_case_in_pipe -> 20
          :nested_if_in_pipe -> 15
          :single_step_pipe -> 8
          :assignment_in_pipe -> 12
          :excessive_complexity -> 18
          _ -> 10
        end
      end)
      |> Enum.sum()

    max(0, base_score - penalty)
  end

  defp find_most_common_anti_pattern(anti_patterns) do
    case Enum.frequencies(anti_patterns) do
      frequencies when map_size(frequencies) > 0 ->
        Enum.max_by(frequencies, fn {_pattern, count} -> count end)
        |> elem(0)

      _ ->
        :none
    end
  end

  # Task 2.5.2.5: Calculate pipeline effectiveness score
  defp calculate_pipeline_effectiveness(
         pipeline_patterns,
         refactoring_opportunities,
         readability_analysis,
         anti_pattern_analysis
       ) do
    # Weighted combination of different pipeline quality dimensions
    weights = %{
      # How much pipelines are used
      usage_density: 0.3,
      # How readable the pipelines are
      readability: 0.25,
      # Absence of anti-patterns
      anti_patterns: 0.2,
      # Utilization of pipeline opportunities
      refactoring: 0.25
    }

    usage_score = calculate_usage_density_score(pipeline_patterns)
    readability_score = readability_analysis.readability_score
    anti_pattern_score = anti_pattern_analysis.anti_pattern_score
    refactoring_score = refactoring_opportunities.refactoring_score

    effectiveness_score =
      usage_score * weights.usage_density +
        readability_score * weights.readability +
        anti_pattern_score * weights.anti_patterns +
        refactoring_score * weights.refactoring

    {:ok, round(effectiveness_score)}
  end

  defp calculate_usage_density_score(pipeline_patterns) do
    # Score based on pipeline density and average length
    density = pipeline_patterns.pipeline_density
    avg_length = pipeline_patterns.average_pipeline_length

    # Base score from density
    # Normalize density to 0-100
    density_score = min(100, density * 50)

    # Bonus for good average pipeline length
    length_bonus =
      case avg_length do
        # Optimal length
        n when n >= 3 and n <= 6 -> 20
        # Acceptable length
        n when n >= 2 and n < 8 -> 10
        _ -> 0
      end

    min(100, density_score + length_bonus)
  end

  # Helper functions

  defp count_total_pipeline_steps(pipeline_analysis) do
    Enum.sum(Enum.map(pipeline_analysis, & &1.step_count))
  end

  defp calculate_average_pipeline_length(pipeline_analysis) do
    if Enum.empty?(pipeline_analysis) do
      0
    else
      total_steps = count_total_pipeline_steps(pipeline_analysis)
      total_steps / length(pipeline_analysis)
    end
  end

  defp calculate_pipeline_density(ast, pipeline_count) do
    total_expressions = count_total_expressions(ast)

    if total_expressions > 0 do
      pipeline_count / total_expressions
    else
      0
    end
  end

  defp count_total_expressions(ast) do
    # Count significant expressions (function calls, assignments, etc.)
    expressions =
      find_in_ast(ast, fn
        {func_name, _, _} when is_atom(func_name) -> :expression
        {:=, _, _} -> :expression
        {{:., _, _}, _, _} -> :expression
        _ -> nil
      end)

    length(expressions)
  end

  defp classify_pipeline_usage(pipeline_patterns, effectiveness_score) do
    cond do
      pipeline_patterns.pipeline_count == 0 -> :none
      effectiveness_score >= 90 -> :excellent
      effectiveness_score >= 80 -> :good
      effectiveness_score >= 70 -> :moderate
      effectiveness_score >= 60 -> :basic
      true -> :poor
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
  Generates pipeline usage analysis report with recommendations.
  """
  def generate_pipeline_report(pipeline_analysis) do
    report = %{
      summary: %{
        effectiveness_score: pipeline_analysis.effectiveness_score,
        pipeline_count: pipeline_analysis.pipeline_patterns.pipeline_count,
        refactoring_opportunities:
          pipeline_analysis.refactoring_opportunities.total_opportunities,
        usage_level: pipeline_analysis.pipeline_usage_level,
        readability_level: pipeline_analysis.readability_analysis.readability_level
      },
      detailed_analysis: %{
        pipeline_patterns: pipeline_analysis.pipeline_patterns,
        refactoring_opportunities: pipeline_analysis.refactoring_opportunities,
        readability_metrics: pipeline_analysis.readability_analysis,
        anti_patterns: pipeline_analysis.anti_pattern_analysis
      },
      recommendations: generate_pipeline_recommendations(pipeline_analysis),
      effectiveness_grade: classify_pipeline_effectiveness(pipeline_analysis.effectiveness_score),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_pipeline_recommendations(analysis) do
    recommendations = []

    recommendations =
      if analysis.pipeline_patterns.pipeline_count == 0 do
        [
          "Consider using pipeline operators (|>) for data transformation sequences"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.refactoring_opportunities.total_opportunities > 5 do
        [
          "Refactor #{analysis.refactoring_opportunities.total_opportunities} nested calls to use pipelines"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.readability_analysis.readability_level in [:needs_improvement, :poor] do
        [
          "Improve pipeline readability - current score: #{analysis.readability_analysis.readability_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.anti_pattern_analysis.anti_pattern_count > 3 do
        [
          "Address #{analysis.anti_pattern_analysis.anti_pattern_count} pipeline anti-patterns"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Pipeline usage demonstrates excellent functional programming practices"]
    else
      recommendations
    end
  end

  defp classify_pipeline_effectiveness(score) do
    cond do
      score >= 90 -> :excellent
      score >= 80 -> :good
      score >= 70 -> :acceptable
      score >= 60 -> :needs_improvement
      true -> :poor
    end
  end

  @doc """
  Validates pipeline analysis results against quality thresholds.
  """
  def validate_pipeline_results(analysis, thresholds \\ default_pipeline_thresholds()) do
    validation = %{
      effectiveness_acceptable:
        analysis.effectiveness_score >= thresholds.minimum_effectiveness_score,
      readability_acceptable:
        analysis.readability_analysis.readability_score >= thresholds.minimum_readability_score,
      anti_patterns_acceptable:
        analysis.anti_pattern_analysis.anti_pattern_count <= thresholds.max_anti_patterns,
      usage_adequate:
        analysis.pipeline_patterns.pipeline_count >= thresholds.minimum_pipeline_count
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_pipeline_validation_issues(validation, analysis)
    }
  end

  defp default_pipeline_thresholds do
    %{
      minimum_effectiveness_score: 70,
      minimum_readability_score: 75,
      max_anti_patterns: 5,
      minimum_pipeline_count: 1
    }
  end

  defp collect_pipeline_validation_issues(validation, analysis) do
    issues = []

    issues =
      if validation.effectiveness_acceptable do
        issues
      else
        ["Pipeline effectiveness below threshold: #{analysis.effectiveness_score}" | issues]
      end

    issues =
      if validation.readability_acceptable do
        issues
      else
        [
          "Pipeline readability below threshold: #{analysis.readability_analysis.readability_score}"
          | issues
        ]
      end

    issues =
      if validation.anti_patterns_acceptable do
        issues
      else
        [
          "Too many pipeline anti-patterns: #{analysis.anti_pattern_analysis.anti_pattern_count}"
          | issues
        ]
      end

    issues =
      if validation.usage_adequate do
        issues
      else
        [
          "Insufficient pipeline usage: #{analysis.pipeline_patterns.pipeline_count} pipelines found"
          | issues
        ]
      end

    issues
  end
end
