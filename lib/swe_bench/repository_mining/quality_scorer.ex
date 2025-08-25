defmodule SweBench.RepositoryMining.QualityScorer do
  @moduledoc """
  Multi-dimensional repository quality assessment.

  Calculates comprehensive quality scores across code quality, community health,
  technical complexity, and maintenance activity dimensions using functional
  programming patterns.
  """

  require Logger

  @doc """
  Calculates comprehensive quality scores for a repository.

  ## Parameters
    - repository_data: Repository information from GitHub/Hex.pm

  ## Returns
    - {:ok, quality_scores} - Multi-dimensional quality assessment
    - {:error, reason} - Assessment error details
  """
  def calculate_quality_scores(repository_data) do
    Logger.debug("Calculating quality scores for: #{repository_data.full_name}")

    try do
      quality_scores = %{
        code_quality_score: score_code_quality(repository_data),
        community_health_score: score_community_health(repository_data),
        technical_complexity_score: score_technical_complexity(repository_data),
        maintenance_activity_score: score_maintenance_activity(repository_data)
      }

      overall_score = calculate_weighted_overall_score(quality_scores)

      final_scores = Map.put(quality_scores, :overall_score, overall_score)

      {:ok, final_scores}
    rescue
      error ->
        Logger.error("Quality scoring failed for #{repository_data.full_name}: #{inspect(error)}")
        {:error, {:scoring_failed, error}}
    end
  end

  # Individual scoring dimensions using functional composition

  defp score_code_quality(repo_data) do
    repo_data
    |> calculate_test_coverage_score()
    |> add_documentation_score(repo_data)
    |> add_code_style_score(repo_data)
    |> add_language_consistency_score(repo_data)
    |> normalize_to_percentage()
  end

  defp score_community_health(repo_data) do
    %{
      contributor_diversity: calculate_contributor_diversity(repo_data),
      issue_activity: calculate_issue_activity_score(repo_data),
      pr_merge_rate: calculate_pr_merge_rate(repo_data),
      release_frequency: calculate_release_frequency(repo_data),
      community_engagement: calculate_community_engagement(repo_data)
    }
    |> calculate_composite_score()
  end

  defp score_technical_complexity(repo_data) do
    complexity_factors = [
      size_complexity: calculate_size_complexity(repo_data),
      dependency_complexity: calculate_dependency_complexity(repo_data),
      umbrella_complexity: calculate_umbrella_complexity(repo_data),
      domain_complexity: calculate_domain_complexity(repo_data)
    ]

    complexity_factors
    |> Enum.map(fn {_factor, value} -> normalize_complexity_factor(value) end)
    |> Enum.sum()
    |> min(100.0)
  end

  defp score_maintenance_activity(repo_data) do
    activity_metrics = [
      recent_commits: score_recent_commits(repo_data),
      contributor_activity: score_contributor_activity(repo_data),
      issue_resolution: score_issue_resolution(repo_data),
      release_cadence: score_release_cadence(repo_data)
    ]

    activity_metrics
    |> Enum.map(&normalize_activity_metric/1)
    |> calculate_geometric_mean()
  end

  # Quality scoring helper functions

  defp calculate_test_coverage_score(repo_data) do
    # Placeholder - enhanced in Phase 3
    cond do
      has_comprehensive_tests?(repo_data) -> 25.0
      has_basic_tests?(repo_data) -> 15.0
      true -> 5.0
    end
  end

  defp add_documentation_score(base_score, repo_data) do
    documentation_score =
      cond do
        has_excellent_documentation?(repo_data) -> 15.0
        has_good_documentation?(repo_data) -> 10.0
        has_basic_documentation?(repo_data) -> 5.0
        true -> 0.0
      end

    base_score + documentation_score
  end

  defp add_code_style_score(base_score, repo_data) do
    # Check for Credo, Dialyzer, formatter configuration
    style_score =
      if has_code_quality_tools?(repo_data), do: 10.0, else: 5.0

    base_score + style_score
  end

  defp add_language_consistency_score(base_score, repo_data) do
    elixir_percentage = calculate_elixir_percentage(repo_data)

    consistency_score =
      cond do
        elixir_percentage >= 90 -> 10.0
        elixir_percentage >= 75 -> 7.0
        elixir_percentage >= 50 -> 4.0
        true -> 1.0
      end

    base_score + consistency_score
  end

  defp normalize_to_percentage(score), do: min(score, 100.0)

  # Community health calculations

  defp calculate_contributor_diversity(repo_data) do
    contributors = Map.get(repo_data, :contributors, [])

    cond do
      length(contributors) >= 10 -> 20.0
      length(contributors) >= 5 -> 15.0
      length(contributors) >= 2 -> 10.0
      true -> 5.0
    end
  end

  defp calculate_issue_activity_score(repo_data) do
    # Placeholder - will be enhanced with actual GitHub API data
    stars = Map.get(repo_data, :stargazers_count, 0)

    cond do
      stars >= 1000 -> 15.0
      stars >= 100 -> 10.0
      stars >= 10 -> 7.0
      true -> 3.0
    end
  end

  defp calculate_pr_merge_rate(_repo_data) do
    # Placeholder - will be calculated from actual PR data
    10.0
  end

  defp calculate_release_frequency(_repo_data) do
    # Placeholder - will be calculated from release history
    10.0
  end

  defp calculate_community_engagement(repo_data) do
    # Base engagement on stars, forks, and watchers
    stars = Map.get(repo_data, :stargazers_count, 0)
    forks = Map.get(repo_data, :forks_count, 0)

    engagement_score = :math.log10(max(stars + forks, 1)) * 5
    min(engagement_score, 20.0)
  end

  defp calculate_composite_score(score_map) do
    score_map
    |> Map.values()
    |> Enum.sum()
    |> min(100.0)
  end

  # Technical complexity calculations

  defp calculate_size_complexity(repo_data) do
    # Estimate complexity based on repository size
    size_kb = Map.get(repo_data, :size, 0)

    cond do
      # Very complex
      size_kb >= 10000 -> 25.0
      # Complex
      size_kb >= 5000 -> 20.0
      # Moderate
      size_kb >= 1000 -> 15.0
      # Simple
      size_kb >= 100 -> 10.0
      # Very simple
      true -> 5.0
    end
  end

  defp calculate_dependency_complexity(_repo_data) do
    # Placeholder - will analyze mix.exs dependencies
    15.0
  end

  defp calculate_umbrella_complexity(repo_data) do
    if Map.get(repo_data, :is_umbrella_project, false) do
      # Umbrella projects are more complex
      20.0
    else
      10.0
    end
  end

  defp calculate_domain_complexity(repo_data) do
    # Analyze topics and description for domain complexity
    topics = Map.get(repo_data, :topics, [])

    complex_domains = ["machine-learning", "distributed-systems", "blockchain", "graphics"]

    if Enum.any?(topics, &(&1 in complex_domains)) do
      20.0
    else
      10.0
    end
  end

  defp normalize_complexity_factor(value), do: max(0.0, min(value, 100.0))

  # Maintenance activity calculations

  defp score_recent_commits(_repo_data) do
    # Placeholder - will be calculated from commit history
    15.0
  end

  defp score_contributor_activity(_repo_data) do
    # Placeholder - will be calculated from contributor data
    15.0
  end

  defp score_issue_resolution(_repo_data) do
    # Placeholder - will be calculated from issue data
    15.0
  end

  defp score_release_cadence(_repo_data) do
    # Placeholder - will be calculated from release data
    15.0
  end

  defp normalize_activity_metric(metric), do: max(0.0, min(metric, 25.0))

  defp calculate_geometric_mean(values) when length(values) > 0 do
    product = Enum.reduce(values, 1.0, &*/2)
    :math.pow(product, 1.0 / length(values))
  end

  defp calculate_geometric_mean(_), do: 0.0

  # Quality assessment helper functions

  defp has_comprehensive_tests?(repo_data) do
    # Check for test directory and CI configuration
    Map.get(repo_data, :has_ci_config, false) and
      Map.get(repo_data, :test_file_count, 0) > 5
  end

  defp has_basic_tests?(repo_data) do
    Map.get(repo_data, :test_file_count, 0) > 0
  end

  defp has_excellent_documentation?(repo_data) do
    description = Map.get(repo_data, :description, "")

    String.length(description) > 100 and
      has_readme?(repo_data) and
      has_documentation_generation?(repo_data)
  end

  defp has_good_documentation?(repo_data) do
    description = Map.get(repo_data, :description, "")

    String.length(description) > 50 and has_readme?(repo_data)
  end

  defp has_basic_documentation?(repo_data) do
    not is_nil(Map.get(repo_data, :description)) or has_readme?(repo_data)
  end

  defp has_readme?(_repo_data) do
    # Placeholder - will check for README file
    true
  end

  defp has_documentation_generation?(_repo_data) do
    # Placeholder - will check for ExDoc or similar
    false
  end

  defp has_code_quality_tools?(_repo_data) do
    # Placeholder - will check for .credo.exs, dialyzer_ignore_warnings, etc.
    false
  end

  defp calculate_elixir_percentage(repo_data) do
    languages = Map.get(repo_data, :languages, %{})

    if Map.has_key?(languages, "Elixir") do
      total_bytes = languages |> Map.values() |> Enum.sum()
      elixir_bytes = Map.get(languages, "Elixir", 0)

      if total_bytes > 0 do
        elixir_bytes / total_bytes * 100
      else
        # Assume 100% if no language data
        100.0
      end
    else
      0.0
    end
  end

  # Overall scoring calculation

  defp calculate_weighted_overall_score(quality_scores) do
    weights = %{
      code_quality_score: 0.30,
      community_health_score: 0.25,
      technical_complexity_score: 0.25,
      maintenance_activity_score: 0.20
    }

    weighted_score =
      quality_scores
      |> Enum.reduce(0.0, fn {dimension, score}, acc ->
        weight = Map.get(weights, dimension, 0)
        acc + score * weight
      end)

    Float.round(weighted_score, 2)
  end
end
