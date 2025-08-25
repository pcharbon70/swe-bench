defmodule SweBench.TaskGeneration.Packager do
  @moduledoc """
  Dataset packaging and release management.

  Handles compression, versioning, and distribution of task instance
  collections into standardized SWE-bench dataset releases.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a dataset package from task instances.
  """
  def create_dataset_package(instance_query, opts \\ []) do
    GenServer.call(__MODULE__, {:create_package, instance_query, opts})
  end

  @doc """
  Gets packaging statistics.
  """
  def get_packaging_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      packages_created: 0,
      total_instances_packaged: 0,
      avg_package_time: 0.0
    }

    Logger.info("Dataset packager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_package, instance_query, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      instance_query
      |> collect_instances_for_packaging()
      |> generate_package_metadata(opts)
      |> create_compressed_package(opts)
      |> validate_package_integrity()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_packaging_stats(state, result, processing_time)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private implementation functions

  defp collect_instances_for_packaging(instance_query) do
    Logger.debug("Collecting instances for packaging")

    case Ash.read(instance_query) do
      {:ok, instances} ->
        Logger.info("Collected #{length(instances)} instances for packaging")
        {:ok, instances}

      {:error, reason} ->
        {:error, {:collection_failed, reason}}
    end
  end

  defp generate_package_metadata({:ok, instances}, opts) do
    Logger.debug("Generating package metadata")

    version = Keyword.get(opts, :version, generate_auto_version())

    metadata = %{
      version: version,
      created_at: DateTime.utc_now(),
      instance_count: length(instances),
      quality_distribution: calculate_quality_distribution(instances),
      difficulty_distribution: calculate_difficulty_distribution(instances),
      format_version: "swe-bench-elixir-1.0",
      generator_version: "1.0.0"
    }

    {:ok, {instances, metadata}}
  end

  defp generate_package_metadata({:error, reason}, _opts) do
    {:error, reason}
  end

  defp create_compressed_package({:ok, {instances, metadata}}, opts) do
    Logger.debug("Creating compressed package")

    # Placeholder implementation - will create actual compressed packages
    package_data = %{
      metadata: metadata,
      instances: instances,
      compression: "placeholder"
    }

    {:ok, {instances, metadata, package_data}}
  end

  defp create_compressed_package({:error, reason}, _opts) do
    {:error, reason}
  end

  defp validate_package_integrity({:ok, {instances, metadata, package_data}}) do
    Logger.debug("Validating package integrity")

    # Basic integrity validation
    integrity_result = %{
      instance_count_match: length(instances) == metadata.instance_count,
      metadata_complete: validate_metadata_completeness(metadata),
      # Placeholder
      package_valid: true
    }

    if Enum.all?(Map.values(integrity_result)) do
      {:ok, {instances, metadata, package_data, integrity_result}}
    else
      {:error, {:integrity_validation_failed, integrity_result}}
    end
  end

  defp validate_package_integrity({:error, reason}) do
    {:error, reason}
  end

  defp calculate_quality_distribution(instances) do
    instances
    |> Enum.group_by(& &1.quality_tier)
    |> Enum.map(fn {tier, group} -> {tier, length(group)} end)
    |> Map.new()
  end

  defp calculate_difficulty_distribution(instances) do
    instances
    |> Enum.group_by(& &1.difficulty_level)
    |> Enum.map(fn {level, group} -> {level, length(group)} end)
    |> Map.new()
  end

  defp validate_metadata_completeness(metadata) do
    required_fields = [:version, :instance_count, :format_version]
    Enum.all?(required_fields, &Map.has_key?(metadata, &1))
  end

  defp generate_auto_version do
    date = Date.utc_today()
    "#{date.year}.#{date.month}.#{date.day}"
  end

  defp update_packaging_stats(state, result, processing_time) do
    new_packages = state.packages_created + 1

    instance_count =
      case result do
        {:ok, {instances, _metadata, _package, _integrity}} -> length(instances)
        _ -> 0
      end

    new_total_instances = state.total_instances_packaged + instance_count

    new_avg_time =
      if new_packages > 1 do
        (state.avg_package_time * (new_packages - 1) + processing_time) / new_packages
      else
        processing_time
      end

    %{
      state
      | packages_created: new_packages,
        total_instances_packaged: new_total_instances,
        avg_package_time: new_avg_time
    }
  end
end
