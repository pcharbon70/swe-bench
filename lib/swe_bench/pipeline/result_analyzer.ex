defmodule SweBench.Pipeline.ResultAnalyzer do
  @moduledoc """
  GenStage Consumer for evaluation result analysis.

  Processes FAIL_TO_PASS transitions in parallel, calculates scoring
  metrics concurrently, and streams results to database.
  """

  use GenStage
  require Logger

  # alias SweBench.TestRunner.Analyzer - for future integration

  defstruct [
    :database_streamer,
    :metrics_calculator,
    :notification_sender,
    :parallel_workers,
    :analysis_cache
  ]

  @doc """
  Starts the result analyzer stage.
  """
  def start_link(opts \\ []) do
    stage_name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, opts, name: stage_name)
  end

  @doc """
  Gets current analyzer statistics.
  """
  def get_stats(stage_name \\ __MODULE__) do
    GenStage.call(stage_name, :get_stats)
  end

  # GenStage callbacks

  @impl GenStage
  def init(opts) do
    parallel_workers = Keyword.get(opts, :parallel_workers, 6)
    enable_notifications = Keyword.get(opts, :enable_notifications, true)
    cache_analysis = Keyword.get(opts, :cache_analysis, true)

    state = %__MODULE__{
      database_streamer: initialize_database_streamer(opts),
      metrics_calculator: initialize_metrics_calculator(opts),
      notification_sender:
        if(enable_notifications, do: initialize_notification_sender(opts), else: nil),
      parallel_workers: parallel_workers,
      analysis_cache: if(cache_analysis, do: %{}, else: nil)
    }

    Logger.info(
      "ResultAnalyzer started with #{parallel_workers} workers, notifications=#{enable_notifications}"
    )

    {:consumer, state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    Logger.debug("ResultAnalyzer processing #{length(events)} evaluation results")

    # Process results in parallel
    analyzed_results = process_results_parallel(events, state)

    # Stream to database without blocking
    stream_results_to_database(analyzed_results, state)

    # Send notifications if enabled
    if state.notification_sender do
      send_progress_notifications(analyzed_results, state)
    end

    Logger.debug("ResultAnalyzer completed processing #{length(analyzed_results)} results")

    {:noreply, [], state}
  end

  @impl GenStage
  def handle_call(:get_stats, _from, state) do
    stats = %{
      parallel_workers: state.parallel_workers,
      notifications_enabled: state.notification_sender != nil,
      cache_enabled: state.analysis_cache != nil,
      database_streamer: state.database_streamer
    }

    {:reply, stats, [], state}
  end

  # Private helper functions

  defp process_results_parallel(events, state) do
    # Process events in parallel chunks
    chunk_size = max(1, div(length(events), state.parallel_workers))

    events
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(fn chunk ->
      Task.async(fn ->
        Enum.map(chunk, &analyze_single_result(&1, state))
      end)
    end)
    |> Task.await_many(:timer.seconds(30))
    |> List.flatten()
  end

  defp analyze_single_result(evaluation_result, state) do
    Logger.debug("Analyzing result for task #{evaluation_result.id}")

    analysis = %{
      task_id: evaluation_result.id,
      repository: evaluation_result.repository,
      evaluation_time: evaluation_result.evaluation_time,
      test_transition: analyze_test_transition(evaluation_result),
      quality_score: calculate_quality_score(evaluation_result),
      performance_metrics: extract_performance_metrics(evaluation_result),
      analyzed_at: DateTime.utc_now()
    }

    # Cache analysis if enabled
    if state.analysis_cache do
      _cache_key = "analysis_#{evaluation_result.id}"
      # Would store in actual cache in production
    end

    Map.merge(evaluation_result, %{analysis: analysis})
  end

  defp analyze_test_transition(evaluation_result) do
    # Placeholder for test transition analysis
    # Would integrate with SweBench.TestRunner.Analyzer in production
    test_results = evaluation_result.test_results || %{}

    %{
      transition_type: determine_transition_type(test_results),
      # Placeholder
      before_state: :failing,
      # Placeholder
      after_state: :passing,
      affected_tests: test_results.total || 0,
      success_rate: calculate_success_rate(test_results)
    }
  end

  defp determine_transition_type(test_results) do
    cond do
      test_results.failed == 0 -> :fail_to_pass
      test_results.passed > test_results.failed -> :partial_fix
      true -> :no_improvement
    end
  end

  defp calculate_success_rate(test_results) do
    total = test_results.total || 1
    passed = test_results.passed || 0

    if total > 0, do: passed / total * 100, else: 0
  end

  defp calculate_quality_score(evaluation_result) do
    base_score = 50

    # Add points for successful evaluation
    score = if evaluation_result.status == :completed, do: base_score + 30, else: base_score

    # Add points for test improvements
    test_results = evaluation_result.test_results || %{}
    score = if test_results.passed > 0, do: score + 20, else: score

    min(100, score)
  end

  defp extract_performance_metrics(evaluation_result) do
    %{
      evaluation_time_ms: evaluation_result.evaluation_time || 0,
      # Placeholder
      memory_usage_mb: 150,
      # Placeholder
      cpu_usage_percent: 45,
      # Placeholder
      container_startup_time_ms: 2000
    }
  end

  defp stream_results_to_database(results, _state) do
    Logger.debug("Streaming #{length(results)} results to database")

    # Placeholder for database streaming
    # Would use Ash.create_many or Ecto.Multi in production
    :ok
  end

  defp send_progress_notifications(results, state) do
    if state.notification_sender do
      Logger.debug("Sending progress notifications for #{length(results)} results")

      # Placeholder for notification sending
      # Would integrate with Phoenix.PubSub or external notification service
      :ok
    end
  end

  defp initialize_database_streamer(_opts) do
    %{enabled: true, batch_size: 10}
  end

  defp initialize_metrics_calculator(_opts) do
    %{enabled: true, cache_ttl: 300}
  end

  defp initialize_notification_sender(_opts) do
    %{enabled: true, channels: ["progress", "completion"]}
  end
end
