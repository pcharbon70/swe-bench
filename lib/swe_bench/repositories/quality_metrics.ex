defmodule SweBench.Repositories.QualityMetrics do
  @moduledoc """
  Ash resource for repository quality assessment data.

  Stores multi-dimensional quality scores including code quality, community health,
  technical complexity, and maintenance activity metrics.
  """

  use Ash.Resource,
    domain: SweBench.Repositories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "repository_quality_metrics"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :calculate_quality do
      accept [
        :repository_id,
        :code_quality_score,
        :community_health_score,
        :technical_complexity_score,
        :maintenance_activity_score,
        :quality_factors
      ]

      change after_action(&calculate_overall_score/2)
    end

    update :recalculate do
      accept [
        :code_quality_score,
        :community_health_score,
        :technical_complexity_score,
        :maintenance_activity_score,
        :quality_factors
      ]

      require_atomic? false
      change after_action(&calculate_overall_score/2)
    end

    read :by_quality_category do
      argument :category, :atom do
        constraints one_of: [:excellent, :good, :average, :below_average, :poor]
      end

      filter expr(category == ^arg(:category))
    end

    read :above_quality_threshold do
      argument :threshold, :decimal do
        constraints min: 0.0, max: 100.0
      end

      filter expr(overall_quality_score >= ^arg(:threshold))
    end

    read :recent_analysis do
      filter expr(updated_at > ago(7, :day))
      prepare build(sort: [updated_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :repository_id, :uuid do
      description "Reference to the analyzed repository"
      allow_nil? false
    end

    # Quality dimension scores (0.0 - 100.0)
    attribute :code_quality_score, :decimal do
      description "Code quality assessment score"
      constraints min: 0.0, max: 100.0
      default 0.0
    end

    attribute :community_health_score, :decimal do
      description "Community health and activity score"
      constraints min: 0.0, max: 100.0
      default 0.0
    end

    attribute :technical_complexity_score, :decimal do
      description "Technical complexity and sophistication score"
      constraints min: 0.0, max: 100.0
      default 0.0
    end

    attribute :maintenance_activity_score, :decimal do
      description "Maintenance activity and freshness score"
      constraints min: 0.0, max: 100.0
      default 0.0
    end

    attribute :overall_quality_score, :decimal do
      description "Weighted overall quality score"
      constraints min: 0.0, max: 100.0
      default 0.0
    end

    attribute :category, :atom do
      description "Quality category classification"
      constraints one_of: [:excellent, :good, :average, :below_average, :poor]
      default :average
    end

    attribute :quality_factors, :map do
      description "Detailed breakdown of quality assessment factors"
      default %{}
    end

    attribute :analysis_version, :string do
      description "Version of quality analysis algorithm used"
      default "1.0.0"
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :repository, SweBench.Repositories.Repository do
      destination_attribute :id
      source_attribute :repository_id
      allow_nil? false
    end
  end

  calculations do
    calculate :weighted_score, :decimal do
      description "Calculated weighted quality score"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          calculate_weighted_quality_score(
            record.code_quality_score,
            record.community_health_score,
            record.technical_complexity_score,
            record.maintenance_activity_score
          )
        end)
      end
    end

    calculate :score_breakdown, :map do
      description "Quality score breakdown with percentages"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          %{
            code_quality: %{
              score: record.code_quality_score,
              percentage: record.code_quality_score,
              weight: 30
            },
            community_health: %{
              score: record.community_health_score,
              percentage: record.community_health_score,
              weight: 25
            },
            technical_complexity: %{
              score: record.technical_complexity_score,
              percentage: record.technical_complexity_score,
              weight: 25
            },
            maintenance_activity: %{
              score: record.maintenance_activity_score,
              percentage: record.maintenance_activity_score,
              weight: 20
            }
          }
        end)
      end
    end
  end

  validations do
    validate compare(:overall_quality_score, greater_than_or_equal_to: 0.0) do
      message "Overall quality score cannot be negative"
    end

    validate compare(:overall_quality_score, less_than_or_equal_to: 100.0) do
      message "Overall quality score cannot exceed 100"
    end
  end

  # Private helper functions for change implementations

  defp calculate_overall_score(_changeset, result) do
    case result do
      {:ok, quality_metrics} ->
        overall_score = calculate_weighted_quality_score(
          quality_metrics.code_quality_score,
          quality_metrics.community_health_score,
          quality_metrics.technical_complexity_score,
          quality_metrics.maintenance_activity_score
        )

        category = determine_quality_category(overall_score)

        quality_metrics
        |> Ash.Changeset.for_update(:recalculate, %{
          overall_quality_score: overall_score,
          category: category
        })
        |> Ash.update()

      error ->
        error
    end
  end

  defp calculate_weighted_quality_score(code, community, technical, maintenance) do
    weights = %{
      code_quality: 0.30,
      community_health: 0.25,
      technical_complexity: 0.25,
      maintenance_activity: 0.20
    }

    weighted_score =
      (code * weights.code_quality) +
        (community * weights.community_health) +
        (technical * weights.technical_complexity) +
        (maintenance * weights.maintenance_activity)

    # Round to 2 decimal places
    Float.round(weighted_score, 2)
  end

  defp determine_quality_category(overall_score) when overall_score >= 85, do: :excellent
  defp determine_quality_category(overall_score) when overall_score >= 70, do: :good
  defp determine_quality_category(overall_score) when overall_score >= 55, do: :average
  defp determine_quality_category(overall_score) when overall_score >= 40, do: :below_average
  defp determine_quality_category(_overall_score), do: :poor
end
