defmodule SweBench.PartialCreditScoring.MultiDimensionalScorer do
  @moduledoc """
  Main coordinator for multi-dimensional scoring evaluation.

  Manages parallel evaluation across all scoring dimensions with fault tolerance
  and result aggregation. Provides the primary interface for scoring operations.
  """

  use GenServer
  require Logger

  alias SweBench.PartialCreditScoring.{
    CompilationScorer,
    FunctionalProgrammingScorer,
    PerformanceScorer,
    QualityScorer,
    ScoreAggregator,
    TestScorer
  }

  defstruct [
    :config,
    :scoring_tasks,
    :results_cache,
    :evaluation_metrics
  ]

  @doc """
  Starts the multi-dimensional scorer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Scores a solution across all dimensions.

  Returns a comprehensive score result with individual dimension scores,
  aggregated score, and analysis metadata.
  """
  def score_solution(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:score_solution, solution_data, options}, 60_000)
  end

  @doc """
  Returns the current scoring configuration.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Updates the scoring configuration.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  @doc """
  Returns current evaluation metrics and statistics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: config,
      scoring_tasks: %{},
      results_cache: %{},
      evaluation_metrics: initialize_metrics()
    }

    Logger.info("MultiDimensionalScorer initialized with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:score_solution, solution_data, options}, from, state) do
    task_id = generate_task_id()
    timeout = Keyword.get(options, :timeout, state.config[:timeout] || 30_000)

    # Start parallel scoring across all dimensions
    scoring_task =
      Task.async_stream(
        [
          {:compilation, CompilationScorer},
          {:partial_tests, TestScorer},
          {:code_quality, QualityScorer},
          {:performance, PerformanceScorer},
          {:functional_programming, FunctionalProgrammingScorer}
        ],
        fn {dimension, scorer_module} ->
          try do
            result = GenServer.call(scorer_module, {:score, solution_data}, timeout)
            {dimension, result}
          rescue
            error ->
              Logger.warning("Scoring failed for #{dimension}: #{inspect(error)}")
              {dimension, {:error, error}}
          end
        end,
        timeout: timeout + 5_000,
        max_concurrency: 5
      )

    # Store task for monitoring
    new_state =
      put_in(state.scoring_tasks[task_id], %{
        from: from,
        task: scoring_task,
        solution_data: solution_data,
        started_at: DateTime.utc_now()
      })

    # Process results asynchronously
    spawn_link(fn -> process_scoring_results(task_id, scoring_task) end)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, {:ok, state.config}, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    new_state = %{state | config: new_config}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.evaluation_metrics, state}
  end

  @impl true
  def handle_info({:scoring_complete, task_id, result}, state) do
    case Map.get(state.scoring_tasks, task_id) do
      nil ->
        {:noreply, state}

      task_info ->
        GenServer.reply(task_info.from, result)

        # Update metrics
        new_metrics =
          update_evaluation_metrics(
            state.evaluation_metrics,
            task_info.started_at,
            result
          )

        # Clean up task
        new_state =
          state
          |> put_in([:scoring_tasks], Map.delete(state.scoring_tasks, task_id))
          |> put_in([:evaluation_metrics], new_metrics)

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:scoring_failed, task_id, error}, state) do
    case Map.get(state.scoring_tasks, task_id) do
      nil ->
        {:noreply, state}

      task_info ->
        GenServer.reply(task_info.from, {:error, error})

        # Update metrics
        new_metrics = update_error_metrics(state.evaluation_metrics, error)

        # Clean up task
        new_state =
          state
          |> put_in([:scoring_tasks], Map.delete(state.scoring_tasks, task_id))
          |> put_in([:evaluation_metrics], new_metrics)

        {:noreply, new_state}
    end
  end

  # Private functions

  defp process_scoring_results(task_id, scoring_task) do
    dimension_results =
      Enum.reduce(scoring_task, %{}, fn
        {:ok, {dimension, result}}, acc -> Map.put(acc, dimension, result)
        {:exit, {dimension, _reason}}, acc -> Map.put(acc, dimension, {:error, :timeout})
      end)

    # Aggregate scores
    case ScoreAggregator.aggregate_scores(dimension_results) do
      {:ok, aggregated_result} ->
        send(__MODULE__, {:scoring_complete, task_id, {:ok, aggregated_result}})

      {:error, reason} ->
        send(__MODULE__, {:scoring_failed, task_id, reason})
    end
  rescue
    error ->
      send(__MODULE__, {:scoring_failed, task_id, error})
  end

  defp generate_task_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp initialize_metrics do
    %{
      total_evaluations: 0,
      successful_evaluations: 0,
      failed_evaluations: 0,
      average_evaluation_time: 0.0,
      dimension_success_rates: %{
        compilation: 0.0,
        partial_tests: 0.0,
        code_quality: 0.0,
        performance: 0.0,
        functional_programming: 0.0
      },
      started_at: DateTime.utc_now()
    }
  end

  defp update_evaluation_metrics(metrics, started_at, result) do
    evaluation_time = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    total = metrics.total_evaluations + 1

    case result do
      {:ok, _aggregated_result} ->
        %{
          metrics
          | total_evaluations: total,
            successful_evaluations: metrics.successful_evaluations + 1,
            average_evaluation_time:
              (metrics.average_evaluation_time * (total - 1) + evaluation_time) / total
        }

      {:error, _reason} ->
        %{
          metrics
          | total_evaluations: total,
            failed_evaluations: metrics.failed_evaluations + 1,
            average_evaluation_time:
              (metrics.average_evaluation_time * (total - 1) + evaluation_time) / total
        }
    end
  end

  defp update_error_metrics(metrics, _error) do
    %{
      metrics
      | total_evaluations: metrics.total_evaluations + 1,
        failed_evaluations: metrics.failed_evaluations + 1
    }
  end
end
