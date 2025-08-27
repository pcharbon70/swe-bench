defmodule SweBench.RepositorySetup.RepositoryConfig do
  @moduledoc """
  Behavior for repository-specific configurations.

  Defines the interface that all repository configurations must implement
  to ensure consistent setup, testing, and validation across repositories.
  """

  @doc """
  Returns the repository name (e.g., "plausible/analytics").
  """
  @callback repository_name() :: String.t()

  @doc """
  Returns the GitHub URL for the repository.
  """
  @callback github_url() :: String.t()

  @doc """
  Returns the complexity tier for resource allocation.
  """
  @callback complexity_tier() :: :core_library | :specialized_framework | :production

  @doc """
  Returns the list of dependencies required for the repository.
  """
  @callback dependencies() :: list()

  @doc """
  Returns environment setup configuration including commands and variables.
  """
  @callback environment_setup() :: map()

  @doc """
  Returns the list of testing scenarios for the repository.
  """
  @callback testing_scenarios() :: list(atom())

  @doc """
  Returns resource requirements for the repository.
  """
  @callback resource_requirements() :: map()

  @doc """
  Returns task generation configuration including target counts and distributions.
  """
  @callback task_generation_config() :: map()

  @doc """
  Returns validation requirements for ensuring repository is properly configured.
  """
  @callback validation_requirements() :: map()
end
