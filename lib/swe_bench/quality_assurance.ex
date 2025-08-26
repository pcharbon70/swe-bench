defmodule SweBench.QualityAssurance do
  @moduledoc """
  Domain for quality assurance and validation.

  Handles comprehensive quality validation, statistical analysis, deduplication,
  and human review for ensuring benchmark dataset excellence.
  """

  use Ash.Domain

  resources do
    resource SweBench.QualityAssurance.QualityValidation
    resource SweBench.QualityAssurance.StatisticalAnalysis
    resource SweBench.QualityAssurance.DeduplicationResult
    resource SweBench.QualityAssurance.ReviewSession
  end
end
