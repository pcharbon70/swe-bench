defmodule SweBench.Issues.Issue do
  @moduledoc """
  Ash resource for GitHub issues with metadata and analysis results.

  Stores issue information for evaluation task generation.
  """

  use Ash.Resource,
    domain: SweBench.Issues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "issues"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :repository_id,
        :github_id,
        :number,
        :title,
        :body,
        :state,
        :labels,
        :closed_at
      ]
    end

    read :by_github_id do
      argument :github_id, :integer, allow_nil?: false
      filter expr(github_id == ^arg(:github_id))
    end

    read :by_repository do
      argument :repository_id, :uuid, allow_nil?: false
      filter expr(repository_id == ^arg(:repository_id))
    end

    read :closed_issues do
      filter expr(state == "closed")
    end

    read :open_issues do
      filter expr(state == "open")
    end
  end

  validations do
    validate compare(:number, greater_than: 0)
    validate compare(:github_id, greater_than: 0)

    validate match(:state, ~r/^(open|closed)$/) do
      message "must be either 'open' or 'closed'"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :github_id, :integer do
      allow_nil? false
      constraints min: 1
    end

    attribute :number, :integer do
      allow_nil? false
      constraints min: 1
    end

    attribute :title, :string do
      allow_nil? false
      constraints max_length: 500
    end

    attribute :body, :string

    attribute :state, :string do
      allow_nil? false
    end

    attribute :labels, {:array, :string} do
      default []
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :closed_at, :utc_datetime
  end

  relationships do
    belongs_to :repository, SweBench.Repositories.Repository do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_github_id, [:github_id]
    identity :unique_repository_number, [:repository_id, :number]
  end
end
