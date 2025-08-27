defmodule SweBench.RepositorySetup.ValidationFramework do
  @moduledoc """
  Comprehensive repository and task validation framework.

  Validates repository configurations, task instance quality, and
  cross-repository compatibility for the expanded repository set.
  """

  require Logger

  @doc """
  Validates production repository configuration.
  """
  def validate_production_configuration(repository_spec, environment_config) do
    Logger.info("Validating production configuration for #{repository_spec.name}")

    validation_checks = [
      {:resource_allocation, validate_resource_allocation(repository_spec)},
      {:environment_setup, validate_environment_setup(environment_config)},
      {:dependency_configuration, validate_dependencies(repository_spec)},
      {:testing_scenarios, validate_testing_scenarios(repository_spec)}
    ]

    case Enum.find(validation_checks, fn {_check, result} -> result != :ok end) do
      nil ->
        {:ok,
         %{
           validation_passed: true,
           checks_completed: length(validation_checks),
           validated_at: DateTime.utc_now()
         }}

      {failed_check, error} ->
        {:error, {failed_check, error}}
    end
  end

  @doc """
  Validates task instance quality and distribution.
  """
  def validate_task_instances(task_instances, repository_spec) do
    target_count = repository_spec.target_instances

    quality_checks = [
      validate_instance_count(task_instances, target_count),
      validate_complexity_distribution(task_instances),
      validate_scenario_coverage(task_instances, repository_spec)
    ]

    case Enum.all?(quality_checks, fn result -> result == :ok end) do
      true ->
        {:ok,
         %{
           task_validation_passed: true,
           total_instances: length(task_instances),
           quality_score: calculate_quality_score(task_instances)
         }}

      false ->
        failed_checks =
          quality_checks
          |> Enum.with_index()
          |> Enum.filter(fn {result, _index} -> result != :ok end)

        {:error, {:quality_validation_failed, failed_checks}}
    end
  end

  @doc """
  Validates cross-repository compatibility.
  """
  def validate_cross_repository_compatibility(repositories) do
    compatibility_checks = [
      validate_resource_conflicts(repositories),
      validate_port_conflicts(repositories),
      validate_dependency_conflicts(repositories)
    ]

    case Enum.all?(compatibility_checks, fn result -> result == :ok end) do
      true ->
        {:ok, %{compatibility_validated: true, repository_count: length(repositories)}}

      false ->
        {:error, :compatibility_validation_failed}
    end
  end

  # Private functions

  defp validate_resource_allocation(repository_spec) do
    requirements = Map.get(repository_spec, :resource_requirements, %{})

    required_fields = [:memory_limit, :cpu_limit, :disk_space]

    case Enum.all?(required_fields, fn field -> Map.has_key?(requirements, field) end) do
      true -> :ok
      false -> {:error, :missing_resource_requirements}
    end
  end

  defp validate_environment_setup(environment_config) do
    required_sections = [:container_configuration, :testing_scenarios, :dependency_setup]

    case Enum.all?(required_sections, fn section -> Map.has_key?(environment_config, section) end) do
      true -> :ok
      false -> {:error, :missing_environment_configuration}
    end
  end

  defp validate_dependencies(repository_spec) do
    dependencies = Map.get(repository_spec, :dependencies, [])

    case length(dependencies) do
      0 -> {:error, :no_dependencies_specified}
      count when count > 10 -> {:error, :too_many_dependencies}
      _ -> :ok
    end
  end

  defp validate_testing_scenarios(repository_spec) do
    scenarios = Map.get(repository_spec, :testing_scenarios, [])

    case length(scenarios) do
      0 -> {:error, :no_testing_scenarios}
      count when count > 0 -> :ok
    end
  end

  defp validate_instance_count(task_instances, target_count) do
    actual_count = length(task_instances)
    # 10% tolerance
    tolerance = max(1, div(target_count, 10))

    if abs(actual_count - target_count) <= tolerance do
      :ok
    else
      {:error, {:instance_count_mismatch, actual_count, target_count}}
    end
  end

  defp validate_complexity_distribution(task_instances) do
    complexity_counts =
      task_instances
      |> Enum.group_by(fn instance -> Map.get(instance, :complexity, :medium) end)
      |> Enum.map(fn {complexity, instances} -> {complexity, length(instances)} end)
      |> Enum.into(%{})

    # Check if we have reasonable distribution
    total = length(task_instances)

    if total > 0 do
      # At least 20% should be medium complexity
      medium_percentage = Map.get(complexity_counts, :medium, 0) / total

      if medium_percentage >= 0.2 do
        :ok
      else
        {:error, :poor_complexity_distribution}
      end
    else
      {:error, :no_instances_to_validate}
    end
  end

  defp validate_scenario_coverage(task_instances, repository_spec) do
    expected_scenarios = Map.get(repository_spec, :testing_scenarios, [])

    actual_scenarios =
      task_instances
      |> Enum.map(fn instance -> Map.get(instance, :scenario) end)
      |> Enum.uniq()

    missing_scenarios = expected_scenarios -- actual_scenarios

    if missing_scenarios == [] do
      :ok
    else
      {:error, {:missing_scenarios, missing_scenarios}}
    end
  end

  defp calculate_quality_score(task_instances) do
    if task_instances == [] do
      0.0
    else
      # Basic quality scoring based on completeness
      complete_instances =
        task_instances
        |> Enum.count(fn instance ->
          Map.has_key?(instance, :description) and
            Map.has_key?(instance, :test_requirements) and
            Map.has_key?(instance, :complexity)
        end)

      complete_instances / length(task_instances) * 100.0
    end
  end

  defp validate_resource_conflicts(repositories) do
    # Check for memory/CPU conflicts
    total_memory =
      repositories
      |> Enum.reduce(0, fn repo, acc ->
        memory_gb = extract_memory_requirement(repo)
        acc + memory_gb
      end)

    # Warn if total exceeds reasonable limits (32GB)
    if total_memory > 32 do
      {:error, {:resource_conflict, :memory_exceeded, total_memory}}
    else
      :ok
    end
  end

  defp validate_port_conflicts(_repositories) do
    # Basic port conflict validation
    # In a real implementation, would check for port overlaps
    :ok
  end

  defp validate_dependency_conflicts(_repositories) do
    # Basic dependency conflict validation
    # In a real implementation, would check for conflicting library versions
    :ok
  end

  defp extract_memory_requirement(repository) do
    case get_in(repository, [:resource_requirements, :memory_limit]) do
      # Default 2GB
      nil ->
        2

      memory_str when is_binary(memory_str) ->
        case Regex.run(~r/(\d+)GB/, memory_str) do
          [_, number] -> String.to_integer(number)
          _ -> 2
        end

      memory_num when is_number(memory_num) ->
        memory_num

      _ ->
        2
    end
  end
end
