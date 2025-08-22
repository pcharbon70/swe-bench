defmodule SweBench.RepositorySetup.TaskExtractor do
  @moduledoc """
  Task instance extraction from repository issues and pull requests.

  Analyzes GitHub repository data to extract high-quality evaluation
  tasks with proper categorization and validation.
  """

  require Logger

  # alias SweBench.Issues.Collector - for future GitHub integration
  # alias SweBench.GitHub.Client - for future GitHub integration

  @doc """
  Extracts sample evaluation tasks from a repository.
  """
  def extract_sample_tasks(repository_name, repository_path, count \\ 10) do
    Logger.info("Extracting #{count} sample tasks from #{repository_name}")

    with {:ok, github_data} <- collect_github_data(repository_name),
         {:ok, task_candidates} <- analyze_task_candidates(github_data),
         {:ok, selected_tasks} <- select_best_tasks(task_candidates, count),
         {:ok, validated_tasks} <- validate_task_quality(selected_tasks, repository_path) do
      extraction_result = %{
        repository: repository_name,
        requested_count: count,
        extracted_count: length(validated_tasks),
        tasks: validated_tasks,
        quality_distribution: calculate_quality_distribution(validated_tasks),
        extracted_at: DateTime.utc_now()
      }

      Logger.info(
        "Task extraction complete: #{length(validated_tasks)}/#{count} tasks for #{repository_name}"
      )

      {:ok, extraction_result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes issue-PR pairs for task quality and complexity.
  """
  def analyze_task_candidates(github_data) do
    Logger.debug("Analyzing task candidates from GitHub data")

    linked_issues_prs = github_data.linked_issues_prs || []

    candidates =
      Enum.map(linked_issues_prs, fn issue_pr_pair ->
        analyze_single_task_candidate(issue_pr_pair)
      end)
      |> Enum.filter(&(&1.quality_score >= 60))
      |> Enum.sort_by(& &1.quality_score, :desc)

    {:ok, candidates}
  end

  @doc """
  Selects the best tasks based on quality and diversity criteria.
  """
  def select_best_tasks(candidates, target_count) do
    Logger.debug("Selecting #{target_count} best tasks from #{length(candidates)} candidates")

    # Ensure diversity across complexity levels
    complexity_targets = %{
      simple: round(target_count * 0.3),
      medium: round(target_count * 0.5),
      complex: round(target_count * 0.2)
    }

    selected_tasks = select_tasks_by_complexity(candidates, complexity_targets)

    # Fill remaining slots with highest quality regardless of complexity
    remaining_count = target_count - length(selected_tasks)

    if remaining_count > 0 do
      additional_tasks =
        candidates
        |> Enum.reject(fn task -> task in selected_tasks end)
        |> Enum.take(remaining_count)

      {:ok, selected_tasks ++ additional_tasks}
    else
      {:ok, Enum.take(selected_tasks, target_count)}
    end
  end

  @doc """
  Validates task quality and ensures evaluation compatibility.
  """
  def validate_task_quality(tasks, repository_path) do
    Logger.debug("Validating #{length(tasks)} tasks for evaluation compatibility")

    validated_tasks =
      Enum.filter(tasks, fn task ->
        validate_single_task(task, repository_path)
      end)

    {:ok, validated_tasks}
  end

  @doc """
  Calculates quality distribution statistics for extracted tasks.
  """
  def calculate_quality_distribution(tasks) do
    complexity_counts = Enum.frequencies_by(tasks, & &1.complexity)
    quality_scores = Enum.map(tasks, & &1.quality_score)

    %{
      complexity_distribution: complexity_counts,
      average_quality_score: average(quality_scores),
      quality_range:
        {Enum.min(quality_scores, fn -> 0 end), Enum.max(quality_scores, fn -> 0 end)},
      total_tasks: length(tasks)
    }
  end

  # Private helper functions

  defp collect_github_data(repository_name) do
    # Placeholder for GitHub data collection
    # Would integrate with SweBench.Issues.Collector in production
    sample_data = %{
      linked_issues_prs: generate_sample_issue_pr_pairs(repository_name)
    }

    {:ok, sample_data}
  end

  defp generate_sample_issue_pr_pairs(repository_name) do
    # Generate sample data based on repository type
    case repository_name do
      "phoenix" -> generate_phoenix_sample_tasks()
      "ecto" -> generate_ecto_sample_tasks()
      "jason" -> generate_jason_sample_tasks()
      "tesla" -> generate_tesla_sample_tasks()
      "credo" -> generate_credo_sample_tasks()
      _ -> []
    end
  end

  defp analyze_single_task_candidate(issue_pr_pair) do
    %{
      issue_number: issue_pr_pair.issue_number || 1,
      pr_number: issue_pr_pair.pr_number || 1,
      title: issue_pr_pair.title || "Sample task",
      complexity: determine_task_complexity(issue_pr_pair),
      quality_score: calculate_task_quality_score(issue_pr_pair),
      test_modifications: issue_pr_pair.test_modifications || [],
      difficulty_indicators: extract_difficulty_indicators(issue_pr_pair)
    }
  end

  defp select_tasks_by_complexity(candidates, complexity_targets) do
    grouped_by_complexity = Enum.group_by(candidates, & &1.complexity)

    selected = []

    selected =
      selected ++ Enum.take(grouped_by_complexity[:simple] || [], complexity_targets.simple)

    selected =
      selected ++ Enum.take(grouped_by_complexity[:medium] || [], complexity_targets.medium)

    selected =
      selected ++ Enum.take(grouped_by_complexity[:complex] || [], complexity_targets.complex)

    selected
  end

  defp validate_single_task(task, _repository_path) do
    # Validation criteria for evaluation tasks
    task.quality_score >= 60 &&
      task.test_modifications != [] &&
      String.length(task.title) > 10
  end

  defp determine_task_complexity(issue_pr_pair) do
    # Simplified complexity determination
    cond do
      length(issue_pr_pair.test_modifications || []) > 5 -> :complex
      length(issue_pr_pair.test_modifications || []) > 2 -> :medium
      true -> :simple
    end
  end

  defp calculate_task_quality_score(issue_pr_pair) do
    base_score = 50

    # Add points for various quality indicators
    score = base_score

    score =
      if issue_pr_pair.test_modifications && length(issue_pr_pair.test_modifications) > 0,
        do: score + 20,
        else: score

    score = if String.length(issue_pr_pair.title || "") > 20, do: score + 10, else: score
    score = if String.length(issue_pr_pair.description || "") > 100, do: score + 15, else: score
    score = if issue_pr_pair.has_clear_reproduction_steps, do: score + 15, else: score

    min(100, score)
  end

  defp extract_difficulty_indicators(issue_pr_pair) do
    indicators = []

    indicators =
      if issue_pr_pair.test_modifications && length(issue_pr_pair.test_modifications) > 3,
        do: [:multiple_test_files | indicators],
        else: indicators

    indicators =
      if String.contains?(issue_pr_pair.title || "", "performance"),
        do: [:performance_issue | indicators],
        else: indicators

    indicators =
      if String.contains?(issue_pr_pair.title || "", "regression"),
        do: [:regression | indicators],
        else: indicators

    indicators
  end

  defp generate_phoenix_sample_tasks do
    [
      %{
        issue_number: 101,
        pr_number: 102,
        title: "Fix LiveView form validation",
        test_modifications: ["test/live_view_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 201,
        pr_number: 202,
        title: "Improve WebSocket connection handling",
        test_modifications: ["test/socket_test.exs", "test/transport_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 301,
        pr_number: 302,
        title: "Add Phoenix.Component attribute validation",
        test_modifications: ["test/component_test.exs"],
        has_clear_reproduction_steps: false
      }
    ]
  end

  defp generate_ecto_sample_tasks do
    [
      %{
        issue_number: 401,
        pr_number: 402,
        title: "Fix schema association preloading",
        test_modifications: ["test/association_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 501,
        pr_number: 502,
        title: "Improve query optimization for complex joins",
        test_modifications: ["test/query_test.exs", "test/optimization_test.exs"],
        has_clear_reproduction_steps: true
      }
    ]
  end

  defp generate_jason_sample_tasks do
    [
      %{
        issue_number: 601,
        pr_number: 602,
        title: "Fix JSON encoding for nested maps",
        test_modifications: ["test/encode_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 701,
        pr_number: 702,
        title: "Improve error handling for invalid JSON",
        test_modifications: ["test/decode_test.exs"],
        has_clear_reproduction_steps: true
      }
    ]
  end

  defp generate_tesla_sample_tasks do
    [
      %{
        issue_number: 801,
        pr_number: 802,
        title: "Fix middleware error propagation",
        test_modifications: ["test/middleware_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 901,
        pr_number: 902,
        title: "Add adapter connection pooling",
        test_modifications: ["test/adapter_test.exs", "test/pool_test.exs"],
        has_clear_reproduction_steps: false
      }
    ]
  end

  defp generate_credo_sample_tasks do
    [
      %{
        issue_number: 1001,
        pr_number: 1002,
        title: "Fix AST traversal for nested modules",
        test_modifications: ["test/ast_test.exs"],
        has_clear_reproduction_steps: true
      },
      %{
        issue_number: 1101,
        pr_number: 1102,
        title: "Improve performance for large codebases",
        test_modifications: ["test/performance_test.exs"],
        has_clear_reproduction_steps: true
      }
    ]
  end

  defp average([]), do: 0

  defp average(numbers) do
    Enum.sum(numbers) / length(numbers)
  end
end
