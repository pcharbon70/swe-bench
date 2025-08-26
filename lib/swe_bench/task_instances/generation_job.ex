defmodule SweBench.TaskInstances.GenerationJob do
  @moduledoc """
  Ash resource for tracking task instance generation jobs.

  Manages generation job lifecycle, progress tracking, and result aggregation
  for batch task instance generation operations.
  """

  use Ash.Resource,
    domain: SweBench.TaskInstances,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "task_generation_jobs"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create_job do
      accept [
        :job_type,
        :input_data,
        :generation_options,
        :target_count,
        :priority
      ]

      validate attribute_does_not_equal(:target_count, 0)
      validate attribute_in(:priority, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    end

    update :mark_running do
      accept [:status, :started_at]

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :mark_completed do
      accept [:status, :instances_generated, :instances_failed, :completed_at]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :mark_failed do
      accept [:status, :error_message, :failed_at]

      change set_attribute(:status, :failed)
      change set_attribute(:failed_at, &DateTime.utc_now/0)
    end

    read :pending do
      filter expr(status == :pending)
    end

    read :by_priority do
      prepare build(sort: [priority: :desc, created_at: :asc])
    end

    read :active do
      filter expr(status in [:pending, :running])
    end

    read :completed_recently do
      filter expr(completed_at > ago(1, :day))
      prepare build(sort: [completed_at: :desc])
    end
  end

  validations do
    validate attribute_does_not_equal(:target_count, 0) do
      message "Must specify at least 1 instance to generate"
    end

    validate compare(:instances_generated, less_than_or_equal_to: :target_count) do
      message "Cannot generate more instances than target"
    end

    validate compare(:instances_failed, greater_than_or_equal_to: 0) do
      message "Failed instance count cannot be negative"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :job_type, :atom do
      description "Type of generation job"
      allow_nil? false
      constraints one_of: [:validation_results, :repository_batch, :manual_list]
    end

    attribute :input_data, :map do
      description "Input data for generation (validation result IDs, repository IDs, etc.)"
      default %{}
    end

    attribute :generation_options, :map do
      description "Configuration options for generation"
      default %{}
    end

    attribute :target_count, :integer do
      description "Target number of instances to generate"
      default 100
      constraints min: 1, max: 10_000
    end

    attribute :priority, :integer do
      description "Job priority (1=lowest, 10=highest)"
      default 5
      constraints min: 1, max: 10
    end

    attribute :status, :atom do
      description "Current job status"
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
    end

    attribute :instances_generated, :integer do
      description "Number of instances successfully generated"
      default 0
      constraints min: 0
    end

    attribute :instances_failed, :integer do
      description "Number of instances that failed generation"
      default 0
      constraints min: 0
    end

    attribute :error_message, :string do
      description "Error message if job failed"
    end

    attribute :processing_time_ms, :integer do
      description "Total processing time in milliseconds"
      constraints min: 0
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :started_at, :utc_datetime do
      description "When job processing began"
    end

    attribute :completed_at, :utc_datetime do
      description "When job completed successfully"
    end

    attribute :failed_at, :utc_datetime do
      description "When job failed"
    end
  end

  # relationships do
  # TODO: Add relationship when TaskInstance includes generation_job_id field
  # has_many :generated_instances, SweBench.TaskInstances.TaskInstance do
  #   destination_attribute :generation_job_id
  # end
  # end

  calculations do
    calculate :success_rate, :decimal do
      description "Success rate of instance generation"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          total = (record.instances_generated || 0) + (record.instances_failed || 0)

          if total > 0 do
            (record.instances_generated || 0) / total
          else
            0.0
          end
        end)
      end
    end

    calculate :instances_per_hour, :decimal do
      description "Instance generation rate per hour"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case record.processing_time_ms do
            time_ms when is_integer(time_ms) and time_ms > 0 ->
              hours = time_ms / 3_600_000
              (record.instances_generated || 0) / max(hours, 0.001)

            _ ->
              0.0
          end
        end)
      end
    end
  end
end
