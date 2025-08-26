defmodule SweBench.TaskInstances.DatasetRelease do
  @moduledoc """
  Ash resource for versioned dataset releases.

  Manages dataset packaging, versioning, and release distribution
  for SWE-bench task instance collections.
  """

  use Ash.Resource,
    domain: SweBench.TaskInstances,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dataset_releases"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_release do
      accept [
        :version,
        :release_type,
        :description,
        :instance_count,
        :quality_distribution,
        :compression_format,
        :package_size_bytes,
        :content_checksum,
        :release_metadata
      ]

      validate present([:version, :instance_count])
      validate match(:version, ~r/^\d+\.\d+\.\d+.*$/)
    end

    update :mark_published do
      accept [:publication_status, :published_at, :download_url]

      change set_attribute(:publication_status, :published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end

    read :by_version do
      argument :version, :string, allow_nil?: false
      filter expr(version == ^arg(:version))
    end

    read :published_releases do
      filter expr(publication_status == :published)
      prepare build(sort: [published_at: :desc])
    end

    read :recent_releases do
      filter expr(created_at > ago(30, :day))
      prepare build(sort: [created_at: :desc])
    end

    read :by_release_type do
      argument :type, :atom do
        constraints one_of: [:full, :incremental, :experimental, :patch]
      end

      filter expr(release_type == ^arg(:type))
    end
  end

  validations do
    validate present([:version, :instance_count]) do
      message "Version and instance count are required"
    end

    validate match(:version, ~r/^\d+\.\d+\.\d+.*$/) do
      message "Version must follow semantic versioning format (e.g., 1.0.0)"
    end

    validate compare(:instance_count, greater_than: 0) do
      message "Instance count must be greater than 0"
    end

    validate compare(:package_size_bytes, greater_than_or_equal_to: 0) do
      message "Package size cannot be negative"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :string do
      description "Semantic version of the dataset release"
      allow_nil? false
      constraints max_length: 50
    end

    attribute :release_type, :atom do
      description "Type of dataset release"
      allow_nil? false
      constraints one_of: [:full, :incremental, :experimental, :patch]
    end

    attribute :description, :string do
      description "Description of the dataset release"
      constraints max_length: 1000
    end

    # Dataset statistics
    attribute :instance_count, :integer do
      description "Total number of instances in the release"
      allow_nil? false
      constraints min: 1
    end

    attribute :quality_distribution, :map do
      description "Distribution of instances by quality tier"
      default %{}
    end

    attribute :difficulty_distribution, :map do
      description "Distribution of instances by difficulty level"
      default %{}
    end

    attribute :repository_coverage, :map do
      description "Coverage statistics by repository"
      default %{}
    end

    # Package information
    attribute :compression_format, :string do
      description "Compression format used for packaging"
      default "gzip"
    end

    attribute :package_size_bytes, :integer do
      description "Size of the packaged dataset in bytes"
      constraints min: 0
    end

    attribute :package_path, :string do
      description "File system path to the packaged dataset"
    end

    attribute :download_url, :string do
      description "URL for downloading the dataset release"
    end

    # Data integrity
    attribute :content_checksum, :string do
      description "SHA256 checksum of the complete dataset"
      constraints max_length: 64
    end

    attribute :release_metadata, :map do
      description "Comprehensive release metadata and build information"
      default %{}
    end

    # Publication status
    attribute :publication_status, :atom do
      description "Publication status of the release"
      default :draft
      constraints one_of: [:draft, :ready, :published, :deprecated]
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :published_at, :utc_datetime do
      description "When the release was published"
    end

    attribute :build_duration_ms, :integer do
      description "Time taken to build the release in milliseconds"
      constraints min: 0
    end
  end

  relationships do
    has_many :task_instances, SweBench.TaskInstances.TaskInstance do
      destination_attribute :dataset_release_id
    end
  end

  calculations do
    calculate :format_version, :string do
      description "Dataset format version for compatibility"

      calculation fn records, _context ->
        records
        |> Enum.map(fn _record ->
          "swe-bench-elixir-1.0"
        end)
      end
    end

    calculate :average_instance_size, :decimal do
      description "Average size per instance in bytes"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          if (record.instance_count || 0) > 0 do
            (record.package_size_bytes || 0) / record.instance_count
          else
            0.0
          end
        end)
      end
    end

    calculate :compression_ratio, :decimal do
      description "Compression efficiency ratio"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          # Placeholder calculation - will be implemented with actual compression
          0.75
        end)
      end
    end
  end
end
