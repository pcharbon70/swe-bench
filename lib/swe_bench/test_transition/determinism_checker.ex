defmodule SweBench.TestTransition.DeterminismChecker do
  @moduledoc """
  Determinism validation for test execution results.

  Implements statistical analysis to detect non-deterministic behavior
  and ensure test transitions are reliable for benchmark tasks.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks determinism across multiple test execution runs.
  """
  def check_determinism(test_results_list, opts \\ []) do
    GenServer.call(__MODULE__, {:check_determinism, test_results_list, opts})
  end

  @doc """
  Gets determinism checking statistics.
  """
  def get_determinism_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      checks_performed: 0,
      deterministic_count: 0,
      non_deterministic_count: 0,
      avg_consistency_score: 0.0
    }

    Logger.info("Determinism checker started")
    {:ok, state}
  end

  @impl true
  def handle_call({:check_determinism, test_results_list, opts}, _from, state) do
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.90)

    result =
      test_results_list
      |> extract_test_outcomes()
      |> calculate_consistency_metrics()
      |> assess_determinism(confidence_threshold)

    updated_state = update_determinism_stats(state, result)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp extract_test_outcomes(test_results_list) when is_list(test_results_list) do
    test_outcomes =
      test_results_list
      |> Enum.map(fn test_result ->
        extract_test_status_map(test_result)
      end)

    {:ok, test_outcomes}
  end

  defp calculate_consistency_metrics({:ok, test_outcomes_list}) do
    all_test_names = extract_all_test_names(test_outcomes_list)

    consistency_metrics =
      all_test_names
      |> Enum.map(fn test_name ->
        statuses = Enum.map(test_outcomes_list, &Map.get(&1, test_name, :unknown))
        consistency = calculate_test_consistency(statuses)

        %{
          test_name: test_name,
          statuses: statuses,
          consistency: consistency,
          is_consistent: consistency >= 0.90
        }
      end)

    overall_consistency = calculate_overall_consistency(consistency_metrics)

    {:ok, {consistency_metrics, overall_consistency}}
  end

  defp calculate_consistency_metrics({:error, reason}) do
    {:error, reason}
  end

  defp calculate_test_consistency(statuses) do
    unique_statuses = Enum.uniq(statuses)

    case length(unique_statuses) do
      # Perfectly consistent
      1 -> 1.0
      # Some variation
      2 -> 0.6
      # High variation
      _ -> 0.2
    end
  end

  defp calculate_overall_consistency(consistency_metrics) do
    if Enum.empty?(consistency_metrics) do
      0.0
    else
      total_consistency = Enum.sum(Enum.map(consistency_metrics, & &1.consistency))
      total_consistency / length(consistency_metrics)
    end
  end

  defp assess_determinism({:ok, {consistency_metrics, overall_consistency}}, confidence_threshold) do
    inconsistent_tests = Enum.filter(consistency_metrics, &(not &1.is_consistent))

    assessment = %{
      overall_consistency: overall_consistency,
      is_deterministic: overall_consistency >= confidence_threshold,
      consistent_test_count: length(consistency_metrics) - length(inconsistent_tests),
      inconsistent_test_count: length(inconsistent_tests),
      inconsistent_tests: Enum.map(inconsistent_tests, & &1.test_name),
      confidence_level: overall_consistency
    }

    {:ok, assessment}
  end

  defp assess_determinism({:error, reason}, _confidence_threshold) do
    {:error, reason}
  end

  defp extract_all_test_names(test_outcomes_list) do
    test_outcomes_list
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
  end

  defp extract_test_status_map(test_result) do
    case Map.get(test_result, :tests) do
      tests when is_list(tests) ->
        tests
        |> Enum.map(fn test ->
          {test_identifier(test), test.status}
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp test_identifier(test) do
    module = Map.get(test, :module, "Unknown")
    name = Map.get(test, :name, "unknown")
    "#{module}.#{name}"
  end

  defp update_determinism_stats(state, result) do
    new_checks = state.checks_performed + 1

    {new_deterministic, new_non_deterministic} =
      case result do
        {:ok, %{is_deterministic: true}} ->
          {state.deterministic_count + 1, state.non_deterministic_count}

        {:ok, %{is_deterministic: false}} ->
          {state.deterministic_count, state.non_deterministic_count + 1}

        {:error, _} ->
          {state.deterministic_count, state.non_deterministic_count + 1}
      end

    new_avg_consistency =
      case result do
        {:ok, %{overall_consistency: consistency}} ->
          if new_checks > 1 do
            (state.avg_consistency_score * (new_checks - 1) + consistency) / new_checks
          else
            consistency
          end

        {:error, _} ->
          state.avg_consistency_score
      end

    %{
      state
      | checks_performed: new_checks,
        deterministic_count: new_deterministic,
        non_deterministic_count: new_non_deterministic,
        avg_consistency_score: new_avg_consistency
    }
  end
end
