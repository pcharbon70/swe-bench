defmodule SweBench.QualityAssurance.ReviewSession do
  @moduledoc """
  Ash resource for human review sessions.

  Tracks individual reviewer assessments including quality ratings,
  review notes, and consensus tracking for inter-rater reliability.
  """

  use Ash.Resource,
    domain: SweBench.QualityAssurance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "quality_review_sessions"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_review do
      accept [
        :quality_validation_id,
        :task_instance_id,
        :reviewer_id,
        :quality_rating,
        :clarity_rating,
        :correctness_rating,
        :difficulty_rating,
        :review_notes,
        :confidence_level
      ]

      validate compare(:quality_rating, greater_than_or_equal_to: 1)
      validate compare(:quality_rating, less_than_or_equal_to: 5)
      validate present([:task_instance_id, :reviewer_id, :quality_rating])
    end

    update :complete_review do
      accept [:review_status, :review_duration_seconds, :completion_notes]

      change set_attribute(:review_status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :by_reviewer do
      argument :reviewer_id, :uuid, allow_nil?: false
      filter expr(reviewer_id == ^arg(:reviewer_id))
    end

    read :by_task_instance do
      argument :task_instance_id, :uuid, allow_nil?: false
      filter expr(task_instance_id == ^arg(:task_instance_id))
    end

    read :pending_reviews do
      filter expr(review_status == :pending)
      prepare build(sort: [created_at: :asc])
    end

    read :completed_reviews do
      filter expr(review_status == :completed)
      prepare build(sort: [completed_at: :desc])
    end

    read :high_confidence_reviews do
      filter expr(confidence_level >= 0.8)
      prepare build(sort: [confidence_level: :desc])
    end
  end

  validations do
    validate present([:task_instance_id, :reviewer_id, :quality_rating]) do
      message "Task instance, reviewer, and quality rating are required"
    end

    validate compare(:quality_rating, greater_than_or_equal_to: 1) do
      message "Quality rating must be at least 1"
    end

    validate compare(:quality_rating, less_than_or_equal_to: 5) do
      message "Quality rating cannot exceed 5"
    end

    validate compare(:review_duration_seconds, greater_than_or_equal_to: 0) do
      message "Review duration cannot be negative"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :quality_validation_id, :uuid do
      description "Reference to the quality validation record"
      allow_nil? false
    end

    attribute :task_instance_id, :uuid do
      description "Reference to the reviewed task instance"
      allow_nil? false
    end

    attribute :reviewer_id, :uuid do
      description "Reference to the reviewer user"
      allow_nil? false
    end

    # Rating scores (1-5 scale)
    attribute :quality_rating, :integer do
      description "Overall quality rating (1-5 scale)"
      allow_nil? false
      constraints min: 1, max: 5
    end

    attribute :clarity_rating, :integer do
      description "Problem statement clarity rating (1-5 scale)"
      constraints min: 1, max: 5
    end

    attribute :correctness_rating, :integer do
      description "Solution correctness rating (1-5 scale)"
      constraints min: 1, max: 5
    end

    attribute :difficulty_rating, :integer do
      description "Task difficulty rating (1-5 scale)"
      constraints min: 1, max: 5
    end

    attribute :confidence_level, :decimal do
      description "Reviewer confidence in their assessment"
      constraints min: 0.0, max: 1.0
    end

    # Review content and metadata
    attribute :review_notes, :string do
      description "Detailed review notes and feedback"
    end

    attribute :review_tags, {:array, :string} do
      description "Categorical tags for review classification"
      default []
    end

    attribute :review_metadata, :map do
      description "Additional review metadata and analysis"
      default %{}
    end

    # Review process tracking
    attribute :review_status, :atom do
      description "Current review status"
      default :pending
      constraints one_of: [:pending, :in_progress, :completed, :skipped]
    end

    attribute :review_duration_seconds, :integer do
      description "Time spent on review in seconds"
      constraints min: 0
    end

    attribute :completion_notes, :string do
      description "Notes from review completion"
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :completed_at, :utc_datetime do
      description "When review was completed"
    end
  end

  relationships do
    belongs_to :quality_validation, SweBench.QualityAssurance.QualityValidation do
      destination_attribute :id
      source_attribute :quality_validation_id
      allow_nil? false
    end

    belongs_to :task_instance, SweBench.TaskInstances.TaskInstance do
      destination_attribute :id
      source_attribute :task_instance_id
      allow_nil? false
    end

    belongs_to :reviewer, SweBench.Accounts.User do
      destination_attribute :id
      source_attribute :reviewer_id
      allow_nil? false
    end
  end

  calculations do
    calculate :normalized_quality_score, :decimal do
      description "Quality rating normalized to 0-1 scale"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          # Convert 1-5 scale to 0-1 scale
          ((record.quality_rating || 1) - 1) / 4.0
        end)
      end
    end

    calculate :review_completeness, :decimal do
      description "Completeness of review data"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          fields_completed = [
            record.quality_rating != nil,
            record.clarity_rating != nil,
            record.correctness_rating != nil,
            record.difficulty_rating != nil,
            not is_nil(record.review_notes) and String.length(record.review_notes) > 10
          ]

          completed_count = Enum.count(fields_completed, & &1)
          completed_count / length(fields_completed)
        end)
      end
    end
  end
end

