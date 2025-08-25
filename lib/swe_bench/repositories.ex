defmodule SweBench.Repositories do
  @moduledoc """
  Domain for GitHub repository data management.

  Handles repository analysis, metadata storage, and relationship
  management for the SWE-bench-Elixir evaluation system.
  """

  use Ash.Domain

  resources do
    resource SweBench.Repositories.Repository
    resource SweBench.Repositories.MiningJob
    resource SweBench.Repositories.QualityMetrics
  end
end
