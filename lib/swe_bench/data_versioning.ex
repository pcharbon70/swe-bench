defmodule SweBench.DataVersioning do
  @moduledoc """
  Main interface for dataset version management.

  Provides semantic versioning, incremental synchronization, and release
  coordination for benchmark dataset evolution and management.
  """

  alias SweBench.DataVersioning.{ReleaseCoordinator, VersionManager}

  @doc """
  Creates a new dataset release with semantic versioning.

  ## Parameters
    - version: Semantic version string (e.g., "1.2.0")
    - config: Release configuration and metadata

  ## Examples
      iex> SweBench.DataVersioning.create_release("1.2.0", %{type: :minor})
      {:ok, %DatasetRelease{version: "1.2.0"}}
  """
  def create_release(version, config \\ %{}) do
    ReleaseCoordinator.create_release(version, config)
  end

  @doc """
  Gets current dataset version and metadata.
  """
  def get_current_version do
    VersionManager.get_current_version()
  end

  @doc """
  Detects changes since a specific version.
  """
  def detect_changes_since(since_version) do
    ReleaseCoordinator.detect_changes(since_version)
  end

  @doc """
  Lists available dataset versions with metadata.
  """
  def list_versions(opts \\ []) do
    VersionManager.list_versions(opts)
  end

  @doc """
  Gets version compatibility matrix.
  """
  def get_compatibility_matrix(version) do
    VersionManager.get_compatibility_matrix(version)
  end

  @doc """
  Performs incremental synchronization since last version.
  """
  def perform_incremental_sync do
    ReleaseCoordinator.perform_incremental_sync()
  end
end
