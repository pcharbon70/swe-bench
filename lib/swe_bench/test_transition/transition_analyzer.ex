defmodule SweBench.TestTransition.TransitionAnalyzer do
  @moduledoc """
  Analyzes test state transitions for validation quality assessment.

  Implements sophisticated algorithms for detecting test transitions,
  identifying flaky behavior, and calculating confidence metrics.
  """

  require Logger

  @doc """
  Analyzes test transitions between base and patched test runs.

  ## Parameters
    - base_results: Test results from base commit execution
    - patched_results: List of test results from patched executions

  ## Returns
    - {:ok, transition_analysis} - Comprehensive transition analysis
    - {:error, reason} - Analysis failure details
  """
  def analyze_transitions(base_results, patched_results) when is_list(patched_results) do
    Logger.debug("Analyzing transitions from #{length(patched_results)} patched runs")

    base_results
    |> extract_test_states()
    |> compare_with_patched_runs(patched_results)
    |> classify_transitions()
    |> detect_flaky_behavior()
    |> calculate_transition_metrics()
  rescue
    error ->
      Logger.error("Transition analysis failed: #{inspect(error)}")
      {:error, {:analysis_failed, error}}
  end

  # Private implementation functions

  defp extract_test_states(test_results) do
    case Map.get(test_results, :tests) do
      tests when is_list(tests) ->
        test_states =
          tests
          |> Enum.map(fn test ->
            {test_identifier(test), test.status}
          end)
          |> Map.new()

        {:ok, test_states}

      _ ->
        {:error, :invalid_test_results}
    end
  end

  defp compare_with_patched_runs({:ok, base_states}, patched_results) do
    patched_states =
      patched_results
      |> Enum.map(fn patched_result ->
        case extract_test_states(patched_result) do
          {:ok, states} -> states
          {:error, _} -> %{}
        end
      end)

    {:ok, {base_states, patched_states}}
  end

  defp compare_with_patched_runs({:error, reason}, _patched_results) do
    {:error, reason}
  end

  defp classify_transitions({:ok, {base_states, patched_states_list}}) do
    # Analyze transitions across all patched runs
    all_test_names = extract_all_test_names(base_states, patched_states_list)

    transitions =
      all_test_names
      |> Enum.map(fn test_name ->
        base_status = Map.get(base_states, test_name, :unknown)
        patched_statuses = Enum.map(patched_states_list, &Map.get(&1, test_name, :unknown))

        transition_type = classify_single_test_transition(base_status, patched_statuses)

        %{
          test_name: test_name,
          base_status: base_status,
          patched_statuses: patched_statuses,
          transition_type: transition_type,
          consistency: calculate_transition_consistency(patched_statuses)
        }
      end)

    grouped_transitions = group_transitions_by_type(transitions)

    {:ok, {transitions, grouped_transitions}}
  end

  defp classify_transitions({:error, reason}) do
    {:error, reason}
  end

  defp classify_single_test_transition(base_status, patched_statuses) do
    # Determine the most common patched status
    most_common_patched = find_most_common_status(patched_statuses)

    case {base_status, most_common_patched} do
      {:failed, :passed} -> :fail_to_pass
      {:passed, :passed} -> :pass_to_pass
      {:passed, :failed} -> :pass_to_fail
      {:failed, :failed} -> :fail_to_fail
      _ -> :indeterminate
    end
  end

  defp find_most_common_status(statuses) do
    statuses
    |> Enum.frequencies()
    |> Enum.max_by(fn {_status, count} -> count end, fn -> {:unknown, 0} end)
    |> elem(0)
  end

  defp calculate_transition_consistency(patched_statuses) do
    unique_statuses = Enum.uniq(patched_statuses)

    case length(unique_statuses) do
      # Perfectly consistent
      1 -> 1.0
      # Some inconsistency
      2 -> 0.7
      # High inconsistency
      _ -> 0.3
    end
  end

  defp group_transitions_by_type(transitions) do
    transitions
    |> Enum.group_by(& &1.transition_type)
    |> Enum.map(fn {type, group} -> {type, length(group)} end)
    |> Map.new()
  end

  defp detect_flaky_behavior({:ok, {transitions, grouped_transitions}}) do
    flaky_tests =
      transitions
      |> Enum.filter(&flaky_test?/1)
      |> Enum.map(& &1.test_name)

    flakiness_score = calculate_flakiness_score(transitions)

    analysis = %{
      transitions: transitions,
      grouped_transitions: grouped_transitions,
      flaky_tests: flaky_tests,
      flakiness_score: flakiness_score
    }

    {:ok, analysis}
  end

  defp detect_flaky_behavior({:error, reason}) do
    {:error, reason}
  end

  defp flaky_test?(transition) do
    # A test is considered flaky if it has low consistency across runs
    transition.consistency < 0.8
  end

  defp calculate_flakiness_score(transitions) do
    if Enum.empty?(transitions) do
      0.0
    else
      total_consistency = Enum.sum(Enum.map(transitions, & &1.consistency))
      average_consistency = total_consistency / length(transitions)

      # Flakiness is inverse of consistency
      1.0 - average_consistency
    end
  end

  defp calculate_transition_metrics({:ok, analysis}) do
    metrics = %{
      total_tests: length(analysis.transitions),
      fail_to_pass_count: Map.get(analysis.grouped_transitions, :fail_to_pass, 0),
      pass_to_pass_count: Map.get(analysis.grouped_transitions, :pass_to_pass, 0),
      pass_to_fail_count: Map.get(analysis.grouped_transitions, :pass_to_fail, 0),
      flaky_test_count: length(analysis.flaky_tests),
      flakiness_score: analysis.flakiness_score,
      transition_diversity: calculate_transition_diversity(analysis.grouped_transitions)
    }

    final_analysis = Map.put(analysis, :metrics, metrics)

    {:ok, final_analysis}
  end

  defp calculate_transition_metrics({:error, reason}) do
    {:error, reason}
  end

  defp calculate_transition_diversity(grouped_transitions) do
    # Measure how diverse the transitions are (useful for quality assessment)
    transition_types = Map.keys(grouped_transitions)
    unique_types = length(transition_types)

    case unique_types do
      # Single transition type
      1 -> 0.0
      # Two transition types
      2 -> 0.5
      # Three transition types
      3 -> 0.8
      # High diversity
      _ -> 1.0
    end
  end

  defp extract_all_test_names(base_states, patched_states_list) do
    all_names = Map.keys(base_states)

    patched_names =
      patched_states_list
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    Enum.uniq(all_names ++ patched_names)
  end

  defp test_identifier(test) do
    # Create unique identifier for test
    module = Map.get(test, :module, "Unknown")
    name = Map.get(test, :name, "unknown")
    "#{module}.#{name}"
  end
end
