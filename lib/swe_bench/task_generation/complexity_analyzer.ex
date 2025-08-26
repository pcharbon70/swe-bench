defmodule SweBench.TaskGeneration.ComplexityAnalyzer do
  @moduledoc """
  Complexity analysis for task instances.

  Implements sophisticated complexity assessment using code metrics,
  change analysis, and integration with existing quality infrastructure.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Analyzes complexity metrics for a task instance.
  """
  def analyze_complexity(task_data) do
    GenServer.call(__MODULE__, {:analyze_complexity, task_data})
  end

  @doc """
  Gets complexity analysis statistics.
  """
  def get_analysis_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      analyses_completed: 0,
      avg_complexity_score: 0.0,
      complexity_distribution: %{easy: 0, medium: 0, hard: 0, expert: 0}
    }

    Logger.info("Complexity analyzer started")
    {:ok, state}
  end

  @impl true
  def handle_call({:analyze_complexity, task_data}, _from, state) do
    result =
      task_data
      |> calculate_code_complexity()
      |> assess_solution_complexity()
      |> estimate_resolution_difficulty()
      |> compile_complexity_metrics()

    updated_state = update_complexity_stats(state, result, 0)
    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp calculate_code_complexity(task_data) do
    Logger.debug("Calculating code complexity for task #{task_data.instance_id}")

    complexity_metrics = %{
      lines_modified: count_modified_lines(task_data.patch_content),
      files_affected: count_affected_files(task_data.patch_content),
      functions_changed: estimate_functions_changed(task_data.patch_content),
      cyclomatic_complexity: estimate_cyclomatic_complexity(task_data.patch_content),
      ast_depth_change: estimate_ast_depth_change(task_data.patch_content)
    }

    {:ok, Map.put(task_data, :code_complexity, complexity_metrics)}
  end

  defp assess_solution_complexity({:ok, task_data}) do
    Logger.debug("Assessing solution complexity")

    solution_metrics = %{
      conceptual_difficulty: assess_conceptual_difficulty(task_data),
      technical_difficulty: assess_technical_difficulty(task_data),
      domain_knowledge_required: assess_domain_knowledge(task_data),
      debugging_complexity: assess_debugging_complexity(task_data)
    }

    {:ok, Map.put(task_data, :solution_complexity, solution_metrics)}
  end

  # Remove unused error clause - placeholder for future error handling
  # defp assess_solution_complexity({:error, reason}) do
  #   {:error, reason}
  # end

  defp estimate_resolution_difficulty({:ok, task_data}) do
    Logger.debug("Estimating resolution difficulty")

    # Calculate overall difficulty based on multiple factors
    difficulty_factors = [
      task_data.code_complexity.lines_modified / 100.0,
      task_data.code_complexity.files_affected / 5.0,
      task_data.solution_complexity.conceptual_difficulty,
      task_data.solution_complexity.technical_difficulty
    ]

    average_difficulty = Enum.sum(difficulty_factors) / length(difficulty_factors)

    difficulty_level =
      case average_difficulty do
        d when d <= 0.25 -> :easy
        d when d <= 0.50 -> :medium
        d when d <= 0.75 -> :hard
        _ -> :expert
      end

    estimated_time = estimate_resolution_time(difficulty_level, task_data.code_complexity)

    difficulty_assessment = %{
      difficulty_level: difficulty_level,
      difficulty_score: average_difficulty,
      estimated_resolution_time: estimated_time,
      confidence: calculate_difficulty_confidence(difficulty_factors)
    }

    {:ok, Map.put(task_data, :difficulty_assessment, difficulty_assessment)}
  end

  # Remove unused error clause - placeholder for future error handling
  # defp estimate_resolution_difficulty({:error, reason}) do
  #   {:error, reason}
  # end

  defp compile_complexity_metrics({:ok, task_data}) do
    complexity_analysis = %{
      code_metrics: task_data.code_complexity,
      solution_metrics: task_data.solution_complexity,
      difficulty_level: task_data.difficulty_assessment.difficulty_level,
      difficulty_score: task_data.difficulty_assessment.difficulty_score,
      estimated_time: task_data.difficulty_assessment.estimated_resolution_time,
      analysis_confidence: task_data.difficulty_assessment.confidence,
      analysis_metadata: %{
        analyzer_version: "1.0.0",
        analyzed_at: DateTime.utc_now()
      }
    }

    {:ok, complexity_analysis}
  end

  # Remove unused error clause - placeholder for future error handling
  # defp compile_complexity_metrics({:error, reason}) do
  #   {:error, reason}
  # end

  # Helper functions for complexity calculation

  defp count_modified_lines(patch_content) do
    lines = String.split(patch_content, "\n")
    additions = Enum.count(lines, &String.starts_with?(&1, "+"))
    deletions = Enum.count(lines, &String.starts_with?(&1, "-"))
    additions + deletions
  end

  defp count_affected_files(patch_content) do
    patch_content
    |> String.split("\n")
    |> Enum.count(&String.starts_with?(&1, "diff --git"))
  end

  defp estimate_functions_changed(patch_content) do
    # Count function definition changes
    patch_content
    |> String.split("\n")
    |> Enum.count(&String.match?(&1, ~r/[+-].*def\s+\w+/))
  end

  defp estimate_cyclomatic_complexity(patch_content) do
    # Estimate complexity based on control flow keywords
    complexity_keywords = ["if", "case", "cond", "try", "receive"]

    complexity_count =
      complexity_keywords
      |> Enum.map(fn keyword ->
        Regex.scan(~r/[+-].*#{keyword}\s/, patch_content) |> length()
      end)
      |> Enum.sum()

    max(1, complexity_count)
  end

  defp estimate_ast_depth_change(patch_content) do
    # Estimate AST depth impact - placeholder implementation
    nested_constructs = Regex.scan(~r/[+-].*\s{2,}/, patch_content) |> length()
    min(10, nested_constructs)
  end

  defp assess_conceptual_difficulty(task_data) do
    # Assess how conceptually challenging the problem is
    problem_indicators = [
      String.contains?(task_data.problem_statement, "performance"),
      String.contains?(task_data.problem_statement, "concurrent"),
      String.contains?(task_data.problem_statement, "distributed"),
      String.contains?(task_data.problem_statement, "memory")
    ]

    difficulty_score = Enum.count(problem_indicators, & &1) / length(problem_indicators)
    difficulty_score
  end

  defp assess_technical_difficulty(task_data) do
    # Assess technical implementation difficulty
    code_complexity = task_data.code_complexity

    technical_factors = [
      code_complexity.functions_changed / 10.0,
      code_complexity.files_affected / 5.0,
      code_complexity.cyclomatic_complexity / 20.0
    ]

    Enum.sum(technical_factors) / length(technical_factors)
  end

  defp assess_domain_knowledge(task_data) do
    # Assess required domain knowledge
    domain_keywords = ["GenServer", "Supervisor", "Phoenix", "Ecto", "LiveView"]

    domain_complexity =
      domain_keywords
      |> Enum.count(&String.contains?(task_data.patch_content, &1))

    min(1.0, domain_complexity / 3.0)
  end

  defp assess_debugging_complexity(task_data) do
    # Assess debugging difficulty based on error patterns
    debugging_indicators = [
      String.contains?(task_data.problem_statement, "error"),
      String.contains?(task_data.problem_statement, "crash"),
      String.contains?(task_data.problem_statement, "exception"),
      String.contains?(task_data.problem_statement, "timeout")
    ]

    Enum.count(debugging_indicators, & &1) / length(debugging_indicators)
  end

  defp estimate_resolution_time(difficulty_level, code_complexity) do
    base_time =
      case difficulty_level do
        # 20 minutes
        :easy -> 20
        # 45 minutes
        :medium -> 45
        # 1.5 hours
        :hard -> 90
        # 3 hours
        :expert -> 180
      end

    # Adjust based on code complexity
    complexity_multiplier = 1.0 + code_complexity.lines_modified / 200.0
    round(base_time * complexity_multiplier)
  end

  defp calculate_difficulty_confidence(difficulty_factors) do
    # Calculate confidence in difficulty assessment
    variance = calculate_variance(difficulty_factors)
    confidence = max(0.5, 1.0 - variance)
    confidence
  end

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)

    variance =
      values
      |> Enum.map(&((&1 - mean) * (&1 - mean)))
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  # Remove unused function - placeholder for future implementation
  # defp extract_file_path(diff_line) do
  #   case Regex.run(~r/diff --git a\/(.+) b\//, diff_line) do
  #     [_full, file_path] -> file_path
  #     _ -> "unknown"
  #   end
  # end

  defp update_complexity_stats(state, result, processing_time) do
    new_total = state.analyses_completed + 1

    {new_successful, new_failed} =
      case result do
        {:ok, _} -> {state.successful_analyses + 1, state.failed_analyses}
        {:error, _} -> {state.successful_analyses, state.failed_analyses + 1}
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_analysis_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | analyses_completed: new_total,
        successful_analyses: new_successful,
        failed_analyses: new_failed,
        avg_analysis_time: new_avg_time
    }
  end
end
