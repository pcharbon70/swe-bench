defmodule SweBench.Repositories.Repository do
  @moduledoc """
  Ash resource for GitHub repositories with metadata and analysis results.

  Stores repository information including GitHub metadata, Elixir-specific
  analysis results, and evaluation task generation data.
  """

  use Ash.Resource,
    domain: SweBench.Repositories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "repositories"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :github_id,
        :name,
        :full_name,
        :owner,
        :description,
        :language,
        :stars_count,
        :forks_count,
        :has_issues,
        :is_umbrella_project,
        :hex_package_name,
        :default_branch,
        :topics,
        :license,
        :analysis_metadata
      ]
    end

    update :analyze do
      accept [
        :is_umbrella_project,
        :hex_package_name,
        :analysis_metadata,
        :last_analyzed_at
      ]
    end

    read :by_github_id do
      argument :github_id, :integer, allow_nil?: false
      filter expr(github_id == ^arg(:github_id))
    end

    read :by_full_name do
      argument :full_name, :string, allow_nil?: false
      filter expr(full_name == ^arg(:full_name))
    end

    read :by_language do
      argument :language, :string, allow_nil?: false
      filter expr(language == ^arg(:language))
    end

    read :umbrella_projects do
      filter expr(is_umbrella_project == true)
    end

    read :with_hex_packages do
      filter expr(not is_nil(hex_package_name))
    end
  end

  validations do
    validate compare(:stars_count, greater_than_or_equal_to: 0)
    validate compare(:forks_count, greater_than_or_equal_to: 0)

    validate match(:full_name, ~r/^[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+$/) do
      message "must be in format 'owner/repo'"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :github_id, :integer do
      allow_nil? false
      constraints min: 1
    end

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :full_name, :string do
      allow_nil? false
      constraints max_length: 512
    end

    attribute :owner, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :description, :string do
      constraints max_length: 2000
    end

    attribute :language, :string do
      constraints max_length: 50
    end

    attribute :stars_count, :integer do
      default 0
      constraints min: 0
    end

    attribute :forks_count, :integer do
      default 0
      constraints min: 0
    end

    attribute :has_issues, :boolean do
      default true
    end

    attribute :is_umbrella_project, :boolean do
      default false
    end

    attribute :hex_package_name, :string do
      constraints max_length: 255
    end

    attribute :default_branch, :string do
      default "main"
      constraints max_length: 255
    end

    attribute :topics, {:array, :string} do
      default []
    end

    attribute :license, :string do
      constraints max_length: 255
    end

    attribute :analysis_metadata, :map do
      default %{}
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :last_analyzed_at, :utc_datetime
  end

  # relationships do
  # TODO: Add relationships when Issue, PullRequest, and Instance resources are created
  # has_many :issues, SweBench.Issues.Issue do
  #   destination_attribute :repository_id
  # end

  # has_many :pull_requests, SweBench.Issues.PullRequest do
  #   destination_attribute :repository_id
  # end

  # has_many :task_instances, SweBench.Tasks.Instance do
  #   destination_attribute :repository_id
  # end
  # end

  identities do
    identity :unique_github_id, [:github_id]
    identity :unique_full_name, [:full_name]
  end
end
