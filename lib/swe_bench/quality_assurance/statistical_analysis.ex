defmodule SweBench.QualityAssurance.StatisticalAnalysis do
  @moduledoc """
  Ash resource for statistical analysis results.

  Stores comprehensive statistical analysis including distribution metrics,
  outlier detection, and quality trend analysis for benchmark datasets.
  """

  use Ash.Resource,
    domain: SweBench.QualityAssurance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "statistical_analyses"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_analysis do
      accept [
        :analysis_type,
        :dataset_version,
        :instance_count,
        :distribution_metrics,
        :quality_statistics,
        :outlier_analysis,
        :trend_analysis,
        :analysis_metadata
      ]

      validate present([:analysis_type, :instance_count])
      validate compare(:instance_count, greater_than: 0)
    end

    read :by_analysis_type do
      argument :type, :atom do
        constraints one_of: [:distribution, :outlier_detection, :trend_analysis, :quality_metrics, :comprehensive]
      end

      filter expr(analysis_type == ^arg(:type))
    end

    read :by_dataset_version do
      argument :version, :string, allow_nil?: false
      filter expr(dataset_version == ^arg(:version))
    end

    read :recent_analyses do
      filter expr(created_at > ago(7, :day))
      prepare build(sort: [created_at: :desc])
    end

    read :by_instance_count_range do
      argument :min_count, :integer, allow_nil?: false
      argument :max_count, :integer, allow_nil?: false
      filter expr(instance_count >= ^arg(:min_count) and instance_count <= ^arg(:max_count))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :analysis_type, :atom do
      description "Type of statistical analysis performed"
      allow_nil? false
      constraints one_of: [:distribution, :outlier_detection, :trend_analysis, :quality_metrics, :comprehensive]
    end

    attribute :dataset_version, :string do
      description "Version of dataset analyzed"
      constraints max_length: 50
    end

    attribute :instance_count, :integer do
      description "Number of task instances analyzed"
      allow_nil? false
      constraints min: 1
    end

    # Statistical metrics
    attribute :distribution_metrics, :map do
      description "Distribution analysis results"
      default %{}
    end

    attribute :quality_statistics, :map do
      description "Quality score statistics and percentiles"
      default %{}
    end

    attribute :outlier_analysis, :map do
      description "Outlier detection results and flagged instances"
      default %{}
    end

    attribute :trend_analysis, :map do
      description "Quality trend analysis over time"
      default %{}
    end

    attribute :correlation_analysis, :map do
      description "Correlation analysis between quality factors"
      default %{}
    end

    # Analysis metadata
    attribute :analysis_metadata, :map do
      description "Comprehensive analysis metadata and configuration"
      default %{}
    end

    attribute :analysis_parameters, :map do
      description "Parameters used for statistical analysis"
      default %{}
    end

    attribute :analysis_duration_ms, :integer do
      description "Time taken to perform analysis in milliseconds"
      constraints min: 0
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :quality_score_summary, :map do
      description "Summary statistics for quality scores"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          stats = Map.get(record.quality_statistics, :score_distribution, %{})

          %{
            mean: Map.get(stats, :mean, 0.0),
            median: Map.get(stats, :median, 0.0),
            std_dev: Map.get(stats, :std_dev, 0.0),
            percentiles: Map.get(stats, :percentiles, %{})
          }
        end)
      end
    end

    calculate :outlier_percentage, :decimal do
      description "Percentage of instances identified as outliers"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          outlier_count = Map.get(record.outlier_analysis, :outlier_count, 0)
          total_instances = record.instance_count || 1

          (outlier_count / total_instances) * 100
        end)
      end
    end
  end

  validations do
    validate present([:analysis_type, :instance_count]) do
      message "Analysis type and instance count are required"
    end

    validate compare(:instance_count, greater_than: 0) do
      message "Instance count must be greater than 0"
    end
  end
end