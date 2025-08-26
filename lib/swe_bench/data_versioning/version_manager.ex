defmodule SweBench.DataVersioning.VersionManager do
  @moduledoc """
  Version management for benchmark datasets.

  Handles semantic versioning, compatibility tracking, and version
  metadata management for dataset evolution and release coordination.
  """

  use GenServer
  require Logger

  alias SweBench.TaskInstances.DatasetRelease

  defstruct [
    :current_version,
    :version_history,
    :compatibility_matrix,
    :version_statistics
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current dataset version.
  """
  def get_current_version do
    GenServer.call(__MODULE__, :get_current_version)
  end

  @doc """
  Lists all dataset versions with metadata.
  """
  def list_versions(opts) do
    GenServer.call(__MODULE__, {:list_versions, opts})
  end

  @doc """
  Gets compatibility matrix for a version.
  """
  def get_compatibility_matrix(version) do
    GenServer.call(__MODULE__, {:get_compatibility_matrix, version})
  end

  @impl true
  def init(_opts) do
    current_version = load_current_version()
    version_history = load_version_history()
    compatibility_matrix = load_compatibility_matrix()

    state = %__MODULE__{
      current_version: current_version,
      version_history: version_history,
      compatibility_matrix: compatibility_matrix,
      version_statistics: %{}
    }

    Logger.info("Version manager started with current version: #{current_version}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_current_version, _from, state) do
    {:reply, state.current_version, state}
  end

  @impl true
  def handle_call({:list_versions, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)

    versions =
      DatasetRelease
      |> Ash.Query.for_read(:published_releases)
      |> Ash.Query.limit(limit)
      |> Ash.read!()

    {:reply, versions, state}
  end

  @impl true
  def handle_call({:get_compatibility_matrix, version}, _from, state) do
    compatibility = Map.get(state.compatibility_matrix, version, %{})
    {:reply, compatibility, state}
  end

  # Private implementation functions

  defp load_current_version do
    case DatasetRelease
         |> Ash.Query.for_read(:published_releases)
         |> Ash.Query.limit(1)
         |> Ash.read() do
      {:ok, [latest | _]} -> latest.version
      _ -> "0.0.0"
    end
  end

  defp load_version_history do
    case DatasetRelease
         |> Ash.Query.for_read(:published_releases)
         |> Ash.Query.limit(100)
         |> Ash.read() do
      {:ok, releases} -> releases
      _ -> []
    end
  end

  defp load_compatibility_matrix do
    # Placeholder - will load from configuration or database
    %{}
  end
end
