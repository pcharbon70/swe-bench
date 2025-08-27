defmodule SweBench.PartialCreditScoring.TestScorer do
  @moduledoc """
  Scores partial test passage and analyzes test failures.
  
  Evaluates how many tests pass and categorizes test failures for detailed
  feedback. Provides 50% threshold scoring based on test achievement.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the test scorer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Scores test passage for the given solution.
  """
  def score(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:score, solution_data, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("TestScorer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:score, solution_data, _options}, _from, state) do
    try do
      score_result = evaluate_tests(solution_data, state.config)
      {:reply, {:ok, score_result}, state}
    rescue
      error ->
        Logger.error("Test scoring failed: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  # Private functions

  defp evaluate_tests(solution_data, config) do
    test_threshold = get_in(config, [:dimensions, :partial_tests, :threshold]) || 50
    
    # Extract test results from solution data
    total_tests = Map.get(solution_data, :total_tests, 0)
    passed_tests = Map.get(solution_data, :passed_tests, 0)
    failed_tests = Map.get(solution_data, :failed_tests, [])
    
    score = if total_tests > 0 do
      (passed_tests / total_tests) * 100.0
    else
      0.0
    end

    %{
      score: score,
      threshold_met: score >= test_threshold,
      details: %{
        total_tests: total_tests,
        passed_tests: passed_tests,
        failed_tests: length(failed_tests),
        pass_rate: score,
        failures: categorize_test_failures(failed_tests),
        threshold: test_threshold
      }
    }
  end

  defp categorize_test_failures(failures) do
    Enum.map(failures, fn failure ->
      %{
        type: determine_failure_type(failure),
        message: to_string(failure),
        severity: determine_failure_severity(failure)
      }
    end)
  end

  defp determine_failure_type(failure) when is_binary(failure) do
    cond do
      String.contains?(failure, "assertion") -> :assertion_failure
      String.contains?(failure, "timeout") -> :timeout
      String.contains?(failure, "setup") -> :setup_error
      String.contains?(failure, "teardown") -> :teardown_error
      String.contains?(failure, "exception") -> :exception
      true -> :unknown_failure
    end
  end

  defp determine_failure_type(_failure), do: :unknown_failure

  defp determine_failure_severity(failure) when is_binary(failure) do
    cond do
      String.contains?(failure, "critical") or String.contains?(failure, "fatal") -> :critical
      String.contains?(failure, "timeout") -> :major
      String.contains?(failure, "assertion") -> :minor
      true -> :minor
    end
  end

  defp determine_failure_severity(_failure), do: :minor
end