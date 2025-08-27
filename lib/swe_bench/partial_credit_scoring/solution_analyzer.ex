defmodule SweBench.PartialCreditScoring.SolutionAnalyzer do
  @moduledoc """
  Analyzes solutions for problem understanding and approach correctness.

  Detects partial implementations, evaluates algorithmic choices,
  and assesses code organization quality.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the solution analyzer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Analyzes a solution for understanding and approach quality.
  """
  def analyze_solution(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:analyze_solution, solution_data, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("SolutionAnalyzer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_solution, solution_data, _options}, _from, state) do
    analysis = perform_solution_analysis(solution_data, state.config)
    {:reply, {:ok, analysis}, state}
  rescue
    error ->
      Logger.error("Solution analysis failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_solution_analysis(solution_data, _config) do
    %{
      problem_understanding: analyze_problem_understanding(solution_data),
      partial_implementation: detect_partial_implementation(solution_data),
      approach_correctness: evaluate_approach_correctness(solution_data),
      algorithmic_choices: analyze_algorithmic_choices(solution_data),
      code_organization: assess_code_organization(solution_data),
      completeness_score: calculate_completeness_score(solution_data)
    }
  end

  defp analyze_problem_understanding(solution_data) do
    # Check if solution addresses the core problem
    problem_description = Map.get(solution_data, :problem_description, "")
    solution_code = Map.get(solution_data, :solution_code, "")

    understanding_indicators = [
      check_domain_terminology(solution_code, problem_description),
      check_expected_functions(solution_data),
      check_problem_constraints(solution_data),
      check_input_output_handling(solution_data)
    ]

    understanding_score =
      understanding_indicators
      |> Enum.count(& &1)
      |> Kernel./(length(understanding_indicators))
      |> Kernel.*(100.0)

    %{
      score: understanding_score,
      indicators: %{
        domain_terminology: Enum.at(understanding_indicators, 0),
        expected_functions: Enum.at(understanding_indicators, 1),
        problem_constraints: Enum.at(understanding_indicators, 2),
        input_output_handling: Enum.at(understanding_indicators, 3)
      }
    }
  end

  defp check_domain_terminology(solution_code, problem_description) do
    # Extract key terms from problem description and check if solution uses them
    key_terms = extract_key_terms(problem_description)

    if length(key_terms) > 0 do
      matches =
        Enum.count(key_terms, fn term ->
          String.contains?(String.downcase(solution_code), String.downcase(term))
        end)

      # At least 30% of terms should be present
      matches / length(key_terms) > 0.3
    else
      false
    end
  end

  defp extract_key_terms(description) do
    # Simple term extraction - could be enhanced with NLP
    description
    |> String.split(~r/\W+/)
    |> Enum.filter(fn word ->
      String.length(word) > 3 and word not in ["the", "and", "for", "with", "that", "this"]
    end)
    # Take top 10 meaningful terms
    |> Enum.take(10)
  end

  defp check_expected_functions(solution_data) do
    expected_functions = Map.get(solution_data, :expected_functions, [])
    implemented_functions = Map.get(solution_data, :implemented_functions, [])

    if expected_functions == [] do
      # No expectations means this check passes
      true
    else
      matches = count_function_matches(expected_functions, implemented_functions)
      # At least 50% of expected functions
      matches / length(expected_functions) > 0.5
    end
  end

  defp count_function_matches(expected_functions, implemented_functions) do
    Enum.count(expected_functions, fn expected ->
      Enum.any?(implemented_functions, fn impl -> String.contains?(impl, expected) end)
    end)
  end

  defp check_problem_constraints(solution_data) do
    constraints = Map.get(solution_data, :problem_constraints, [])

    # Check if solution appears to handle constraints
    # This is a simplified check - could be enhanced with AST analysis
    constraint_adherence =
      Enum.reduce(constraints, 0, fn constraint, acc ->
        if constraint_appears_handled(solution_data, constraint) do
          acc + 1
        else
          acc
        end
      end)

    if length(constraints) > 0 do
      constraint_adherence / length(constraints) > 0.6
    else
      true
    end
  end

  defp constraint_appears_handled(_solution_data, _constraint) do
    # Placeholder - would analyze if constraint is addressed in code
    true
  end

  defp check_input_output_handling(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    # Check for input validation and output formatting
    has_input_handling =
      String.contains?(solution_code, "when ") or
        String.contains?(solution_code, "case ") or
        String.contains?(solution_code, "if ")

    has_output_formatting =
      String.contains?(solution_code, "def ") and
        String.contains?(solution_code, " do")

    has_input_handling and has_output_formatting
  end

  defp detect_partial_implementation(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")
    expected_functions = Map.get(solution_data, :expected_functions, [])

    partial_indicators = [
      check_incomplete_functions(solution_code),
      check_todo_comments(solution_code),
      check_missing_implementations(solution_code, expected_functions),
      check_stub_patterns(solution_code)
    ]

    partial_count = Enum.count(partial_indicators, & &1)

    %{
      is_partial: partial_count > 0,
      partial_indicators: %{
        incomplete_functions: Enum.at(partial_indicators, 0),
        todo_comments: Enum.at(partial_indicators, 1),
        missing_implementations: Enum.at(partial_indicators, 2),
        stub_patterns: Enum.at(partial_indicators, 3)
      },
      completeness_percentage: max(0.0, 100.0 - partial_count * 25.0)
    }
  end

  defp check_incomplete_functions(code) do
    String.contains?(code, "# TODO") or
      String.contains?(code, "raise \"Not implemented\"") or
      String.contains?(code, ":not_implemented")
  end

  defp check_todo_comments(code) do
    String.contains?(code, "TODO") or
      String.contains?(code, "FIXME") or
      String.contains?(code, "XXX")
  end

  defp check_missing_implementations(code, expected_functions) do
    Enum.any?(expected_functions, fn func ->
      not String.contains?(code, "def #{func}")
    end)
  end

  defp check_stub_patterns(code) do
    String.contains?(code, "def ") and
      (String.contains?(code, "nil") or String.contains?(code, ":ok"))
  end

  defp evaluate_approach_correctness(solution_data) do
    # Analyze if the chosen approach is reasonable for the problem type
    problem_type = Map.get(solution_data, :problem_type, :unknown)
    algorithmic_approach = Map.get(solution_data, :detected_algorithm, :unknown)

    correctness_score =
      case {problem_type, algorithmic_approach} do
        {:sorting, :quick_sort} -> 90.0
        {:sorting, :merge_sort} -> 95.0
        {:sorting, :bubble_sort} -> 60.0
        {:search, :binary_search} -> 90.0
        {:search, :linear_search} -> 70.0
        {:graph, :bfs} -> 85.0
        {:graph, :dfs} -> 85.0
        # Default for unknown combinations
        _ -> 50.0
      end

    %{
      score: correctness_score,
      problem_type: problem_type,
      detected_algorithm: algorithmic_approach,
      approach_suitability: determine_approach_suitability(problem_type, algorithmic_approach)
    }
  end

  defp determine_approach_suitability(problem_type, algorithm) do
    # This would be enhanced with more sophisticated analysis
    case {problem_type, algorithm} do
      {:sorting, alg} when alg in [:quick_sort, :merge_sort] -> :excellent
      {:search, :binary_search} -> :excellent
      {:graph, alg} when alg in [:bfs, :dfs] -> :good
      _ -> :adequate
    end
  end

  defp analyze_algorithmic_choices(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    %{
      time_complexity: estimate_time_complexity(solution_code),
      space_complexity: estimate_space_complexity(solution_code),
      uses_appropriate_data_structures: check_data_structure_usage(solution_code),
      optimization_opportunities: identify_optimization_opportunities(solution_code)
    }
  end

  defp estimate_time_complexity(code) do
    cond do
      String.contains?(code, "Enum.each") and String.contains?(code, "Enum.map") -> :quadratic
      String.contains?(code, "Enum.reduce") -> :linear
      String.contains?(code, "Enum.find") -> :linear
      # Default assumption
      true -> :linear
    end
  end

  defp estimate_space_complexity(code) do
    cond do
      String.contains?(code, "List.flatten") -> :linear
      String.contains?(code, "Enum.map") -> :linear
      String.contains?(code, "Enum.filter") -> :linear
      # Default assumption
      true -> :constant
    end
  end

  defp check_data_structure_usage(code) do
    appropriate_structures = [
      String.contains?(code, "MapSet") and String.contains?(code, "member?"),
      String.contains?(code, "Map.get") and String.contains?(code, "%{"),
      String.contains?(code, "[") and String.contains?(code, "|")
    ]

    Enum.any?(appropriate_structures)
  end

  defp identify_optimization_opportunities(code) do
    opportunities = []

    opportunities =
      if String.contains?(code, "++") do
        ["Consider using List prepend [item | list] instead of ++" | opportunities]
      else
        opportunities
      end

    opportunities =
      if String.contains?(code, "Enum.map") and String.contains?(code, "Enum.filter") do
        ["Consider combining map and filter operations" | opportunities]
      else
        opportunities
      end

    opportunities
  end

  defp assess_code_organization(solution_data) do
    solution_code = Map.get(solution_data, :solution_code, "")

    %{
      function_modularity: assess_function_modularity(solution_code),
      naming_quality: assess_naming_quality(solution_code),
      documentation_quality: assess_documentation_quality(solution_code),
      code_structure_score: calculate_structure_score(solution_code)
    }
  end

  defp assess_function_modularity(code) do
    # Check for single responsibility principle
    function_count = length(Regex.scan(~r/def\s+\w+/, code))

    avg_function_length =
      if function_count > 0 do
        String.length(code) / function_count
      else
        0
      end

    cond do
      avg_function_length < 200 and function_count > 1 -> :good
      avg_function_length < 500 -> :fair
      true -> :poor
    end
  end

  defp assess_naming_quality(code) do
    # Simple heuristic for naming quality
    has_descriptive_names =
      String.contains?(code, "_") and
        not String.contains?(code, "x") and
        not String.contains?(code, "temp")

    if has_descriptive_names, do: :good, else: :fair
  end

  defp assess_documentation_quality(code) do
    has_moduledoc = String.contains?(code, "@moduledoc")
    has_doc = String.contains?(code, "@doc")
    has_comments = String.contains?(code, "#")

    cond do
      has_moduledoc and has_doc -> :excellent
      has_doc or has_comments -> :good
      true -> :minimal
    end
  end

  defp calculate_structure_score(code) do
    # Simple scoring based on structure indicators
    # Base score
    score = 50.0

    score = if String.contains?(code, "defmodule"), do: score + 20.0, else: score
    score = if String.contains?(code, "def "), do: score + 10.0, else: score

    score =
      if String.contains?(code, "case ") or String.contains?(code, "when "),
        do: score + 10.0,
        else: score

    score = if String.contains?(code, "with "), do: score + 10.0, else: score

    min(100.0, score)
  end

  defp calculate_completeness_score(solution_data) do
    understanding = get_in(solution_data, [:problem_understanding, :score]) || 0.0
    partial_impl = Map.get(solution_data, :partial_implementation, %{})
    completeness_pct = Map.get(partial_impl, :completeness_percentage, 0.0)
    approach = get_in(solution_data, [:approach_correctness, :score]) || 0.0

    understanding * 0.3 + completeness_pct * 0.4 + approach * 0.3
  end
end
