defmodule SweBench.Issues.PullRequest do
  @moduledoc """
  Ash resource for GitHub pull requests with diff content and analysis.

  Stores PR information, diffs, and test modifications for evaluation.
  """

  use Ash.Resource,
    domain: SweBench.Issues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "pull_requests"
    repo SweBench.Repo
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :repository_id,
        :issue_id,
        :github_id,
        :number,
        :title,
        :body,
        :state,
        :diff_content,
        :test_files_modified,
        :review_comments,
        :additions,
        :deletions,
        :changed_files,
        :merged_at,
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

    read :merged_prs do
      filter expr(not is_nil(merged_at))
    end

    read :with_test_modifications do
      filter expr(length(test_files_modified) > 0)
    end

    read :by_state do
      argument :state, :string, allow_nil?: false
      filter expr(state == ^arg(:state))
    end
  end

  validations do
    validate compare(:number, greater_than: 0)
    validate compare(:github_id, greater_than: 0)
    validate compare(:additions, greater_than_or_equal_to: 0)
    validate compare(:deletions, greater_than_or_equal_to: 0)
    validate compare(:changed_files, greater_than_or_equal_to: 0)

    validate match(:state, ~r/^(open|closed|merged)$/) do
      message "must be 'open', 'closed', or 'merged'"
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

    attribute :diff_content, :string

    attribute :test_files_modified, {:array, :string} do
      default []
    end

    attribute :review_comments, {:array, :map} do
      default []
    end

    attribute :additions, :integer do
      default 0
    end

    attribute :deletions, :integer do
      default 0
    end

    attribute :changed_files, :integer do
      default 0
    end

    create_timestamp :created_at
    update_timestamp :updated_at

    attribute :merged_at, :utc_datetime
    attribute :closed_at, :utc_datetime
  end

  relationships do
    belongs_to :repository, SweBench.Repositories.Repository do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :issue, SweBench.Issues.Issue do
      attribute_writable? true
    end
  end

  identities do
    identity :unique_github_id, [:github_id]
    identity :unique_repository_number, [:repository_id, :number]
  end
end
