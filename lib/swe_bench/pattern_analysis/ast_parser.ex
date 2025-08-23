defmodule SweBench.PatternAnalysis.ASTParser do
  @moduledoc """
  AST parser for pattern matching analysis.

  Parses Elixir source code into quoted expressions, extracts function
  definitions and clauses, and identifies pattern types for analysis.
  """

  require Logger

  @doc """
  Parses Elixir source code and extracts pattern matching information.
  """
  def parse_source(source_code) when is_binary(source_code) do
    case Code.string_to_quoted(source_code) do
      {:ok, ast} ->
        analysis = %{
          functions: extract_function_definitions(ast),
          patterns: extract_patterns(ast),
          guards: extract_guard_expressions(ast),
          metadata: %{
            source_length: String.length(source_code),
            parsed_at: DateTime.utc_now()
          }
        }

        {:ok, analysis}

      {:error, reason} ->
        Logger.error("Failed to parse source code: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Parses source code from a file path.
  """
  def parse_file(file_path) do
    case File.read(file_path) do
      {:ok, source_code} ->
        parse_source(source_code)

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Extracts function definitions with their clauses and patterns.
  """
  def extract_function_definitions(ast) do
    ast
    |> find_function_nodes()
    |> Enum.map(&analyze_function_node/1)
    |> Enum.filter(& &1)
  end

  @doc """
  Extracts all patterns from function clauses.
  """
  def extract_patterns(ast) do
    ast
    |> find_pattern_nodes()
    |> Enum.map(&analyze_pattern_node/1)
    |> List.flatten()
  end

  @doc """
  Extracts guard expressions and their complexity.
  """
  def extract_guard_expressions(ast) do
    ast
    |> find_guard_nodes()
    |> Enum.map(&analyze_guard_node/1)
  end

  @doc """
  Builds a pattern coverage matrix for analysis.
  """
  def build_pattern_coverage_matrix(functions) do
    Map.new(functions, fn function ->
      coverage = %{
        total_clauses: length(function.clauses),
        pattern_types: analyze_pattern_types(function.clauses),
        guard_coverage: analyze_guard_coverage(function.clauses),
        exhaustiveness_score: calculate_exhaustiveness_score(function.clauses)
      }

      {function.name, coverage}
    end)
  end

  # Private helper functions

  defp find_function_nodes(ast) do
    case ast do
      {:defmodule, _, [{_module, _, _}, [do: {:__block__, _, body}]]} ->
        extract_functions_from_body(body)

      {:defmodule, _, [{_module, _, _}, [do: single_expr]]} ->
        extract_functions_from_body([single_expr])

      {:__block__, _, body} ->
        extract_functions_from_body(body)

      _ ->
        []
    end
  end

  defp extract_functions_from_body(body) when is_list(body) do
    Enum.flat_map(body, fn expr ->
      case expr do
        {:def, _, _} = def_node -> [def_node]
        {:defp, _, _} = defp_node -> [defp_node]
        _ -> []
      end
    end)
  end

  defp extract_functions_from_body(_), do: []

  defp analyze_function_node({def_type, meta, clauses}) when def_type in [:def, :defp] do
    case extract_function_name_and_clauses(clauses) do
      {name, arity, function_clauses} ->
        %{
          name: name,
          arity: arity,
          type: def_type,
          clauses: analyze_function_clauses(function_clauses),
          meta: meta,
          line: Keyword.get(meta, :line)
        }

      nil ->
        nil
    end
  end

  defp analyze_function_node(_), do: nil

  defp extract_function_name_and_clauses([{:when, _, [{name, _, args}, _guard]} | _] = clauses)
       when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity, clauses}
  end

  defp extract_function_name_and_clauses([{name, _, args} | _] = clauses) when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity, clauses}
  end

  defp extract_function_name_and_clauses(_), do: nil

  defp analyze_function_clauses(clauses) do
    Enum.with_index(clauses, fn clause, index ->
      analyze_single_clause(clause, index)
    end)
  end

  defp analyze_single_clause({:when, meta, [head, guard]}, index) do
    %{
      index: index,
      head: head,
      guard: guard,
      patterns: extract_patterns_from_head(head),
      guard_complexity: calculate_guard_complexity(guard),
      meta: meta
    }
  end

  defp analyze_single_clause(head, index) do
    %{
      index: index,
      head: head,
      guard: nil,
      patterns: extract_patterns_from_head(head),
      guard_complexity: 0,
      meta: []
    }
  end

  defp extract_patterns_from_head({_name, _, args}) when is_list(args) do
    Enum.map(args, &analyze_pattern_structure/1)
  end

  defp extract_patterns_from_head(_), do: []

  defp analyze_pattern_structure(pattern) do
    %{
      type: determine_pattern_type(pattern),
      complexity: calculate_pattern_complexity(pattern),
      specificity: calculate_pattern_specificity(pattern),
      destructuring_depth: calculate_destructuring_depth(pattern)
    }
  end

  defp determine_pattern_type(pattern) do
    cond do
      literal_pattern?(pattern) -> classify_literal_pattern(pattern)
      structural_pattern?(pattern) -> classify_structural_pattern(pattern)
      variable_pattern?(pattern) -> classify_variable_pattern(pattern)
      true -> :complex
    end
  end

  defp literal_pattern?(pattern) do
    is_atom(pattern) or is_number(pattern) or is_binary(pattern)
  end

  defp classify_literal_pattern(pattern) do
    cond do
      is_atom(pattern) -> :literal_atom
      is_number(pattern) -> :literal_number
      is_binary(pattern) -> :literal_string
    end
  end

  defp structural_pattern?(pattern) do
    case pattern do
      {:{}, _, _} -> true
      [_ | _] -> true
      %{} -> true
      {_, _} -> true
      {:_, _, _} -> true
      _ -> false
    end
  end

  defp classify_structural_pattern(pattern) do
    case pattern do
      {:{}, _, _} -> :tuple
      [_ | _] -> :list
      %{} -> :map
      {_, _} -> :two_tuple
      {:_, _, _} -> :wildcard
    end
  end

  defp variable_pattern?(pattern) do
    case pattern do
      {name, _, nil} when is_atom(name) -> true
      {name, _, _} when is_atom(name) -> true
      _ -> false
    end
  end

  defp classify_variable_pattern(pattern) do
    case pattern do
      {name, _, nil} when is_atom(name) -> :variable
      {name, _, _} when is_atom(name) -> :variable_with_context
    end
  end

  defp calculate_pattern_complexity(pattern) do
    case pattern do
      atom when is_atom(atom) ->
        1

      number when is_number(number) ->
        1

      binary when is_binary(binary) ->
        1

      {:{}, _, elements} ->
        1 + Enum.sum(Enum.map(elements, &calculate_pattern_complexity/1))

      [head | tail] ->
        1 + calculate_pattern_complexity(head) + calculate_pattern_complexity(tail)

      %{} = map ->
        1 + map_size(map)

      {left, right} ->
        1 + calculate_pattern_complexity(left) + calculate_pattern_complexity(right)

      _ ->
        1
    end
  end

  defp calculate_pattern_specificity(pattern) do
    cond do
      wildcard_pattern?(pattern) -> 0
      variable_pattern_simple?(pattern) -> 1
      literal_pattern?(pattern) -> 5
      map_pattern?(pattern) -> 4
      tuple_pattern?(pattern) -> 3
      list_pattern?(pattern) -> 2
      true -> 2
    end
  end

  defp wildcard_pattern?({:_, _, _}), do: true
  defp wildcard_pattern?(_), do: false

  defp variable_pattern_simple?({name, _, nil}) when is_atom(name), do: true
  defp variable_pattern_simple?(_), do: false

  defp map_pattern?(%{}), do: true
  defp map_pattern?(_), do: false

  defp tuple_pattern?({:{}, _, _}), do: true
  defp tuple_pattern?(_), do: false

  defp list_pattern?([_ | _]), do: true
  defp list_pattern?(_), do: false

  defp calculate_destructuring_depth(pattern) do
    case pattern do
      {:{}, _, elements} ->
        1 + Enum.max(Enum.map(elements, &calculate_destructuring_depth/1), fn -> 0 end)

      [head | tail] ->
        1 + max(calculate_destructuring_depth(head), calculate_destructuring_depth(tail))

      {left, right} ->
        1 + max(calculate_destructuring_depth(left), calculate_destructuring_depth(right))

      %{} = map when map_size(map) > 0 ->
        1

      _ ->
        0
    end
  end

  defp find_pattern_nodes(ast) do
    # Extract patterns from function heads
    functions = find_function_nodes(ast)

    Enum.flat_map(functions, fn function ->
      case analyze_function_node(function) do
        nil -> []
        analyzed -> Enum.flat_map(analyzed.clauses, & &1.patterns)
      end
    end)
  end

  defp find_guard_nodes(ast) do
    functions = find_function_nodes(ast)

    Enum.flat_map(functions, fn function ->
      case analyze_function_node(function) do
        nil ->
          []

        analyzed ->
          analyzed.clauses
          |> Enum.filter(& &1.guard)
          |> Enum.map(& &1.guard)
      end
    end)
  end

  defp analyze_pattern_node(pattern) do
    analyze_pattern_structure(pattern)
  end

  defp analyze_guard_node(guard) do
    %{
      guard_ast: guard,
      complexity: calculate_guard_complexity(guard),
      predicates: extract_guard_predicates(guard)
    }
  end

  defp calculate_guard_complexity({:and, _, [left, right]}) do
    1 + calculate_guard_complexity(left) + calculate_guard_complexity(right)
  end

  defp calculate_guard_complexity({:or, _, [left, right]}) do
    1 + calculate_guard_complexity(left) + calculate_guard_complexity(right)
  end

  defp calculate_guard_complexity({:not, _, [expr]}) do
    1 + calculate_guard_complexity(expr)
  end

  defp calculate_guard_complexity({_func, _, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &calculate_guard_complexity/1))
  end

  defp calculate_guard_complexity(_), do: 1

  defp extract_guard_predicates(guard) do
    case guard do
      {:and, _, [left, right]} ->
        extract_guard_predicates(left) ++ extract_guard_predicates(right)

      {:or, _, [left, right]} ->
        extract_guard_predicates(left) ++ extract_guard_predicates(right)

      {predicate, _, _} when is_atom(predicate) ->
        [predicate]

      _ ->
        []
    end
  end

  defp analyze_pattern_types(clauses) do
    clauses
    |> Enum.flat_map(& &1.patterns)
    |> Enum.map(& &1.type)
    |> Enum.frequencies()
  end

  defp analyze_guard_coverage(clauses) do
    total_clauses = length(clauses)
    guarded_clauses = Enum.count(clauses, & &1.guard)

    %{
      total_clauses: total_clauses,
      guarded_clauses: guarded_clauses,
      guard_coverage_ratio: if(total_clauses > 0, do: guarded_clauses / total_clauses, else: 0)
    }
  end

  defp calculate_exhaustiveness_score(clauses) do
    # Simple heuristic for exhaustiveness
    total_patterns = Enum.sum(Enum.map(clauses, &length(&1.patterns)))
    wildcard_patterns = count_wildcard_patterns(clauses)

    base_score = if wildcard_patterns > 0, do: 80, else: 60
    pattern_bonus = min(20, total_patterns * 2)

    min(100, base_score + pattern_bonus)
  end

  defp count_wildcard_patterns(clauses) do
    clauses
    |> Enum.flat_map(& &1.patterns)
    |> Enum.count(&(&1.type == :wildcard))
  end
end
