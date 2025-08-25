defmodule SweBench.Repositories.MiningJob do
  @moduledoc """
  Ash resource for tracking repository mining operations.

  Represents mining jobs that discover and analyze repositories from various sources
  including Hex.pm packages and GitHub trending repositories.
  """

  use Ash.Resource,
    domain: SweBench.Repositories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "mining_jobs"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :queue_mining do
      accept [:source, :query_params, :max_repositories, :priority]

      validate attribute_does_not_equal(:max_repositories, 0)
      validate attribute_in(:priority, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    end

    update :mark_running do
      accept [:status, :started_at]

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :mark_completed do
      accept [:status, :repositories_discovered, :completed_at]

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

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      description "Source of repository discovery"
      allow_nil? false
      constraints one_of: [:hex_pm, :github_trending, :github_search, :manual_list]
    end

    attribute :query_params, :map do
      description "Parameters for repository discovery query"
      default %{}
    end

    attribute :max_repositories, :integer do
      description "Maximum number of repositories to discover"
      default 100
      constraints min: 1, max: 1000
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

    attribute :repositories_discovered, :integer do
      description "Number of repositories successfully discovered"
      default 0
      constraints min: 0
    end

    attribute :repositories_analyzed, :integer do
      description "Number of repositories fully analyzed"
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

  relationships do
    has_many :discovered_repositories, SweBench.Repositories.Repository do
      destination_attribute :mining_job_id
    end
  end

  calculations do
    calculate :duration_seconds, :integer do
      description "Job duration in seconds"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case {record.started_at, record.completed_at || record.failed_at} do
            {%DateTime{} = start_time, %DateTime{} = end_time} ->
              DateTime.diff(end_time, start_time)

            {%DateTime{}, nil} ->
              DateTime.diff(DateTime.utc_now(), record.started_at)

            _ ->
              0
          end
        end)
      end
    end

    calculate :repositories_per_hour, :decimal do
      description "Repository discovery rate per hour"

      calculation fn records, _context ->
        records
        |> Enum.map(fn record ->
          case record.processing_time_ms do
            time_ms when is_integer(time_ms) and time_ms > 0 ->
              hours = time_ms / 3_600_000
              record.repositories_discovered / max(hours, 0.001)

            _ ->
              0.0
          end
        end)
      end
    end
  end

  validations do
    validate attribute_does_not_equal(:max_repositories, 0) do
      message "Must specify at least 1 repository to discover"
    end

    validate compare(:repositories_discovered, less_than_or_equal_to: :max_repositories) do
      message "Cannot discover more repositories than maximum specified"
    end

    validate compare(:repositories_analyzed, less_than_or_equal_to: :repositories_discovered) do
      message "Cannot analyze more repositories than discovered"
    end
  end
end
