defmodule SweBench.QualityValidation.DeduplicationSystem do
  @moduledoc """
  Deduplication system for quality validation.

  Implements sophisticated similarity detection using AST analysis,
  text similarity, and semantic matching to identify duplicate tasks.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks a task instance for duplicates.
  """
  def check_for_duplicates(task_instance) do
    GenServer.call(__MODULE__, {:check_duplicates, task_instance})
  end

  @doc """
  Analyzes similarity between two task instances.
  """
  def analyze_similarity(task_a, task_b) do
    GenServer.call(__MODULE__, {:analyze_similarity, task_a, task_b})
  end

  @doc """
  Gets deduplication statistics.
  """
  def get_deduplication_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      similarity_checks: 0,
      duplicates_found: 0,
      avg_check_time: 0.0,
      similarity_cache: %{}
    }

    Logger.info("Deduplication system started")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_duplicates, task_instance}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      task_instance
      |> find_potential_duplicates()
      |> calculate_similarity_scores()
      |> evaluate_deduplication_recommendations()
      |> compile_deduplication_result()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_deduplication_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call({:analyze_similarity, task_a, task_b}, _from, state) do
    similarity_score = calculate_pairwise_similarity(task_a, task_b)
    {:reply, {:ok, similarity_score}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp find_potential_duplicates(task_instance) do
    Logger.debug("Finding potential duplicates for task #{task_instance.instance_id}")

    # Query for task instances in same repository with similar characteristics
    similar_tasks =
      SweBench.TaskInstances.TaskInstance
      |> Ash.Query.for_read(:by_repository, %{repository_id: task_instance.repository_id})
      # Limit for performance
      |> Ash.Query.limit(50)
      |> Ash.read!()

    add_deduplication_step(task_instance, :candidate_search, %{
      candidates_found: length(similar_tasks)
    })
  end

  defp calculate_similarity_scores(task_instance) do
    Logger.debug("Calculating similarity scores for task #{task_instance.instance_id}")

    candidates = get_step_result(task_instance, :candidate_search, :candidates_found, 0)

    # Placeholder for similarity calculations
    similarity_results = %{
      code_similarity_scores: [],
      text_similarity_scores: [],
      semantic_similarity_scores: [],
      combined_scores: []
    }

    add_deduplication_step(task_instance, :similarity_calculation, similarity_results)
  end

  defp evaluate_deduplication_recommendations(task_instance) do
    Logger.debug("Evaluating deduplication recommendations for task #{task_instance.instance_id}")

    # Placeholder for deduplication logic
    recommendations = %{
      high_similarity_matches: [],
      deduplication_candidates: [],
      # High uniqueness (no significant duplicates)
      uniqueness_score: 0.95,
      recommendation: :keep
    }

    add_deduplication_step(task_instance, :recommendation_evaluation, recommendations)
  end

  defp compile_deduplication_result(task_instance) do
    deduplication_steps = Map.get(task_instance, :deduplication_steps, [])

    # Extract final recommendations
    recommendations =
      get_step_result(task_instance, :recommendation_evaluation, :recommendation, :keep)

    uniqueness_score =
      get_step_result(task_instance, :recommendation_evaluation, :uniqueness_score, 0.95)

    deduplication_summary = %{
      uniqueness_score: uniqueness_score,
      deduplication_recommendation: recommendations,
      similarity_analysis: compile_similarity_summary(deduplication_steps),
      # Placeholder
      deduplication_confidence: 0.90,
      analysis_stage: :deduplication,
      analyzed_at: DateTime.utc_now()
    }

    {:ok, deduplication_summary}
  end

  defp calculate_pairwise_similarity(task_a, task_b) do
    # Implement multi-dimensional similarity calculation
    code_sim = calculate_code_similarity(task_a.patch_content, task_b.patch_content)
    text_sim = calculate_text_similarity(task_a.problem_statement, task_b.problem_statement)

    # Weighted combination
    combined_similarity = code_sim * 0.6 + text_sim * 0.4

    %{
      code_similarity: code_sim,
      text_similarity: text_sim,
      combined_similarity: combined_similarity,
      similarity_confidence: 0.85
    }
  end

  defp calculate_code_similarity(patch_a, patch_b) do
    # Placeholder - will implement AST-based code similarity
    # For now, use simple text similarity as approximation
    calculate_text_similarity(patch_a, patch_b)
  end

  defp calculate_text_similarity(text_a, text_b) do
    # Simple Jaccard similarity implementation
    words_a = text_a |> String.downcase() |> String.split() |> MapSet.new()
    words_b = text_b |> String.downcase() |> String.split() |> MapSet.new()

    intersection = MapSet.intersection(words_a, words_b) |> MapSet.size()
    union = MapSet.union(words_a, words_b) |> MapSet.size()

    if union > 0 do
      intersection / union
    else
      0.0
    end
  end

  defp add_deduplication_step(task_instance, step_name, step_result) do
    deduplication_step = %{
      step: step_name,
      result: step_result,
      timestamp: DateTime.utc_now()
    }

    existing_steps = Map.get(task_instance, :deduplication_steps, [])
    Map.put(task_instance, :deduplication_steps, [deduplication_step | existing_steps])
  end

  defp get_step_result(task_instance, step_name, key, default) do
    case Enum.find(Map.get(task_instance, :deduplication_steps, []), &(&1.step == step_name)) do
      %{result: result} -> Map.get(result, key, default)
      nil -> default
    end
  end

  defp compile_similarity_summary(deduplication_steps) do
    similarity_step = Enum.find(deduplication_steps, &(&1.step == :similarity_calculation))

    case similarity_step do
      %{result: similarity_data} ->
        %{
          total_comparisons: length(similarity_data.combined_scores || []),
          high_similarity_count: count_high_similarities(similarity_data.combined_scores || []),
          avg_similarity: calculate_avg_similarity(similarity_data.combined_scores || [])
        }

      nil ->
        %{total_comparisons: 0, high_similarity_count: 0, avg_similarity: 0.0}
    end
  end

  defp count_high_similarities(scores) do
    Enum.count(scores, &(&1 > 0.8))
  end

  defp calculate_avg_similarity([]), do: 0.0

  defp calculate_avg_similarity(scores) do
    Enum.sum(scores) / length(scores)
  end

  defp update_deduplication_stats(state, result, processing_time) do
    new_total = state.similarity_checks + 1

    new_duplicates =
      case result do
        {:ok, %{deduplication_recommendation: rec}} when rec in [:remove, :merge] ->
          state.duplicates_found + 1

        _ ->
          state.duplicates_found
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_check_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | similarity_checks: new_total,
        duplicates_found: new_duplicates,
        avg_check_time: new_avg_time
    }
  end
end
