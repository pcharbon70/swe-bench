defmodule SweBench.Issues.IssuePrLink do
  @moduledoc """
  Ash resource for sophisticated issue-PR relationships with confidence scoring.

  Stores relationships between issues and PRs with automated and manual
  validation, confidence scoring, and relationship type classification.
  """

  use Ash.Resource,
    domain: SweBench.Issues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "issue_pr_links"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_link do
      accept [
        :issue_id,
        :pull_request_id,
        :repository_id,
        :relationship_type,
        :confidence_score,
        :detection_method,
        :analysis_metadata,
        :validation_status
      ]

      validate attribute_does_not_equal(:confidence_score, 0.0)
      validate compare(:confidence_score, greater_than_or_equal_to: 0.0)
      validate compare(:confidence_score, less_than_or_equal_to: 1.0)
    end

    update :validate_link do
      accept [:validation_status, :manual_validation_notes, :confidence_score]

      change set_attribute(:validation_status, :validated)
      change set_attribute(:validated_at, &DateTime.utc_now/0)
    end

    update :reject_link do
      accept [:validation_status, :manual_validation_notes]

      change set_attribute(:validation_status, :rejected)
      change set_attribute(:rejected_at, &DateTime.utc_now/0)
    end

    read :by_confidence_threshold do
      argument :min_confidence, :decimal, allow_nil?: false
      filter expr(confidence_score >= ^arg(:min_confidence))
    end

    read :by_relationship_type do
      argument :type, :atom, allow_nil?: false
      filter expr(relationship_type == ^arg(:type))
    end

    read :pending_validation do
      filter expr(validation_status == :pending)
      prepare build(sort: [confidence_score: :desc])
    end

    read :validated_links do
      filter expr(validation_status == :validated)
      prepare build(sort: [confidence_score: :desc])
    end

    read :high_confidence do
      filter expr(confidence_score >= 0.8)
      prepare build(sort: [confidence_score: :desc])
    end

    read :by_repository do
      argument :repository_id, :uuid, allow_nil?: false
      filter expr(repository_id == ^arg(:repository_id))
    end
  end

  validations do
    validate compare(:confidence_score, greater_than_or_equal_to: 0.0) do
      message "Confidence score cannot be negative"
    end

    validate compare(:confidence_score, less_than_or_equal_to: 1.0) do
      message "Confidence score cannot exceed 1.0"
    end

    validate present([:issue_id, :pull_request_id, :repository_id]) do
      message "Issue, PR, and repository references are required"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :repository_id, :uuid do
      description "Repository containing the issue and PR"
      allow_nil? false
    end

    attribute :issue_id, :uuid do
      description "Reference to the linked issue"
      allow_nil? false
    end

    attribute :pull_request_id, :uuid do
      description "Reference to the linked pull request"
      allow_nil? false
    end

    # Relationship classification
    attribute :relationship_type, :atom do
      description "Type of relationship between issue and PR"
      allow_nil? false
      constraints one_of: [:fixes, :addresses, :references, :closes, :related_to, :implements]
    end

    # Confidence and validation
    attribute :confidence_score, :decimal do
      description "Confidence score for the relationship (0.0-1.0)"
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :detection_method, :atom do
      description "Primary method used to detect the relationship"
      allow_nil? false

      constraints one_of: [
                    :commit_message,
                    :pr_description,
                    :code_analysis,
                    :semantic_similarity,
                    :temporal_proximity,
                    :manual
                  ]
    end

    attribute :validation_status, :atom do
      description "Current validation status of the relationship"
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :validated, :rejected, :uncertain, :requires_review]
    end

    # Analysis metadata for debugging and improvement
    attribute :analysis_metadata, :map do
      description "Detailed analysis data and evidence for the relationship"
      default %{}
    end

    attribute :manual_validation_notes, :string do
      description "Notes from manual validation process"
    end

    attribute :quality_score, :decimal do
      description "Overall quality score combining confidence and validation"
      constraints min: 0.0, max: 1.0
    end

    # Detection evidence
    attribute :matching_evidence, :map do
      description "Evidence used for relationship detection"
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :validated_at, :utc_datetime do
      description "When the relationship was validated"
    end

    attribute :rejected_at, :utc_datetime do
      description "When the relationship was rejected"
    end
  end

  relationships do
    belongs_to :repository, SweBench.Repositories.Repository do
      destination_attribute :id
      source_attribute :repository_id
      allow_nil? false
    end

    belongs_to :issue, SweBench.Issues.Issue do
      destination_attribute :id
      source_attribute :issue_id
      allow_nil? false
    end

    belongs_to :pull_request, SweBench.Issues.PullRequest do
      destination_attribute :id
      source_attribute :pull_request_id
      allow_nil? false
    end
  end

  calculations do
    calculate :quality_tier, :atom do
      description "Quality tier based on confidence and validation"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case {record.confidence_score, record.validation_status} do
            {score, :validated} when score >= 0.9 -> :excellent
            {score, :validated} when score >= 0.8 -> :high
            {score, :validated} when score >= 0.7 -> :good
            {score, :validated} when score >= 0.6 -> :medium
            {score, :validated} -> :low
            {score, _} when score >= 0.8 -> :unvalidated_high
            {score, _} when score >= 0.6 -> :unvalidated_medium
            _ -> :unvalidated_low
          end
        end)
      end
    end

    calculate :relationship_strength, :decimal do
      description "Combined relationship strength metric"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          base_score = record.confidence_score || 0.0

          validation_multiplier =
            case record.validation_status do
              :validated -> 1.0
              :pending -> 0.8
              :uncertain -> 0.6
              :rejected -> 0.0
              _ -> 0.7
            end

          base_score * validation_multiplier
        end)
      end
    end
  end

  identities do
    identity :unique_issue_pr, [:issue_id, :pull_request_id]
  end
end
