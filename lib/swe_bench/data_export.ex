defmodule SweBench.DataExport do
  @moduledoc """
  Main interface for data export operations.

  Provides high-performance export capabilities with multiple formats,
  compression, and streaming processing for large benchmark datasets.
  """

  alias SweBench.DataExport.ExportManager

  @doc """
  Starts an export job for dataset extraction.

  ## Parameters
    - format: Export format (:json, :csv, :parquet)
    - opts: Export configuration and filters

  ## Examples
      iex> SweBench.DataExport.start_export(:json, %{quality_tier: :gold})
      {:ok, %{export_id: "abc123", estimated_size: "50MB"}}
  """
  def start_export(format, opts \\ %{}) do
    ExportManager.start_export(format, opts)
  end

  @doc """
  Gets export job progress and status.
  """
  def get_export_progress(export_id) do
    ExportManager.get_progress(export_id)
  end

  @doc """
  Lists available export formats and capabilities.
  """
  def list_export_formats do
    %{
      json: %{
        description: "JSON format compatible with SWE-bench",
        compression: ["gzip", "lz4"],
        max_size_gb: 10
      },
      csv: %{
        description: "CSV format for analysis and reporting",
        compression: ["gzip"],
        max_size_gb: 5
      },
      parquet: %{
        description: "Parquet format for efficient analytics",
        compression: ["snappy", "gzip"],
        max_size_gb: 20
      }
    }
  end

  @doc """
  Gets export statistics and performance metrics.
  """
  def get_export_statistics do
    ExportManager.get_export_statistics()
  end

  @doc """
  Estimates export size and duration for planning.
  """
  def estimate_export(format, filters) do
    ExportManager.estimate_export(format, filters)
  end
end
