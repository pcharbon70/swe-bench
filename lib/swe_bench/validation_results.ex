defmodule SweBench.ValidationResults do
  @moduledoc """
  Domain for test transition validation results.

  Handles validation result storage, quality assessment, and metrics
  for the test transition validation system.
  """

  use Ash.Domain

  resources do
    resource SweBench.ValidationResults.ValidationResult
  end
end