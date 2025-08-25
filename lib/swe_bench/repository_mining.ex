defmodule SweBench.RepositoryMining do
  @moduledoc """
  Main interface for repository mining infrastructure.

  Provides automated repository discovery and analysis capabilities for generating
  high-quality benchmark tasks from real-world Elixir repositories.
  """

  alias SweBench.RepositoryMining.Coordinator

  @doc """
  Starts a new repository mining operation.

  ## Parameters
    - source: :hex_pm | :github_trending | :manual_list
    - params: Configuration for mining operation

  ## Examples
      iex> SweBench.RepositoryMining.start_mining(:hex_pm, %{max_repositories: 50})
      {:ok, %MiningJob{}}
  """
  def start_mining(source, params \\ %{}) do
    Coordinator.queue_mining_job(source, params)
  end

  @doc """
  Gets current mining statistics and progress.
  """
  def get_mining_status do
    Coordinator.get_mining_status()
  end

  @doc """
  Lists discovered repositories with quality scores.
  """
  def list_discovered_repositories(opts \\ []) do
    SweBench.Repositories.Repository
    |> Ash.Query.for_read(:recently_mined)
    |> Ash.Query.limit(Keyword.get(opts, :limit, 100))
    |> Ash.read()
  end

  @doc """
  Gets repository quality breakdown by category.
  """
  def get_quality_distribution do
    Coordinator.get_quality_distribution()
  end
end