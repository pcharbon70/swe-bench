defmodule SweBench.Issues do
  @moduledoc """
  Domain for GitHub issues and pull requests data management.

  Handles issue collection, PR analysis, and diff parsing for
  evaluation task generation.
  """

  use Ash.Domain

  resources do
    resource SweBench.Issues.Issue
    resource SweBench.Issues.PullRequest
    resource SweBench.Issues.IssuePrLink
  end
end
