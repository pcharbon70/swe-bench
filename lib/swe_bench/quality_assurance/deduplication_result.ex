defmodule SweBench.QualityAssurance.DeduplicationResult do
  @moduledoc """
  Ash resource for deduplication analysis results.

  Stores similarity analysis results between task instances including
  similarity scores, matching criteria, and deduplication recommendations.
  """

  use Ash.Resource,
    domain: SweBench.QualityAssurance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "deduplication_results"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_deduplication do
      accept [
        :primary_task_id,
        :similar_task_id,
        :similarity_score,
        :similarity_type,
        :similarity_metadata,
        :deduplication_recommendation,
        :analysis_confidence
      ]

      validate compare(:similarity_score, greater_than_or_equal_to: 0.0)
      validate compare(:similarity_score, less_than_or_equal_to: 1.0)
      validate present([:primary_task_id, :similar_task_id, :similarity_score])
    end

    read :by_similarity_threshold do
      argument :min_similarity, :decimal, allow_nil?: false
      filter expr(similarity_score >= ^arg(:min_similarity))
    end

    read :by_task_instance do
      argument :task_instance_id, :uuid, allow_nil?: false
      filter expr(primary_task_id == ^arg(:task_instance_id) or similar_task_id == ^arg(:task_instance_id))
    end

    read :deduplication_candidates do
      filter expr(deduplication_recommendation == :remove and similarity_score >= 0.8)
      prepare build(sort: [similarity_score: :desc])
    end

    read :by_similarity_type do
      argument :type, :atom do
        constraints one_of: [:code_similarity, :text_similarity, :semantic_similarity, :combined]
      end

      filter expr(similarity_type == ^arg(:type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :primary_task_id, :uuid do
      description "Primary task instance in similarity comparison"
      allow_nil? false
    end

    attribute :similar_task_id, :uuid do
      description "Similar task instance found"
      allow_nil? false
    end

    attribute :similarity_score, :decimal do
      description "Similarity score between task instances (0.0-1.0)"
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :similarity_type, :atom do
      description "Type of similarity analysis performed"
      allow_nil? false
      constraints one_of: [:code_similarity, :text_similarity, :semantic_similarity, :combined]
    end

    attribute :similarity_metadata, :map do
      description "Detailed similarity analysis data"
      default %{}
    end

    attribute :deduplication_recommendation, :atom do
      description "Recommendation for handling the duplicate"
      constraints one_of: [:keep_both, :remove, :merge, :review_required]
    end

    attribute :analysis_confidence, :decimal do
      description "Confidence in the similarity analysis"
      constraints min: 0.0, max: 1.0
    end

    attribute :review_status, :atom do
      description "Human review status for deduplication decision"
      default :pending
      constraints one_of: [:pending, :reviewed, :confirmed, :rejected]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :primary_task, SweBench.TaskInstances.TaskInstance do
      destination_attribute :id
      source_attribute :primary_task_id
      allow_nil? false
    end

    belongs_to :similar_task, SweBench.TaskInstances.TaskInstance do
      destination_attribute :id
      source_attribute :similar_task_id
      allow_nil? false
    end
  end

  identities do
    identity :unique_task_pair, [:primary_task_id, :similar_task_id]
  end

  calculations do
    calculate :similarity_category, :atom do
      description "Categorized similarity level"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case record.similarity_score do
            score when score >= 0.95 -> :very_high
            score when score >= 0.85 -> :high
            score when score >= 0.70 -> :medium
            score when score >= 0.50 -> :low
            _ -> :very_low
          end
        end)
      end
    end

    calculate :deduplication_priority, :integer do
      description "Priority for deduplication processing"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          base_priority = round(record.similarity_score * 100)

          # Boost priority for high-confidence, high-similarity matches
          confidence_boost = 
            if (record.analysis_confidence || 0.0) > 0.9, do: 10, else: 0

          base_priority + confidence_boost
        end)
      end
    end
  end

  validations do
    validate present([:primary_task_id, :similar_task_id, :similarity_score]) do
      message "Primary task, similar task, and similarity score are required"
    end

    validate compare(:similarity_score, greater_than_or_equal_to: 0.0) do
      message "Similarity score cannot be negative"
    end

    validate compare(:similarity_score, less_than_or_equal_to: 1.0) do
      message "Similarity score cannot exceed 1.0"
    end

    validate attribute_does_not_equal(:primary_task_id, :similar_task_id) do
      message "Primary and similar task must be different instances"
    end
  end
end