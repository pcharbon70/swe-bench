defmodule SweBench.PartialCreditScoring.ImprovementSuggester do
  @moduledoc """
  Generates actionable improvement suggestions based on comprehensive analysis.

  Provides targeted feedback based on error categorization, solution analysis,
  and scoring results to guide model improvement efforts.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the improvement suggester with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Generates improvement suggestions based on comprehensive scoring analysis.
  """
  def generate_suggestions(scoring_result, options \\ []) do
    GenServer.call(__MODULE__, {:generate_suggestions, scoring_result, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("ImprovementSuggester initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_suggestions, scoring_result, _options}, _from, state) do
    suggestions = perform_suggestion_generation(scoring_result, state.config)
    {:reply, {:ok, suggestions}, state}
  rescue
    error ->
      Logger.error("Suggestion generation failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_suggestion_generation(scoring_result, config) do
    dimension_scores = Map.get(scoring_result, :dimension_scores, %{})
    overall_score = Map.get(scoring_result, :overall_score, 0.0)
    score_category = Map.get(scoring_result, :score_category, :insufficient)

    %{
      priority_suggestions: generate_priority_suggestions(dimension_scores, config),
      dimension_specific: generate_dimension_suggestions(dimension_scores),
      strategic_recommendations:
        generate_strategic_recommendations(overall_score, score_category),
      next_steps: generate_next_steps(scoring_result),
      learning_resources: suggest_learning_resources(dimension_scores)
    }
  end

  defp generate_priority_suggestions(dimension_scores, config) do
    # Find dimensions below threshold and prioritize by impact
    failing_dimensions =
      dimension_scores
      |> Enum.filter(fn {dimension, result} ->
        threshold = get_in(config, [:dimensions, dimension, :threshold]) || 50
        score = Map.get(result, :score, 0.0)
        score < threshold
      end)
      |> Enum.sort_by(
        fn {dimension, result} ->
          weight = get_in(config, [:dimensions, dimension, :weight]) || 0.0
          score = Map.get(result, :score, 0.0)
          # Higher weight and lower score = higher priority
          weight * (100.0 - score)
        end,
        :desc
      )
      # Top 3 priority areas
      |> Enum.take(3)

    Enum.map(failing_dimensions, fn {dimension, result} ->
      threshold = get_in(config, [:dimensions, dimension, :threshold]) || 50
      score = Map.get(result, :score, 0.0)
      gap = threshold - score

      %{
        dimension: dimension,
        current_score: score,
        target_threshold: threshold,
        improvement_needed: gap,
        impact: get_in(config, [:dimensions, dimension, :weight]) || 0.0,
        suggestion: generate_dimension_priority_suggestion(dimension, result, gap)
      }
    end)
  end

  defp generate_dimension_priority_suggestion(:compilation, result, gap) do
    error = Map.get(result, :error)

    if error do
      "Fix compilation errors: #{inspect(error)}. Focus on syntax and type correctness."
    else
      "Improve compilation success rate by #{Float.round(gap, 1)}%. Review syntax and dependencies."
    end
  end

  defp generate_dimension_priority_suggestion(:partial_tests, result, gap) do
    details = Map.get(result, :details, %{})
    failed_tests = Map.get(details, :failed_tests, 0)

    if failed_tests > 0 do
      "#{failed_tests} tests failing. Improve test pass rate by #{Float.round(gap, 1)}%. Review test logic and edge cases."
    else
      "Increase test coverage and pass rate by #{Float.round(gap, 1)}%."
    end
  end

  defp generate_dimension_priority_suggestion(:code_quality, result, gap) do
    details = Map.get(result, :details, %{})
    dialyzer_issues = Map.get(details, :dialyzer_issues, 0)

    if dialyzer_issues > 0 do
      "Address #{dialyzer_issues} type issues. Improve code quality by #{Float.round(gap, 1)}% through better typing and static analysis."
    else
      "Enhance code quality by #{Float.round(gap, 1)}%. Focus on style, documentation, and static analysis improvements."
    end
  end

  defp generate_dimension_priority_suggestion(:performance, result, gap) do
    details = Map.get(result, :details, %{})

    "Optimize performance by #{Float.round(gap, 1)}%. Review algorithmic complexity and data structure choices. " <>
      "Current scores - Execution: #{Map.get(details, :execution_score, 0)} Memory: #{Map.get(details, :memory_score, 0)}"
  end

  defp generate_dimension_priority_suggestion(:functional_programming, result, gap) do
    details = Map.get(result, :details, %{})
    fp_patterns = Map.get(details, :fp_patterns, %{})

    missing_patterns =
      fp_patterns
      |> Enum.filter(fn {_pattern, used} -> not used end)
      |> Enum.map(fn {pattern, _} -> pattern end)
      |> Enum.take(3)

    "Improve functional programming adherence by #{Float.round(gap, 1)}%. Focus on: #{Enum.join(missing_patterns, ", ")}"
  end

  defp generate_dimension_suggestions(dimension_scores) do
    Enum.reduce(dimension_scores, %{}, fn {dimension, result}, acc ->
      suggestions =
        case dimension do
          :compilation -> suggest_compilation_improvements(result)
          :partial_tests -> suggest_test_improvements(result)
          :code_quality -> suggest_quality_improvements(result)
          :performance -> suggest_performance_improvements(result)
          :functional_programming -> suggest_fp_improvements(result)
          _ -> []
        end

      Map.put(acc, dimension, suggestions)
    end)
  end

  defp suggest_compilation_improvements(result) do
    case Map.get(result, :status) do
      :failed ->
        error = Map.get(result, :error)
        ["Fix compilation error: #{inspect(error)}", "Review syntax and module dependencies"]

      :success ->
        score = Map.get(result, :score, 0.0)

        if score < 100.0 do
          ["Address remaining compilation warnings", "Improve type specifications"]
        else
          ["Compilation successful - maintain code quality"]
        end
    end
  end

  defp suggest_test_improvements(result) do
    details = Map.get(result, :details, %{})
    failed_tests = Map.get(details, :failed_tests, 0)
    pass_rate = Map.get(details, :pass_rate, 0.0)

    suggestions = []

    suggestions =
      if failed_tests > 0 do
        [
          "Investigate #{failed_tests} failing tests",
          "Review test assertions and expected outputs" | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if pass_rate < 100.0 do
        [
          "Improve test pass rate from #{Float.round(pass_rate, 1)}% to 100%",
          "Handle edge cases in test scenarios" | suggestions
        ]
      else
        ["All tests passing - excellent!" | suggestions]
      end

    suggestions
  end

  defp suggest_quality_improvements(result) do
    details = Map.get(result, :details, %{})
    credo_score = Map.get(details, :credo_score, 50.0)
    dialyzer_issues = Map.get(details, :dialyzer_issues, 0)

    suggestions = []

    suggestions =
      if credo_score < 80.0 do
        [
          "Improve Credo score from #{Float.round(credo_score, 1)} to 80+",
          "Address code style and complexity issues" | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if dialyzer_issues > 0 do
        [
          "Fix #{dialyzer_issues} Dialyzer type issues",
          "Add comprehensive type specifications" | suggestions
        ]
      else
        suggestions
      end

    if suggestions == [] do
      ["Code quality is good - maintain standards"]
    else
      suggestions
    end
  end

  defp suggest_performance_improvements(result) do
    details = Map.get(result, :details, %{})
    execution_score = Map.get(details, :execution_score, 50.0)
    memory_score = Map.get(details, :memory_score, 50.0)
    scalability_score = Map.get(details, :scalability_score, 50.0)

    suggestions = []

    suggestions =
      if execution_score < 70.0 do
        [
          "Optimize algorithm for better execution time",
          "Consider more efficient data structures" | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if memory_score < 70.0 do
        [
          "Reduce memory usage through better data handling",
          "Avoid unnecessary data copies" | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if scalability_score < 70.0 do
        [
          "Improve algorithmic complexity for better scalability",
          "Consider streaming or lazy evaluation" | suggestions
        ]
      else
        suggestions
      end

    if suggestions == [] do
      ["Performance is adequate - consider micro-optimizations"]
    else
      suggestions
    end
  end

  defp suggest_fp_improvements(result) do
    details = Map.get(result, :details, %{})
    fp_patterns = Map.get(details, :fp_patterns, %{})

    suggestions = []

    suggestions =
      if Map.get(fp_patterns, :immutable_structures, false) do
        suggestions
      else
        ["Use immutable data structures instead of mutable ones" | suggestions]
      end

    suggestions =
      if Map.get(fp_patterns, :pattern_matching, false) do
        suggestions
      else
        ["Leverage pattern matching for cleaner code" | suggestions]
      end

    suggestions =
      if Map.get(fp_patterns, :pipe_operators, false) do
        suggestions
      else
        ["Use pipe operators |> for better data flow" | suggestions]
      end

    suggestions =
      if Map.get(fp_patterns, :pure_functions, false) do
        suggestions
      else
        ["Write pure functions without side effects" | suggestions]
      end

    if suggestions == [] do
      ["Functional programming patterns are well used"]
    else
      suggestions
    end
  end

  defp generate_strategic_recommendations(_overall_score, score_category) do
    case score_category do
      :excellent ->
        [
          "Excellent work! Focus on maintaining high standards",
          "Consider contributing to open source projects",
          "Explore advanced optimization techniques"
        ]

      :good ->
        [
          "Good foundation. Focus on consistency across all dimensions",
          "Target specific weak areas for improvement",
          "Consider code review practices"
        ]

      :partial ->
        [
          "Partial understanding demonstrated. Focus on completeness",
          "Strengthen test-driven development practices",
          "Improve error handling and edge case coverage"
        ]

      :minimal ->
        [
          "Basic functionality needs significant improvement",
          "Focus on fundamental programming concepts",
          "Practice with simpler problems first"
        ]

      :insufficient ->
        [
          "Start with basic compilation and syntax correctness",
          "Review fundamental programming concepts",
          "Seek mentorship or additional learning resources"
        ]
    end
  end

  defp generate_next_steps(scoring_result) do
    overall_score = Map.get(scoring_result, :overall_score, 0.0)

    cond do
      overall_score >= 90.0 ->
        [
          "Maintain current quality level",
          "Focus on advanced optimization",
          "Contribute to community projects"
        ]

      overall_score >= 75.0 ->
        [
          "Address remaining quality gaps",
          "Strengthen test coverage",
          "Focus on performance optimization"
        ]

      overall_score >= 50.0 ->
        [
          "Complete partial implementations",
          "Improve test pass rates",
          "Address compilation issues"
        ]

      overall_score >= 25.0 ->
        [
          "Fix compilation errors first",
          "Implement basic functionality",
          "Focus on problem understanding"
        ]

      true ->
        [
          "Start with syntax correctness",
          "Review problem requirements carefully",
          "Seek additional learning resources"
        ]
    end
  end

  defp suggest_learning_resources(dimension_scores) do
    resources = %{}

    resources =
      if needs_improvement?(dimension_scores, :compilation) do
        Map.put(resources, :compilation, [
          "Elixir Getting Started Guide",
          "Elixir School - Basics",
          "Programming Elixir by Dave Thomas"
        ])
      else
        resources
      end

    resources =
      if needs_improvement?(dimension_scores, :functional_programming) do
        Map.put(resources, :functional_programming, [
          "Functional Programming in Elixir",
          "Learn You Some Erlang (BEAM VM concepts)",
          "Elixir in Action by Saša Jurić"
        ])
      else
        resources
      end

    resources =
      if needs_improvement?(dimension_scores, :performance) do
        Map.put(resources, :performance, [
          "Benchee documentation",
          "Elixir Performance Optimization",
          "BEAM VM Performance Tuning"
        ])
      else
        resources
      end

    resources
  end

  defp needs_improvement?(dimension_scores, dimension) do
    case Map.get(dimension_scores, dimension) do
      nil -> false
      result -> Map.get(result, :score, 100.0) < 70.0
    end
  end
end
