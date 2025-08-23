defmodule SweBench.StaticAnalysis.QualityCalculator do
  @moduledoc """
  Calculates comprehensive quality metrics for code evaluation.

  Computes cyclomatic complexity, measures code duplication, assesses
  documentation coverage, evaluates naming conventions, and generates
  overall quality scores for the graduated scoring system.
  """

  require Logger

  @doc """
  Calculates comprehensive quality metrics for source code.

  ## Parameters
    - source_path: Path to the source code directory
    - static_analysis_results: Combined results from Credo and Dialyzer
    - opts: Calculation options and thresholds

  ## Returns
    - {:ok, quality_metrics} - Comprehensive quality metrics
    - {:error, reason} - Calculation error
  """
  def calculate_quality_metrics(source_path, static_analysis_results, opts \\ []) do
    Logger.info("Calculating comprehensive quality metrics for #{source_path}")

    with {:ok, complexity_metrics} <- calculate_complexity_metrics(source_path, opts),
         {:ok, duplication_metrics} <-
           measure_code_duplication(source_path, static_analysis_results, opts),
         {:ok, documentation_metrics} <- assess_documentation_coverage(source_path, opts),
         {:ok, naming_metrics} <-
           evaluate_naming_conventions(source_path, static_analysis_results, opts),
         {:ok, overall_score} <-
           compute_overall_quality_score(
             complexity_metrics,
             duplication_metrics,
             documentation_metrics,
             naming_metrics,
             static_analysis_results
           ) do
      quality_metrics = %{
        source_path: source_path,
        complexity_metrics: complexity_metrics,
        duplication_metrics: duplication_metrics,
        documentation_metrics: documentation_metrics,
        naming_metrics: naming_metrics,
        overall_quality_score: overall_score,
        static_analysis_integration: static_analysis_results,
        calculated_at: DateTime.utc_now()
      }

      Logger.info("Quality metrics calculation complete: overall score #{overall_score}")
      {:ok, quality_metrics}
    else
      {:error, reason} ->
        Logger.warning("Quality metrics calculation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.4.4.1: Calculate cyclomatic complexity
  defp calculate_complexity_metrics(source_path, opts) do
    Logger.debug("Calculating complexity metrics for #{source_path}")

    with {:ok, source_files} <- discover_source_files(source_path),
         {:ok, function_complexities} <- analyze_function_complexities(source_files, opts),
         {:ok, module_complexities} <- analyze_module_complexities(source_files, opts) do
      complexity_metrics = %{
        source_files_analyzed: length(source_files),
        function_complexities: function_complexities,
        module_complexities: module_complexities,
        average_function_complexity: calculate_average_complexity(function_complexities),
        max_function_complexity: calculate_max_complexity(function_complexities),
        complexity_distribution: calculate_complexity_distribution(function_complexities),
        complexity_score: calculate_complexity_score(function_complexities)
      }

      {:ok, complexity_metrics}
    end
  end

  defp discover_source_files(source_path) do
    lib_path = Path.join(source_path, "lib")

    if File.dir?(lib_path) do
      source_files = Path.wildcard(Path.join(lib_path, "**/*.ex"))
      {:ok, source_files}
    else
      {:ok, []}
    end
  end

  defp analyze_function_complexities(source_files, _opts) do
    function_complexities =
      source_files
      |> Enum.flat_map(&extract_functions_from_file/1)
      |> Enum.map(&calculate_function_complexity/1)

    {:ok, function_complexities}
  end

  defp extract_functions_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Code.string_to_quoted(content) do
          {:ok, ast} ->
            extract_functions_from_ast(ast, file_path)

          {:error, _} ->
            # Skip files that can't be parsed
            []
        end

      {:error, _} ->
        []
    end
  end

  defp extract_functions_from_ast(ast, file_path) do
    functions = find_function_definitions(ast)

    Enum.map(functions, fn {name, arity, definition} ->
      %{
        file_path: file_path,
        function_name: name,
        arity: arity,
        definition: definition
      }
    end)
  end

  defp find_function_definitions(ast) do
    find_in_ast(ast, fn
      {:def, _, [{name, _, args} | _]} = definition when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, definition}

      {:defp, _, [{name, _, args} | _]} = definition when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {name, arity, definition}

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

  defp calculate_function_complexity(function_info) do
    # Simple cyclomatic complexity calculation
    complexity = count_decision_points(function_info.definition) + 1

    %{
      file_path: function_info.file_path,
      function_name: function_info.function_name,
      arity: function_info.arity,
      cyclomatic_complexity: complexity,
      complexity_level: classify_complexity_level(complexity)
    }
  end

  defp count_decision_points({_, _, children}) when is_list(children) do
    Enum.sum(Enum.map(children, &count_decision_points/1))
  end

  defp count_decision_points({:if, _, _}), do: 1
  defp count_decision_points({:case, _, _}), do: 1
  defp count_decision_points({:cond, _, _}), do: 1
  defp count_decision_points({:with, _, _}), do: 1
  defp count_decision_points({:unless, _, _}), do: 1
  defp count_decision_points({:try, _, _}), do: 1
  defp count_decision_points(_), do: 0

  defp classify_complexity_level(complexity) do
    cond do
      complexity <= 5 -> :simple
      complexity <= 10 -> :moderate
      complexity <= 15 -> :complex
      true -> :very_complex
    end
  end

  defp analyze_module_complexities(source_files, _opts) do
    module_complexities =
      source_files
      |> Enum.map(&calculate_module_complexity/1)
      |> Enum.reject(&is_nil/1)

    {:ok, module_complexities}
  end

  defp calculate_module_complexity(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        lines_of_code = count_lines_of_code(content)
        function_count = count_functions_in_file(content)

        %{
          file_path: file_path,
          lines_of_code: lines_of_code,
          function_count: function_count,
          average_function_size:
            if(function_count > 0, do: lines_of_code / function_count, else: 0),
          module_complexity_score: calculate_module_score(lines_of_code, function_count)
        }

      {:error, _} ->
        nil
    end
  end

  defp count_lines_of_code(content) do
    content
    |> String.split("\n")
    |> Enum.count(fn line ->
      trimmed = String.trim(line)
      trimmed != "" and not String.starts_with?(trimmed, "#")
    end)
  end

  defp count_functions_in_file(content) do
    function_pattern = ~r/^\s*(def|defp)\s+\w+/m
    Regex.scan(function_pattern, content) |> length()
  end

  defp calculate_module_score(lines_of_code, function_count) do
    # Score based on module size and function organization
    base_score = 100

    # Penalize very large modules
    size_penalty =
      cond do
        lines_of_code > 500 -> 30
        lines_of_code > 300 -> 20
        lines_of_code > 200 -> 10
        true -> 0
      end

    # Penalize modules with too many functions
    function_penalty =
      cond do
        function_count > 20 -> 20
        function_count > 15 -> 10
        function_count > 10 -> 5
        true -> 0
      end

    max(0, base_score - size_penalty - function_penalty)
  end

  # Task 2.4.4.2: Measure code duplication
  defp measure_code_duplication(source_path, static_analysis_results, opts) do
    Logger.debug("Measuring code duplication for #{source_path}")

    # Extract duplication info from Credo results
    credo_duplication = extract_credo_duplication_metrics(static_analysis_results)

    # Perform additional duplication analysis if needed
    additional_analysis = Keyword.get(opts, :additional_duplication_analysis, false)

    duplication_metrics =
      if additional_analysis do
        with {:ok, source_files} <- discover_source_files(source_path),
             {:ok, token_analysis} <- analyze_token_duplication(source_files),
             {:ok, semantic_analysis} <- analyze_semantic_duplication(source_files) do
          merge_duplication_analyses(credo_duplication, token_analysis, semantic_analysis)
        else
          _ -> credo_duplication
        end
      else
        credo_duplication
      end

    {:ok, duplication_metrics}
  end

  defp extract_credo_duplication_metrics(static_analysis_results) do
    # Extract duplication information from Credo analysis
    case static_analysis_results do
      %{credo: %{parsed_results: %{summary: summary}}} ->
        %{
          duplicated_lines: Map.get(summary, :duplicated_lines, 0),
          duplication_score: calculate_duplication_score(Map.get(summary, :duplicated_lines, 0)),
          source: :credo_analysis
        }

      _ ->
        %{
          duplicated_lines: 0,
          duplication_score: 100,
          source: :fallback
        }
    end
  end

  defp calculate_duplication_score(duplicated_lines) do
    # Higher penalty for more duplication
    base_score = 100
    # 0.5 points per duplicated line, max 50
    penalty = min(50, duplicated_lines * 0.5)
    max(50, base_score - penalty)
  end

  defp analyze_token_duplication(_source_files) do
    # Placeholder for token-based duplication analysis
    # Would implement sophisticated token comparison in production
    {:ok,
     %{
       token_duplication_percentage: 0,
       duplicated_token_blocks: [],
       token_analysis_score: 100
     }}
  end

  defp analyze_semantic_duplication(_source_files) do
    # Placeholder for semantic duplication analysis
    # Would implement AST-based semantic comparison in production
    {:ok,
     %{
       semantic_duplication_percentage: 0,
       duplicated_semantic_blocks: [],
       semantic_analysis_score: 100
     }}
  end

  defp merge_duplication_analyses(credo_dup, token_dup, semantic_dup) do
    %{
      duplicated_lines: credo_dup.duplicated_lines,
      duplication_score: credo_dup.duplication_score,
      token_duplication: token_dup,
      semantic_duplication: semantic_dup,
      composite_duplication_score:
        calculate_composite_duplication_score(credo_dup, token_dup, semantic_dup)
    }
  end

  defp calculate_composite_duplication_score(credo_dup, token_dup, semantic_dup) do
    # Weighted combination of different duplication metrics
    weights = %{credo: 0.5, token: 0.3, semantic: 0.2}

    weighted_score =
      credo_dup.duplication_score * weights.credo +
        token_dup.token_analysis_score * weights.token +
        semantic_dup.semantic_analysis_score * weights.semantic

    round(weighted_score)
  end

  # Task 2.4.4.3: Assess documentation coverage
  defp assess_documentation_coverage(source_path, _opts) do
    Logger.debug("Assessing documentation coverage for #{source_path}")

    with {:ok, source_files} <- discover_source_files(source_path),
         {:ok, module_docs} <- analyze_module_documentation(source_files),
         {:ok, function_docs} <- analyze_function_documentation(source_files),
         {:ok, spec_coverage} <- analyze_spec_coverage(source_files) do
      documentation_metrics = %{
        modules_analyzed: length(source_files),
        module_documentation: module_docs,
        function_documentation: function_docs,
        spec_coverage: spec_coverage,
        overall_documentation_score:
          calculate_documentation_score(module_docs, function_docs, spec_coverage),
        documentation_completeness:
          assess_documentation_completeness(module_docs, function_docs, spec_coverage)
      }

      {:ok, documentation_metrics}
    end
  end

  defp analyze_module_documentation(source_files) do
    module_doc_analysis =
      source_files
      |> Enum.map(&check_module_documentation/1)
      |> Enum.reject(&is_nil/1)

    total_modules = length(module_doc_analysis)
    documented_modules = Enum.count(module_doc_analysis, & &1.has_moduledoc)

    %{
      total_modules: total_modules,
      documented_modules: documented_modules,
      documentation_percentage: calculate_percentage(documented_modules, total_modules),
      module_details: module_doc_analysis
    }
  end

  defp check_module_documentation(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        has_moduledoc = String.contains?(content, "@moduledoc")
        moduledoc_quality = assess_moduledoc_quality(content)

        %{
          file_path: file_path,
          has_moduledoc: has_moduledoc,
          moduledoc_quality: moduledoc_quality,
          estimated_doc_length: estimate_doc_length(content)
        }

      {:error, _} ->
        nil
    end
  end

  defp assess_moduledoc_quality(content) do
    cond do
      String.contains?(content, "@moduledoc false") -> :disabled
      String.contains?(content, "@moduledoc \"\"\"") -> :comprehensive
      String.contains?(content, "@moduledoc \"") -> :basic
      String.contains?(content, "@moduledoc") -> :present
      true -> :missing
    end
  end

  defp estimate_doc_length(content) do
    # Estimate documentation length from moduledoc content
    case Regex.run(~r/@moduledoc\s+"""(.*?)"""/s, content) do
      [_, doc_content] -> String.length(String.trim(doc_content))
      _ -> 0
    end
  end

  defp analyze_function_documentation(source_files) do
    function_doc_analysis =
      source_files
      |> Enum.flat_map(&extract_function_docs_from_file/1)

    total_functions = length(function_doc_analysis)
    documented_functions = Enum.count(function_doc_analysis, & &1.has_doc)

    %{
      total_functions: total_functions,
      documented_functions: documented_functions,
      documentation_percentage: calculate_percentage(documented_functions, total_functions),
      function_details: function_doc_analysis
    }
  end

  defp extract_function_docs_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Code.string_to_quoted(content) do
          {:ok, ast} ->
            extract_function_doc_info(ast, file_path)

          {:error, _} ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp extract_function_doc_info(ast, file_path) do
    # Extract function definitions and check for associated @doc
    functions = find_function_definitions(ast)
    doc_strings = find_doc_attributes(ast)

    Enum.map(functions, fn {name, arity, _definition} ->
      has_doc = function_has_doc?(name, doc_strings)

      %{
        file_path: file_path,
        function_name: name,
        arity: arity,
        has_doc: has_doc,
        # Simplified - would check def vs defp in production
        is_public: true
      }
    end)
  end

  defp find_doc_attributes(ast) do
    find_in_ast(ast, fn
      {:@, _, [{:doc, _, [doc_content]}]} -> doc_content
      _ -> nil
    end)
  end

  defp function_has_doc?(function_name, doc_strings) do
    # Simplified check - would be more sophisticated in production
    Enum.any?(doc_strings, fn doc ->
      is_binary(doc) and String.contains?(doc, Atom.to_string(function_name))
    end)
  end

  defp analyze_spec_coverage(source_files) do
    spec_analysis =
      source_files
      |> Enum.flat_map(&extract_specs_from_file/1)

    total_functions = count_total_functions(source_files)
    functions_with_specs = length(spec_analysis)

    %{
      total_functions: total_functions,
      functions_with_specs: functions_with_specs,
      spec_coverage_percentage: calculate_percentage(functions_with_specs, total_functions),
      spec_details: spec_analysis
    }
  end

  defp extract_specs_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Simple spec extraction - would be more sophisticated in production
        spec_count = Regex.scan(~r/@spec\s+\w+/, content) |> length()

        if spec_count > 0 do
          [
            %{
              file_path: file_path,
              spec_count: spec_count
            }
          ]
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  defp count_total_functions(source_files) do
    source_files
    |> Enum.map(&count_functions_in_file_content/1)
    |> Enum.sum()
  end

  defp count_functions_in_file_content(file_path) do
    case File.read(file_path) do
      {:ok, content} -> count_functions_in_content(content)
      {:error, _} -> 0
    end
  end

  defp count_functions_in_content(content) do
    function_pattern = ~r/^\s*(def|defp)\s+\w+/m
    Regex.scan(function_pattern, content) |> length()
  end

  # Task 2.4.4.4: Evaluate naming conventions
  defp evaluate_naming_conventions(source_path, static_analysis_results, _opts) do
    Logger.debug("Evaluating naming conventions for #{source_path}")

    # Extract naming-related warnings from static analysis
    naming_warnings = extract_naming_warnings(static_analysis_results)

    with {:ok, source_files} <- discover_source_files(source_path),
         {:ok, naming_analysis} <- analyze_naming_patterns(source_files),
         {:ok, convention_adherence} <-
           assess_convention_adherence(naming_analysis, naming_warnings) do
      naming_metrics = %{
        naming_warnings: naming_warnings,
        naming_analysis: naming_analysis,
        convention_adherence: convention_adherence,
        naming_score: calculate_naming_score(naming_warnings, convention_adherence),
        patterns_analyzed: count_naming_patterns(naming_analysis)
      }

      {:ok, naming_metrics}
    end
  end

  defp extract_naming_warnings(static_analysis_results) do
    # Extract naming-related warnings from Credo results
    case static_analysis_results do
      %{credo: %{categorized_issues: categorized}} ->
        all_issues =
          categorized.design ++
            categorized.readability ++
            categorized.refactor ++ categorized.warning ++ categorized.consistency

        naming_issues =
          all_issues
          |> Enum.filter(&naming_related_issue?/1)

        %{
          naming_issues: naming_issues,
          issue_count: length(naming_issues)
        }

      _ ->
        %{naming_issues: [], issue_count: 0}
    end
  end

  defp naming_related_issue?(issue) do
    check_name = issue.check || ""

    String.contains?(check_name, "Names") or
      String.contains?(check_name, "Naming") or
      String.contains?(check_name, "Variable") or
      String.contains?(check_name, "Function") or
      String.contains?(check_name, "Module")
  end

  defp analyze_naming_patterns(source_files) do
    naming_patterns =
      source_files
      |> Enum.flat_map(&extract_naming_patterns_from_file/1)

    %{
      module_names: filter_by_type(naming_patterns, :module),
      function_names: filter_by_type(naming_patterns, :function),
      variable_names: filter_by_type(naming_patterns, :variable),
      total_patterns: length(naming_patterns)
    }
  end

  defp extract_naming_patterns_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        patterns = []

        # Extract module names
        patterns = patterns ++ extract_module_names(content, file_path)

        # Extract function names
        patterns = patterns ++ extract_function_names(content, file_path)

        patterns

      {:error, _} ->
        []
    end
  end

  defp extract_module_names(content, file_path) do
    Regex.scan(~r/defmodule\s+([\w\.]+)/, content)
    |> Enum.map(fn [_, module_name] ->
      %{
        type: :module,
        name: module_name,
        file_path: file_path,
        follows_convention: module_name_follows_convention?(module_name)
      }
    end)
  end

  defp extract_function_names(content, file_path) do
    Regex.scan(~r/def[p]?\s+(\w+)/, content)
    |> Enum.map(fn [_, function_name] ->
      %{
        type: :function,
        name: function_name,
        file_path: file_path,
        follows_convention: function_name_follows_convention?(function_name)
      }
    end)
  end

  defp module_name_follows_convention?(name) do
    # Check PascalCase for modules
    Regex.match?(~r/^[A-Z][a-zA-Z0-9]*(\.[A-Z][a-zA-Z0-9]*)*$/, name)
  end

  defp function_name_follows_convention?(name) do
    # Check snake_case for functions
    Regex.match?(~r/^[a-z][a-z0-9_]*[?!]?$/, name)
  end

  defp filter_by_type(patterns, type) do
    Enum.filter(patterns, fn pattern -> pattern.type == type end)
  end

  defp assess_convention_adherence(naming_analysis, naming_warnings) do
    total_patterns = naming_analysis.total_patterns

    # Count convention violations
    module_violations = Enum.count(naming_analysis.module_names, &(not &1.follows_convention))
    function_violations = Enum.count(naming_analysis.function_names, &(not &1.follows_convention))
    warning_violations = naming_warnings.issue_count

    total_violations = module_violations + function_violations + warning_violations

    %{
      total_patterns: total_patterns,
      total_violations: total_violations,
      module_violations: module_violations,
      function_violations: function_violations,
      warning_violations: warning_violations,
      adherence_percentage: calculate_adherence_percentage(total_violations, total_patterns),
      adherence_level: classify_adherence_level(total_violations, total_patterns)
    }
  end

  defp calculate_adherence_percentage(violations, total) when total > 0 do
    (total - violations) / total * 100
  end

  defp calculate_adherence_percentage(_violations, 0), do: 100

  defp classify_adherence_level(violations, total) do
    percentage = calculate_adherence_percentage(violations, total)

    cond do
      percentage >= 95 -> :excellent
      percentage >= 85 -> :good
      percentage >= 70 -> :acceptable
      percentage >= 50 -> :needs_improvement
      true -> :poor
    end
  end

  defp calculate_naming_score(naming_warnings, convention_adherence) do
    base_score = 100

    # Penalty for naming warnings
    warning_penalty = min(30, naming_warnings.issue_count * 5)

    # Penalty based on adherence level
    adherence_penalty =
      case convention_adherence.adherence_level do
        :excellent -> 0
        :good -> 5
        :acceptable -> 15
        :needs_improvement -> 30
        :poor -> 50
      end

    max(0, base_score - warning_penalty - adherence_penalty)
  end

  defp count_naming_patterns(naming_analysis) do
    naming_analysis.total_patterns
  end

  # Task 2.4.4.5: Compute overall quality score
  defp compute_overall_quality_score(
         complexity_metrics,
         duplication_metrics,
         documentation_metrics,
         naming_metrics,
         static_analysis_results
       ) do
    # Weighted combination of all quality dimensions
    weights = %{
      complexity: 0.25,
      duplication: 0.15,
      documentation: 0.20,
      naming: 0.15,
      credo: 0.15,
      dialyzer: 0.10
    }

    credo_score = get_credo_score(static_analysis_results)
    dialyzer_score = get_dialyzer_score(static_analysis_results)

    weighted_score =
      complexity_metrics.complexity_score * weights.complexity +
        duplication_metrics.duplication_score * weights.duplication +
        documentation_metrics.overall_documentation_score * weights.documentation +
        naming_metrics.naming_score * weights.naming +
        credo_score * weights.credo +
        dialyzer_score * weights.dialyzer

    overall_score = round(weighted_score)

    {:ok, overall_score}
  end

  defp get_credo_score(static_analysis_results) do
    case static_analysis_results do
      %{credo: %{credo_score: score}} -> score
      _ -> 0
    end
  end

  defp get_dialyzer_score(static_analysis_results) do
    case static_analysis_results do
      %{dialyzer: %{type_safety_score: score}} -> score
      _ -> 0
    end
  end

  # Helper functions

  defp calculate_average_complexity(function_complexities) do
    if Enum.empty?(function_complexities) do
      0
    else
      total_complexity = Enum.sum(Enum.map(function_complexities, & &1.cyclomatic_complexity))
      total_complexity / length(function_complexities)
    end
  end

  defp calculate_max_complexity(function_complexities) do
    if Enum.empty?(function_complexities) do
      0
    else
      Enum.max(Enum.map(function_complexities, & &1.cyclomatic_complexity))
    end
  end

  defp calculate_complexity_distribution(function_complexities) do
    Enum.frequencies_by(function_complexities, & &1.complexity_level)
  end

  defp calculate_complexity_score(function_complexities) do
    case function_complexities do
      [] ->
        100

      functions when is_list(functions) ->
        calculate_weighted_complexity_score(functions)
    end
  end

  defp calculate_weighted_complexity_score(function_complexities) do
    # Score based on distribution of complexity levels
    distribution = calculate_complexity_distribution(function_complexities)

    simple_count = Map.get(distribution, :simple, 0)
    moderate_count = Map.get(distribution, :moderate, 0)
    complex_count = Map.get(distribution, :complex, 0)
    very_complex_count = Map.get(distribution, :very_complex, 0)

    total = length(function_complexities)

    weighted_sum =
      calculate_weighted_sum(simple_count, moderate_count, complex_count, very_complex_count)

    # Calculate final score with explicit division check
    final_score = calculate_normalized_complexity_score(weighted_sum, total)
    min(100, round(final_score))
  end

  defp calculate_normalized_complexity_score(weighted_sum, total) when total > 0 do
    weighted_sum / total * 25
  end

  defp calculate_normalized_complexity_score(_weighted_sum, _total), do: 0

  defp calculate_weighted_sum(simple_count, moderate_count, complex_count, very_complex_count) do
    simple_count * 4 + moderate_count * 3 + complex_count * 2 + very_complex_count
  end

  defp calculate_documentation_score(module_docs, function_docs, spec_coverage) do
    # Weighted documentation score
    module_weight = 0.4
    function_weight = 0.35
    spec_weight = 0.25

    module_score = module_docs.documentation_percentage
    function_score = function_docs.documentation_percentage
    spec_score = spec_coverage.spec_coverage_percentage

    weighted_score =
      module_score * module_weight +
        function_score * function_weight +
        spec_score * spec_weight

    round(weighted_score)
  end

  defp assess_documentation_completeness(module_docs, function_docs, spec_coverage) do
    %{
      module_completeness: classify_completeness(module_docs.documentation_percentage),
      function_completeness: classify_completeness(function_docs.documentation_percentage),
      spec_completeness: classify_completeness(spec_coverage.spec_coverage_percentage),
      overall_completeness:
        classify_completeness(
          (module_docs.documentation_percentage + function_docs.documentation_percentage +
             spec_coverage.spec_coverage_percentage) / 3
        )
    }
  end

  defp classify_completeness(percentage) do
    cond do
      percentage >= 90 -> :excellent
      percentage >= 75 -> :good
      percentage >= 50 -> :adequate
      percentage >= 25 -> :insufficient
      true -> :missing
    end
  end

  defp calculate_percentage(count, total) when total > 0, do: count / total * 100
  defp calculate_percentage(_count, 0), do: 0

  @doc """
  Generates comprehensive quality metrics report.
  """
  def generate_quality_report(quality_metrics) do
    report = %{
      summary: %{
        overall_quality_score: quality_metrics.overall_quality_score,
        complexity_score: quality_metrics.complexity_metrics.complexity_score,
        duplication_score: quality_metrics.duplication_metrics.duplication_score,
        documentation_score: quality_metrics.documentation_metrics.overall_documentation_score,
        naming_score: quality_metrics.naming_metrics.naming_score
      },
      detailed_metrics: %{
        complexity_analysis: quality_metrics.complexity_metrics,
        duplication_analysis: quality_metrics.duplication_metrics,
        documentation_analysis: quality_metrics.documentation_metrics,
        naming_analysis: quality_metrics.naming_metrics
      },
      recommendations: generate_quality_recommendations(quality_metrics),
      quality_grade: classify_overall_quality(quality_metrics.overall_quality_score),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp generate_quality_recommendations(quality_metrics) do
    recommendations = []

    recommendations =
      if quality_metrics.complexity_metrics.complexity_score < 70 do
        [
          "Reduce function complexity - current complexity score: #{quality_metrics.complexity_metrics.complexity_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if quality_metrics.duplication_metrics.duplication_score < 80 do
        [
          "Address code duplication - current duplication score: #{quality_metrics.duplication_metrics.duplication_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if quality_metrics.documentation_metrics.overall_documentation_score < 70 do
        [
          "Improve documentation coverage - current score: #{quality_metrics.documentation_metrics.overall_documentation_score}"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if quality_metrics.naming_metrics.naming_score < 80 do
        [
          "Review naming conventions - current score: #{quality_metrics.naming_metrics.naming_score}"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Code quality metrics indicate excellent adherence to Elixir best practices"]
    else
      recommendations
    end
  end

  defp classify_overall_quality(score) do
    cond do
      score >= 90 -> :excellent
      score >= 80 -> :good
      score >= 70 -> :acceptable
      score >= 60 -> :needs_improvement
      true -> :poor
    end
  end
end
