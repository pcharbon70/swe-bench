defmodule SweBench.DataExport.ExportManager do
  @moduledoc """
  Export job management and coordination.

  Manages large dataset export operations with progress tracking,
  format conversion, and performance optimization.
  """

  use GenServer
  require Logger

  defstruct [
    :active_exports,
    :completed_exports,
    :failed_exports,
    :export_statistics
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts an export job.
  """
  def start_export(format, opts) do
    GenServer.call(__MODULE__, {:start_export, format, opts})
  end

  @doc """
  Gets export progress for a specific job.
  """
  def get_progress(export_id) do
    GenServer.call(__MODULE__, {:get_progress, export_id})
  end

  @doc """
  Gets export statistics and performance metrics.
  """
  def get_export_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Estimates export size and duration.
  """
  def estimate_export(format, filters) do
    GenServer.call(__MODULE__, {:estimate_export, format, filters})
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_exports: %{},
      completed_exports: [],
      failed_exports: [],
      export_statistics: %{
        total_exports: 0,
        successful_exports: 0,
        avg_export_time: 0.0,
        total_data_exported_mb: 0
      }
    }

    Logger.info("Export manager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_export, format, opts}, _from, state) do
    export_id = generate_export_id()

    export_job = %{
      id: export_id,
      format: format,
      filters: Map.get(opts, :filters, %{}),
      options: opts,
      status: :starting,
      progress: 0.0,
      started_at: DateTime.utc_now(),
      estimated_completion: estimate_completion_time(format, opts)
    }

    # Start the actual export process
    case start_export_process(export_job) do
      {:ok, pid} ->
        updated_job = Map.put(export_job, :pid, pid)
        updated_state = %{state | active_exports: Map.put(state.active_exports, export_id, updated_job)}

        {:reply, {:ok, %{export_id: export_id, estimated_completion: export_job.estimated_completion}}, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_progress, export_id}, _from, state) do
    case Map.get(state.active_exports, export_id) do
      nil ->
        # Check completed exports
        completed_export = Enum.find(state.completed_exports, &(&1.id == export_id))
        {:reply, completed_export, state}

      active_export ->
        {:reply, active_export, state}
    end
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, state.export_statistics, state}
  end

  @impl true
  def handle_call({:estimate_export, format, filters}, _from, state) do
    estimation = calculate_export_estimation(format, filters)
    {:reply, estimation, state}
  end

  @impl true
  def handle_info({:export_completed, export_id, result}, state) do
    Logger.info("Export #{export_id} completed")

    case Map.pop(state.active_exports, export_id) do
      {nil, _} ->
        {:noreply, state}

      {export_job, remaining_exports} ->
        completed_job = Map.merge(export_job, %{
          status: :completed,
          completed_at: DateTime.utc_now(),
          result: result
        })

        updated_statistics = update_export_statistics(state.export_statistics, completed_job)

        updated_state = %{
          state
          | active_exports: remaining_exports,
            completed_exports: [completed_job | state.completed_exports],
            export_statistics: updated_statistics
        }

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:export_failed, export_id, reason}, state) do
    Logger.error("Export #{export_id} failed: #{inspect(reason)}")

    case Map.pop(state.active_exports, export_id) do
      {nil, _} ->
        {:noreply, state}

      {export_job, remaining_exports} ->
        failed_job = Map.merge(export_job, %{
          status: :failed,
          failed_at: DateTime.utc_now(),
          error: reason
        })

        updated_state = %{
          state
          | active_exports: remaining_exports,
            failed_exports: [failed_job | state.failed_exports]
        }

        {:noreply, updated_state}
    end
  end

  # Private implementation functions

  defp start_export_process(export_job) do
    # Placeholder - will start actual export pipeline
    Logger.debug("Starting export process for job #{export_job.id}")

    {:ok, spawn_link(fn ->
      # Simulate export work
      Process.sleep(1000)
      send(self(), {:export_completed, export_job.id, %{files_created: 1, size_mb: 10}})
    end)}
  end

  defp estimate_completion_time(format, opts) do
    # Estimate based on format and data size
    base_time_minutes = 
      case format do
        :json -> 5
        :csv -> 3
        :parquet -> 8
        _ -> 5
      end

    # Add time based on filters (more data = more time)
    filter_complexity = calculate_filter_complexity(Map.get(opts, :filters, %{}))
    
    estimated_minutes = base_time_minutes + filter_complexity
    
    DateTime.add(DateTime.utc_now(), estimated_minutes * 60, :second)
  end

  defp calculate_filter_complexity(filters) do
    # Simple complexity calculation based on filter count
    map_size(filters)
  end

  defp calculate_export_estimation(format, filters) do
    # Estimate export size and duration
    estimated_records = estimate_record_count(filters)
    
    size_per_record_kb = 
      case format do
        :json -> 2.5
        :csv -> 0.5
        :parquet -> 1.0
        _ -> 2.0
      end

    estimated_size_mb = (estimated_records * size_per_record_kb) / 1024

    %{
      estimated_records: estimated_records,
      estimated_size_mb: round(estimated_size_mb),
      estimated_duration_minutes: round(estimated_size_mb / 10),  # ~10MB/minute processing
      format: format
    }
  end

  defp estimate_record_count(filters) do
    # Placeholder - will count actual records based on filters
    base_count = 10_000

    # Adjust based on filters
    quality_filter = Map.get(filters, :quality_tier)
    
    case quality_filter do
      :gold -> round(base_count * 0.3)
      :silver -> round(base_count * 0.4)
      :bronze -> round(base_count * 0.3)
      _ -> base_count
    end
  end

  defp update_export_statistics(current_stats, completed_job) do
    new_total = current_stats.total_exports + 1
    new_successful = current_stats.successful_exports + 1

    processing_time_minutes = 
      DateTime.diff(completed_job.completed_at, completed_job.started_at) / 60

    new_avg_time = 
      if new_total > 1 do
        ((current_stats.avg_export_time * (new_total - 1)) + processing_time_minutes) / new_total
      else
        processing_time_minutes
      end

    data_exported_mb = get_in(completed_job, [:result, :size_mb]) || 0

    %{
      current_stats
      | total_exports: new_total,
        successful_exports: new_successful,
        avg_export_time: new_avg_time,
        total_data_exported_mb: current_stats.total_data_exported_mb + data_exported_mb
    }
  end

  defp generate_export_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end