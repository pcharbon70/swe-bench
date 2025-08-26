defmodule SweBench.TaskInstances.TaskInstance do
  @moduledoc """
  Ash resource for SWE-bench task instances.

  Stores standardized benchmark task instances created from validated
  issue-PR pairs, including code changes, test specifications, and metadata.
  """

  use Ash.Resource,
    domain: SweBench.TaskInstances,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "task_instances"
    repo SweBench.Repo

    # Indexes will be created via migration
  end

  actions do
    defaults [:read, :update, :destroy]

    create :generate_instance do
      accept [
        :instance_id,
        :repository_id,
        :issue_pr_link_id,
        :validation_result_id,
        :base_commit_sha,
        :problem_statement,
        :patch_content,
        :hints,
        :test_specification,
        :solution_specification,
        :task_metadata,
        :evaluation_metadata,
        :quality_tier,
        :difficulty_level,
        :content_checksum
      ]

      validate present([:instance_id, :repository_id, :problem_statement])
      validate match(:instance_id, ~r/^[a-zA-Z0-9_-]+$/)
      validate attribute_in(:quality_tier, [:gold, :silver, :bronze])
    end

    update :mark_ready_for_packaging do
      accept [:packaging_status]

      change set_attribute(:packaging_status, :ready)
      change set_attribute(:ready_at, &DateTime.utc_now/0)
    end

    update :mark_packaged do
      accept [:packaging_status, :dataset_release_id]

      change set_attribute(:packaging_status, :packaged)
      change set_attribute(:packaged_at, &DateTime.utc_now/0)
    end

    read :by_quality_tier do
      argument :tier, :atom do
        constraints one_of: [:gold, :silver, :bronze]
      end

      filter expr(quality_tier == ^arg(:tier))
    end

    read :by_repository do
      argument :repository_id, :uuid, allow_nil?: false
      filter expr(repository_id == ^arg(:repository_id))
    end

    read :by_difficulty do
      argument :level, :atom do
        constraints one_of: [:easy, :medium, :hard, :expert]
      end

      filter expr(difficulty_level == ^arg(:level))
    end

    read :ready_for_packaging do
      filter expr(packaging_status == :ready and quality_tier in [:gold, :silver, :bronze])
      prepare build(sort: [quality_tier: :asc, difficulty_level: :asc])
    end

    read :in_repository_range do
      argument :repository_ids, {:array, :uuid}, allow_nil?: false
      filter expr(repository_id in ^arg(:repository_ids))
    end

    read :recent_instances do
      filter expr(created_at > ago(7, :day))
      prepare build(sort: [created_at: :desc])
    end
  end

  validations do
    validate present([:instance_id, :repository_id, :problem_statement]) do
      message "Instance ID, repository, and problem statement are required"
    end

    validate match(:instance_id, ~r/^[a-zA-Z0-9_-]+$/) do
      message "Instance ID must contain only alphanumeric characters, underscores, and hyphens"
    end

    validate attribute_in(:quality_tier, [:gold, :silver, :bronze]) do
      message "Quality tier must be gold, silver, or bronze"
    end
  end

  attributes do
    uuid_primary_key :id

    # Core SWE-bench compatibility fields
    attribute :instance_id, :string do
      description "Unique instance identifier (repo_name-issue_number)"
      allow_nil? false
      constraints max_length: 200
    end

    attribute :repository_id, :uuid do
      description "Reference to the repository"
      allow_nil? false
    end

    attribute :issue_pr_link_id, :uuid do
      description "Reference to the validated issue-PR relationship"
      allow_nil? false
    end

    attribute :validation_result_id, :uuid do
      description "Reference to the test transition validation result"
      allow_nil? false
    end

    # Task content
    attribute :base_commit_sha, :string do
      description "Base commit SHA for the task"
      allow_nil? false
      constraints max_length: 40
    end

    attribute :problem_statement, :string do
      description "Clear description of the problem to solve"
      allow_nil? false
    end

    attribute :patch_content, :string do
      description "The gold standard solution patch"
      allow_nil? false
    end

    attribute :hints, {:array, :string} do
      description "Optional hints for solving the problem"
      default []
    end

    # Test and solution specifications
    attribute :test_specification, :map do
      description "Test files and execution requirements"
      default %{}
    end

    attribute :solution_specification, :map do
      description "Expected solution characteristics"
      default %{}
    end

    # Rich metadata for analysis
    attribute :task_metadata, :map do
      description "Comprehensive task metadata and analysis"
      default %{}
    end

    attribute :evaluation_metadata, :map do
      description "Metadata for evaluation and scoring"
      default %{}
    end

    # Classification and quality
    attribute :quality_tier, :atom do
      description "Quality tier classification"
      allow_nil? false
      constraints one_of: [:gold, :silver, :bronze]
    end

    attribute :difficulty_level, :atom do
      description "Estimated difficulty level"
      default :medium
      constraints one_of: [:easy, :medium, :hard, :expert]
    end

    attribute :complexity_score, :decimal do
      description "Complexity assessment score"
      constraints min: 0.0, max: 100.0
    end

    # Packaging and release management
    attribute :packaging_status, :atom do
      description "Packaging status for dataset releases"
      default :draft
      constraints one_of: [:draft, :ready, :packaged, :published]
    end

    attribute :dataset_release_id, :uuid do
      description "Reference to dataset release containing this instance"
    end

    # Data integrity
    attribute :content_checksum, :string do
      description "SHA256 checksum of instance content for integrity validation"
      constraints max_length: 64
    end

    attribute :generation_metadata, :map do
      description "Metadata about the generation process"
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :ready_at, :utc_datetime do
      description "When instance was marked ready for packaging"
    end

    attribute :packaged_at, :utc_datetime do
      description "When instance was packaged into a dataset"
    end
  end

  # Custom Jason encoder for SWE-bench format compatibility
  @derive {Jason.Encoder,
           only: [
             :instance_id,
             :repository,
             :base_commit_sha,
             :problem_statement,
             :patch_content,
             :hints,
             :test_specification,
             :solution_specification,
             :quality_tier,
             :difficulty_level,
             :task_metadata,
             :created_at
           ]}

  relationships do
    belongs_to :repository, SweBench.Repositories.Repository do
      destination_attribute :id
      source_attribute :repository_id
      allow_nil? false
    end

    belongs_to :issue_pr_link, SweBench.Issues.IssuePrLink do
      destination_attribute :id
      source_attribute :issue_pr_link_id
      allow_nil? false
    end

    belongs_to :validation_result, SweBench.ValidationResults.ValidationResult do
      destination_attribute :id
      source_attribute :validation_result_id
      allow_nil? false
    end

    belongs_to :dataset_release, SweBench.TaskInstances.DatasetRelease do
      destination_attribute :id
      source_attribute :dataset_release_id
    end
  end

  calculations do
    calculate :swe_bench_format, :map do
      description "Task instance in standard SWE-bench JSON format"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          %{
            instance_id: record.instance_id,
            repo: extract_repo_name(record.repository),
            base_commit: record.base_commit_sha,
            problem_statement: record.problem_statement,
            patch: record.patch_content,
            test_patch: extract_test_patch(record.test_specification),
            hints: record.hints,
            created_at: DateTime.to_iso8601(record.created_at),
            elixir_metadata: Map.get(record.task_metadata, :elixir_analysis, %{})
          }
        end)
      end
    end

    calculate :estimated_resolution_time, :string do
      description "Estimated time to resolve based on complexity"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case record.difficulty_level do
            :easy -> "15-30 minutes"
            :medium -> "30-60 minutes"
            :hard -> "1-2 hours"
            :expert -> "2+ hours"
          end
        end)
      end
    end

    calculate :instance_size_estimate, :integer do
      description "Estimated instance size in bytes"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          problem_size = String.length(record.problem_statement || "")
          patch_size = String.length(record.patch_content || "")
          metadata_size = estimate_map_size(record.task_metadata)

          problem_size + patch_size + metadata_size
        end)
      end
    end
  end

  # Helper functions for calculations
  defp extract_repo_name(repository) when is_map(repository) do
    Map.get(repository, :full_name, "unknown/unknown")
  end

  defp extract_repo_name(_), do: "unknown/unknown"

  defp extract_test_patch(test_specification) when is_map(test_specification) do
    Map.get(test_specification, :test_patch, "")
  end

  defp extract_test_patch(_), do: ""

  defp estimate_map_size(map) when is_map(map) do
    map
    |> Jason.encode!()
    |> String.length()
  end

  defp estimate_map_size(_), do: 0
end
