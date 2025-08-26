defmodule SweBench.QualityAssurance.QualityValidation do
  @moduledoc """
  Ash resource for quality validation tracking.

  Stores comprehensive quality validation results including automated validation,
  statistical analysis, deduplication scores, and human review consensus.
  """

  use Ash.Resource,
    domain: SweBench.QualityAssurance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "quality_validations"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_validation do
      accept [
        :task_instance_id,
        :validation_stage,
        :quality_score,
        :validation_metadata,
        :validation_status,
        :automated_confidence,
        :statistical_analysis,
        :deduplication_score,
        :human_review_consensus
      ]

      validate compare(:quality_score, greater_than_or_equal_to: 0.0)
      validate compare(:quality_score, less_than_or_equal_to: 1.0)
      validate present([:task_instance_id, :validation_stage])
    end

    update :complete_validation do
      accept [:validation_status, :completion_notes]

      change set_attribute(:validation_status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :update_human_consensus do
      accept [:human_review_consensus, :reviewer_count, :consensus_metadata]
    end

    read :by_validation_stage do
      argument :stage, :atom do
        constraints one_of: [
                      :automated,
                      :statistical,
                      :deduplication,
                      :human_review,
                      :comprehensive
                    ]
      end

      filter expr(validation_stage == ^arg(:stage))
    end

    read :by_quality_threshold do
      argument :min_quality, :decimal, allow_nil?: false
      filter expr(quality_score >= ^arg(:min_quality))
    end

    read :pending_validations do
      filter expr(validation_status == :pending)
      prepare build(sort: [created_at: :asc])
    end

    read :completed_validations do
      filter expr(validation_status == :completed)
      prepare build(sort: [quality_score: :desc])
    end

    read :requiring_review do
      filter expr(validation_stage == :human_review and validation_status == :pending)
      prepare build(sort: [created_at: :asc])
    end

    read :by_task_instance do
      argument :task_instance_id, :uuid, allow_nil?: false
      filter expr(task_instance_id == ^arg(:task_instance_id))
    end
  end

  validations do
    validate present([:task_instance_id, :validation_stage, :quality_score]) do
      message "Task instance, validation stage, and quality score are required"
    end

    validate compare(:quality_score, greater_than_or_equal_to: 0.0) do
      message "Quality score cannot be negative"
    end

    validate compare(:quality_score, less_than_or_equal_to: 1.0) do
      message "Quality score cannot exceed 1.0"
    end

    validate compare(:reviewer_count, greater_than_or_equal_to: 0) do
      message "Reviewer count cannot be negative"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :task_instance_id, :uuid do
      description "Reference to the validated task instance"
      allow_nil? false
    end

    attribute :validation_stage, :atom do
      description "Stage of validation performed"
      allow_nil? false

      constraints one_of: [
                    :automated,
                    :statistical,
                    :deduplication,
                    :human_review,
                    :comprehensive
                  ]
    end

    # Quality scores and metrics
    attribute :quality_score, :decimal do
      description "Overall quality score (0.0-1.0)"
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :automated_confidence, :decimal do
      description "Confidence score from automated validation"
      constraints min: 0.0, max: 1.0
    end

    attribute :statistical_analysis, :map do
      description "Statistical analysis results and metrics"
      default %{}
    end

    attribute :deduplication_score, :decimal do
      description "Deduplication analysis score"
      constraints min: 0.0, max: 1.0
    end

    attribute :human_review_consensus, :decimal do
      description "Human reviewer consensus score"
      constraints min: 0.0, max: 1.0
    end

    attribute :reviewer_count, :integer do
      description "Number of human reviewers who validated this instance"
      default 0
      constraints min: 0
    end

    # Validation metadata and status
    attribute :validation_metadata, :map do
      description "Detailed validation data and analysis results"
      default %{}
    end

    attribute :consensus_metadata, :map do
      description "Human review consensus tracking data"
      default %{}
    end

    attribute :validation_status, :atom do
      description "Current validation status"
      default :pending
      constraints one_of: [:pending, :in_progress, :completed, :failed, :requires_review]
    end

    attribute :completion_notes, :string do
      description "Notes from validation completion"
    end

    # Performance and processing
    attribute :processing_time_ms, :integer do
      description "Total validation processing time in milliseconds"
      constraints min: 0
    end

    attribute :validation_errors, {:array, :string} do
      description "List of validation errors encountered"
      default []
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :completed_at, :utc_datetime do
      description "When validation was completed"
    end
  end

  relationships do
    belongs_to :task_instance, SweBench.TaskInstances.TaskInstance do
      destination_attribute :id
      source_attribute :task_instance_id
      allow_nil? false
    end

    has_many :review_sessions, SweBench.QualityAssurance.ReviewSession do
      destination_attribute :quality_validation_id
    end

    has_many :deduplication_matches, SweBench.QualityAssurance.DeduplicationResult do
      destination_attribute :primary_task_id
    end
  end

  calculations do
    calculate :overall_confidence, :decimal do
      description "Combined confidence score from all validation stages"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          weights = %{automated: 0.4, statistical: 0.2, deduplication: 0.2, human_review: 0.2}

          base_confidence = record.quality_score || 0.0
          automated_weight = (record.automated_confidence || 0.0) * weights.automated
          human_weight = (record.human_review_consensus || 0.0) * weights.human_review

          base_confidence * 0.6 + automated_weight + human_weight
        end)
      end
    end

    calculate :validation_completeness, :decimal do
      description "Percentage of validation stages completed"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          stages_completed = count_completed_validation_stages(record)

          # automated, statistical, deduplication, human_review

          total_stages = 4

          stages_completed / total_stages
        end)
      end
    end

    calculate :quality_tier_recommendation, :atom do
      description "Recommended quality tier based on validation results"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          overall_score = record.quality_score || 0.0
          consensus = record.human_review_consensus || 0.0

          cond do
            overall_score >= 0.9 and consensus >= 0.9 -> :gold
            overall_score >= 0.8 and consensus >= 0.8 -> :silver
            overall_score >= 0.7 and consensus >= 0.7 -> :bronze
            true -> :needs_improvement
          end
        end)
      end
    end
  end

  # Helper function for completeness calculation
  defp count_completed_validation_stages(record) do
    stages = [
      record.automated_confidence != nil,
      record.statistical_analysis != %{},
      record.deduplication_score != nil,
      record.human_review_consensus != nil
    ]

    Enum.count(stages, & &1)
  end
end
