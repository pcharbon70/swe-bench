defmodule SweBench.Monitoring.DistributedTracer do
  @moduledoc """
  Distributed tracing infrastructure for evaluation workflows.

  Implements OpenTelemetry-compatible tracing with span correlation
  across evaluation pipeline stages and system components.
  """

  use GenServer
  require Logger

  alias SweBench.Monitoring.StructuredLogger

  defstruct [
    :config,
    :active_traces,
    :trace_spans,
    :sampling_config
  ]

  @trace_operations [
    :evaluation_submission,
    :evaluation_processing,
    :test_execution,
    :result_analysis,
    :model_comparison,
    :dashboard_rendering,
    :authentication,
    :session_management
  ]

  @doc """
  Starts the distributed tracer with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Starts a new trace for an operation.
  """
  def start_trace(operation_name, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:start_trace, operation_name, metadata})
  end

  @doc """
  Adds a span to an existing trace.
  """
  def add_span(trace_id, span_name, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:add_span, trace_id, span_name, metadata})
  end

  @doc """
  Completes a trace with final metadata.
  """
  def complete_trace(trace_id, result_metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:complete_trace, trace_id, result_metadata})
  end

  @doc """
  Gets active trace information.
  """
  def get_active_traces do
    GenServer.call(__MODULE__, :get_active_traces)
  end

  @doc """
  Gets trace history for analysis.
  """
  def get_trace_history(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_trace_history, limit})
  end

  @impl true
  def init(config) do
    tracing_config = build_tracing_config(config)

    state = %__MODULE__{
      config: tracing_config,
      active_traces: %{},
      trace_spans: %{},
      sampling_config: build_sampling_config(tracing_config)
    }

    # Setup telemetry handlers for automatic tracing
    setup_tracing_handlers()

    Logger.info("Monitoring.DistributedTracer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_trace, operation_name, metadata}, _from, state) do
    # Check if operation should be traced based on sampling
    case should_trace_operation?(operation_name, state.sampling_config) do
      false ->
        {:reply, {:ok, :not_sampled}, state}

      true ->
        trace_context = StructuredLogger.create_trace_context(operation_name)

        trace_data = %{
          trace_id: trace_context.trace_id,
          operation_name: operation_name,
          started_at: trace_context.started_at,
          metadata: metadata,
          spans: [],
          status: :active
        }

        new_traces = Map.put(state.active_traces, trace_context.trace_id, trace_data)

        # Log trace start
        StructuredLogger.log_evaluation_event(
          :trace_started,
          trace_context.trace_id,
          "Started trace for #{operation_name}",
          metadata
        )

        new_state = %{state | active_traces: new_traces}
        {:reply, {:ok, trace_context}, new_state}
    end
  end

  @impl true
  def handle_call(:get_active_traces, _from, state) do
    {:reply, state.active_traces, state}
  end

  @impl true
  def handle_call({:get_trace_history, limit}, _from, state) do
    trace_history =
      state.trace_spans
      |> Map.values()
      |> Enum.sort_by(& &1.completed_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:reply, trace_history, state}
  end

  @impl true
  def handle_cast({:add_span, trace_id, span_name, metadata}, state) do
    case Map.get(state.active_traces, trace_id) do
      nil ->
        # Trace not found or expired
        {:noreply, state}

      trace_data ->
        span_data = %{
          span_id: StructuredLogger.create_trace_context().span_id,
          span_name: span_name,
          started_at: DateTime.utc_now(),
          metadata: metadata,
          status: :active
        }

        updated_spans = [span_data | trace_data.spans]
        updated_trace = Map.put(trace_data, :spans, updated_spans)
        new_traces = Map.put(state.active_traces, trace_id, updated_trace)

        new_state = %{state | active_traces: new_traces}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:complete_trace, trace_id, result_metadata}, state) do
    case Map.get(state.active_traces, trace_id) do
      nil ->
        {:noreply, state}

      trace_data ->
        completed_trace = %{
          trace_data
          | completed_at: DateTime.utc_now(),
            result_metadata: result_metadata,
            status: :completed,
            duration_ms: DateTime.diff(DateTime.utc_now(), trace_data.started_at, :millisecond)
        }

        # Move to trace history and remove from active
        new_spans = Map.put(state.trace_spans, trace_id, completed_trace)
        new_active = Map.delete(state.active_traces, trace_id)

        # Log trace completion
        StructuredLogger.log_evaluation_event(
          :trace_completed,
          trace_id,
          "Completed trace for #{trace_data.operation_name} in #{completed_trace.duration_ms}ms",
          result_metadata
        )

        new_state = %{state | active_traces: new_active, trace_spans: new_spans}

        {:noreply, new_state}
    end
  end

  # Private functions

  defp build_tracing_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      # 10% sampling
      sampling_rate: 0.1,
      trace_retention_hours: 24,
      jaeger_enabled: false,
      automatic_instrumentation: true
    }
  end

  defp build_sampling_config(config) do
    %{
      default_rate: Map.get(config, :sampling_rate, 0.1),
      operation_rates: %{
        # Always trace evaluations
        evaluation_submission: 1.0,
        # 50% of processing
        evaluation_processing: 0.5,
        # 1% of dashboard views
        dashboard_rendering: 0.01,
        # 10% of auth events
        authentication: 0.1
      }
    }
  end

  defp should_trace_operation?(operation_name, sampling_config) do
    rate = Map.get(sampling_config.operation_rates, operation_name, sampling_config.default_rate)
    :rand.uniform() <= rate
  end

  defp setup_tracing_handlers do
    # Set up telemetry handlers for automatic span creation
    tracing_events = [
      [:swe_bench, :evaluation, :start],
      [:swe_bench, :evaluation, :stop],
      [:phoenix, :endpoint, :start],
      [:phoenix, :endpoint, :stop],
      [:swe_bench, :repo, :query, :start],
      [:swe_bench, :repo, :query, :stop]
    ]

    :telemetry.attach_many(
      "swe-bench-distributed-tracer",
      tracing_events,
      &handle_tracing_event/4,
      %{}
    )
  end

  defp handle_tracing_event([:swe_bench, :evaluation, :start], _measurements, metadata, _config) do
    # Start evaluation trace
    case start_trace(:evaluation_processing, metadata) do
      {:ok, trace_context} ->
        # Store trace context for correlation
        Process.put(:trace_context, trace_context)

      _ ->
        :ok
    end
  end

  defp handle_tracing_event([:swe_bench, :evaluation, :stop], measurements, metadata, _config) do
    # Complete evaluation trace
    case Process.get(:trace_context) do
      %{trace_id: trace_id} ->
        result_metadata = Map.merge(metadata, measurements)
        complete_trace(trace_id, result_metadata)
        Process.delete(:trace_context)

      _ ->
        :ok
    end
  end

  defp handle_tracing_event([:phoenix, :endpoint, :start], _measurements, metadata, _config) do
    # Start HTTP request span
    case Process.get(:trace_context) do
      %{trace_id: trace_id} ->
        add_span(trace_id, :http_request, metadata)

      _ ->
        # Create new trace for HTTP request
        case start_trace(:http_request, metadata) do
          {:ok, trace_context} ->
            Process.put(:trace_context, trace_context)

          _ ->
            :ok
        end
    end
  end

  defp handle_tracing_event([:swe_bench, :repo, :query, :start], _measurements, metadata, _config) do
    # Start database query span
    case Process.get(:trace_context) do
      %{trace_id: trace_id} ->
        add_span(trace_id, :database_query, Map.take(metadata, [:query, :params]))

      _ ->
        :ok
    end
  end

  defp handle_tracing_event(_event, _measurements, _metadata, _config) do
    # Ignore other events
    :ok
  end

  defp maybe_broadcast_log_event(structured_entry) do
    # Broadcast important log events for real-time monitoring
    case structured_entry.entry.level do
      level when level in [:warning, :error] ->
        :telemetry.execute(
          [:swe_bench, :monitoring, :log_broadcast],
          %{
            level: level,
            severity: level
          },
          structured_entry.metadata
        )

      _ ->
        :ok
    end
  end
end
