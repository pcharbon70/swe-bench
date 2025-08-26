defmodule SweBench.TaskInstances do
  @moduledoc """
  Domain for SWE-bench task instance generation and management.

  Handles task instance creation, quality assessment, and dataset packaging
  for the SWE-bench-Elixir evaluation system.
  """

  use Ash.Domain

  resources do
    resource SweBench.TaskInstances.TaskInstance
    resource SweBench.TaskInstances.GenerationJob
    resource SweBench.TaskInstances.DatasetRelease
  end
end
