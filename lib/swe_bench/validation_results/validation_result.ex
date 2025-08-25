defmodule SweBench.ValidationResults.ValidationResult do
  @moduledoc """
  Ash resource for test transition validation results.

  Stores comprehensive validation data including test transitions, quality metrics,
  and confidence scores for benchmark task suitability assessment.
  """

  use Ash.Resource,
    domain: SweBench.ValidationResults,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "validation_results"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_validation do
      accept [
        :issue_pr_link_id,
        :repository_id,
        :base_commit_sha,
        :patch_sha256,
        :validation_runs,
        :consistency_score,
        :confidence_level,
        :benchmark_quality,
        :fail_to_pass_count,
        :pass_to_pass_count,
        :pass_to_fail_count,
        :flaky_tests,
        :validation_metadata
      ]

      validate compare(:consistency_score, greater_than_or_equal_to: 0.0)
      validate compare(:consistency_score, less_than_or_equal_to: 1.0)
      validate compare(:confidence_level, greater_than_or_equal_to: 0.0)
      validate compare(:confidence_level, less_than_or_equal_to: 1.0)
    end

    update :update_quality do
      accept [:benchmark_quality, :confidence_level, :validation_metadata]
    end

    read :by_quality_tier do
      argument :tier, :atom do
        constraints one_of: [:gold, :silver, :bronze, :unsuitable]
      end

      filter expr(benchmark_quality == ^arg(:tier))
    end

    read :by_confidence_threshold do
      argument :min_confidence, :decimal, allow_nil?: false
      filter expr(confidence_level >= ^arg(:min_confidence))
    end

    read :suitable_for_benchmark do
      filter expr(benchmark_quality in [:gold, :silver, :bronze])
      prepare build(sort: [confidence_level: :desc])
    end

    read :by_repository do
      argument :repository_id, :uuid, allow_nil?: false
      filter expr(repository_id == ^arg(:repository_id))
    end

    read :failed_validations do
      filter expr(benchmark_quality == :unsuitable)
      prepare build(sort: [created_at: :desc])
    end

    read :recent_validations do
      filter expr(created_at > ago(7, :day))
      prepare build(sort: [created_at: :desc])
    end
  end

  validations do
    validate compare(:consistency_score, greater_than_or_equal_to: 0.0) do
      message "Consistency score cannot be negative"
    end

    validate compare(:confidence_level, greater_than_or_equal_to: 0.0) do
      message "Confidence level cannot be negative"
    end

    validate compare(:fail_to_pass_count, greater_than_or_equal_to: 0) do
      message "FAIL_TO_PASS count cannot be negative"
    end

    validate present([:issue_pr_link_id, :repository_id, :base_commit_sha]) do
      message "Issue-PR link, repository, and commit references are required"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :issue_pr_link_id, :uuid do
      description "Reference to the validated issue-PR relationship"
      allow_nil? false
    end

    attribute :repository_id, :uuid do
      description "Repository containing the validated issue-PR pair"
      allow_nil? false
    end

    attribute :base_commit_sha, :string do
      description "Base commit SHA where validation was performed"
      allow_nil? false
      constraints max_length: 40
    end

    attribute :patch_sha256, :string do
      description "SHA256 hash of the applied patch for caching"
      allow_nil? false
      constraints max_length: 64
    end

    # Validation execution data
    attribute :validation_runs, :integer do
      description "Number of validation runs performed"
      default 3
      constraints min: 1, max: 10
    end

    attribute :consistency_score, :decimal do
      description "Consistency score across multiple validation runs"
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :confidence_level, :decimal do
      description "Statistical confidence level for the validation"
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :benchmark_quality, :atom do
      description "Quality tier classification for benchmark suitability"
      allow_nil? false
      constraints one_of: [:gold, :silver, :bronze, :unsuitable]
    end

    # Test transition counts
    attribute :fail_to_pass_count, :integer do
      description "Number of tests that transitioned from FAIL to PASS"
      default 0
      constraints min: 0
    end

    attribute :pass_to_pass_count, :integer do
      description "Number of tests that remained PASS"
      default 0
      constraints min: 0
    end

    attribute :pass_to_fail_count, :integer do
      description "Number of tests that regressed from PASS to FAIL"
      default 0
      constraints min: 0
    end

    # Quality indicators
    attribute :flaky_tests, {:array, :string} do
      description "List of tests identified as flaky or non-deterministic"
      default []
    end

    attribute :compilation_success, :boolean do
      description "Whether the patched code compiled successfully"
      default true
    end

    attribute :execution_time_ms, :integer do
      description "Total validation execution time in milliseconds"
      constraints min: 0
    end

    # Metadata and debugging
    attribute :validation_metadata, :map do
      description "Detailed validation data for debugging and analysis"
      default %{}
    end

    attribute :error_details, :map do
      description "Error details if validation failed"
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :issue_pr_link, SweBench.Issues.IssuePrLink do
      destination_attribute :id
      source_attribute :issue_pr_link_id
      allow_nil? false
    end

    belongs_to :repository, SweBench.Repositories.Repository do
      destination_attribute :id
      source_attribute :repository_id
      allow_nil? false
    end
  end

  calculations do
    calculate :total_tests, :integer do
      description "Total number of tests analyzed"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          (record.fail_to_pass_count || 0) +
            (record.pass_to_pass_count || 0) +
            (record.pass_to_fail_count || 0)
        end)
      end
    end

    calculate :transition_ratio, :decimal do
      description "Ratio of transitioning tests to total tests"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          total_tests =
            (record.fail_to_pass_count || 0) +
              (record.pass_to_pass_count || 0) +
              (record.pass_to_fail_count || 0)

          if total_tests > 0 do
            (record.fail_to_pass_count || 0) / total_tests
          else
            0.0
          end
        end)
      end
    end

    calculate :quality_score, :decimal do
      description "Overall quality score combining confidence and consistency"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          base_score =
            (record.confidence_level || 0.0) * 0.7 +
              (record.consistency_score || 0.0) * 0.3

          # Penalty for regressions
          regression_penalty = min(0.2, (record.pass_to_fail_count || 0) * 0.05)

          max(0.0, base_score - regression_penalty)
        end)
      end
    end
  end
end
