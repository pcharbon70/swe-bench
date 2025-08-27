defmodule SweBench.RepositorySetup.ResourceAllocationManager do
  @moduledoc """
  Dynamic resource allocation and scaling for repository tiers.

  Manages memory, CPU, disk, and timeout allocation based on repository
  complexity and tier classification.
  """

  require Logger

  @production_tier_config %{
    memory_limit: "8GB",
    cpu_limit: "4",
    disk_space: "20GB",
    network_bandwidth: "1Gbps",
    concurrent_tasks: 8,
    timeout_multiplier: 3.0,
    priority: :high
  }

  @specialized_framework_config %{
    memory_limit: "4GB",
    cpu_limit: "2",
    disk_space: "10GB",
    network_bandwidth: "500Mbps",
    concurrent_tasks: 4,
    timeout_multiplier: 2.0,
    priority: :medium
  }

  @core_library_config %{
    memory_limit: "2GB",
    cpu_limit: "1",
    disk_space: "5GB",
    network_bandwidth: "200Mbps",
    concurrent_tasks: 2,
    timeout_multiplier: 1.0,
    priority: :standard
  }

  @doc """
  Allocates resources for a production repository based on its specifications.
  """
  def allocate_production_resources(repository_spec, options \\ []) do
    base_config = get_tier_config(repository_spec.tier)

    # Apply repository-specific overrides
    repository_overrides = Map.get(repository_spec, :resource_requirements, %{})

    # Apply user options
    user_overrides = Enum.into(options, %{})

    # Merge configurations with priority: user_options > repository_spec > tier_defaults
    final_allocation = base_config
    |> Map.merge(repository_overrides)
    |> Map.merge(user_overrides)
    |> add_allocation_metadata(repository_spec)

    Logger.info("Allocated resources for #{repository_spec.name}: #{inspect(final_allocation)}")
    final_allocation
  end

  @doc """
  Allocates resources for specialized framework repositories.
  """
  def allocate_specialized_resources(repository_spec, options \\ []) do
    allocate_production_resources(
      %{repository_spec | tier: :specialized_framework},
      options
    )
  end

  @doc """
  Allocates resources for core library repositories.
  """
  def allocate_core_library_resources(repository_spec, options \\ []) do
    allocate_production_resources(
      %{repository_spec | tier: :core_library},
      options
    )
  end

  @doc """
  Returns the total resource requirements for all allocated repositories.
  """
  def calculate_total_resources(allocations) when is_list(allocations) do
    total_memory = allocations
    |> Enum.reduce(0, fn allocation, acc ->
        memory_gb = parse_memory_limit(Map.get(allocation, :memory_limit, "0GB"))
        acc + memory_gb
    end)

    total_cpu = allocations
    |> Enum.reduce(0, fn allocation, acc ->
        cpu_count = parse_cpu_limit(Map.get(allocation, :cpu_limit, "0"))
        acc + cpu_count
    end)

    total_disk = allocations
    |> Enum.reduce(0, fn allocation, acc ->
        disk_gb = parse_disk_space(Map.get(allocation, :disk_space, "0GB"))
        acc + disk_gb
    end)

    %{
      total_memory_gb: total_memory,
      total_cpu_cores: total_cpu,
      total_disk_gb: total_disk,
      estimated_monthly_cost: estimate_infrastructure_cost(total_memory, total_cpu)
    }
  end

  @doc """
  Optimizes resource allocation for performance and cost efficiency.
  """
  def optimize_resource_allocation(current_allocations) do
    # Analyze current resource usage and suggest optimizations
    optimization_suggestions = analyze_resource_efficiency(current_allocations)

    %{
      current_allocation: calculate_total_resources(current_allocations),
      optimization_opportunities: optimization_suggestions,
      potential_savings: calculate_potential_savings(optimization_suggestions)
    }
  end

  # Private functions

  defp get_tier_config(:production), do: @production_tier_config
  defp get_tier_config(:specialized_framework), do: @specialized_framework_config
  defp get_tier_config(:core_library), do: @core_library_config
  defp get_tier_config(_), do: @core_library_config

  defp add_allocation_metadata(allocation, repository_spec) do
    Map.merge(allocation, %{
      repository_name: repository_spec.name,
      tier: repository_spec.tier,
      complexity: repository_spec.complexity,
      allocated_at: DateTime.utc_now(),
      allocation_id: generate_allocation_id()
    })
  end

  defp parse_memory_limit(memory_str) do
    case String.downcase(memory_str) do
      "1gb" -> 1
      "2gb" -> 2
      "4gb" -> 4
      "6gb" -> 6
      "8gb" -> 8
      _ ->
        # Try to parse number + gb
        case Regex.run(~r/(\d+)gb/, String.downcase(memory_str)) do
          [_, number] -> String.to_integer(number)
          _ -> 0
        end
    end
  end

  defp parse_cpu_limit(cpu_str) when is_binary(cpu_str) do
    case Integer.parse(cpu_str) do
      {number, _} -> number
      :error -> 1
    end
  end

  defp parse_cpu_limit(cpu_num) when is_integer(cpu_num), do: cpu_num
  defp parse_cpu_limit(_), do: 1

  defp parse_disk_space(disk_str) do
    case String.downcase(disk_str) do
      "5gb" -> 5
      "10gb" -> 10
      "15gb" -> 15
      "20gb" -> 20
      _ ->
        case Regex.run(~r/(\d+)gb/, String.downcase(disk_str)) do
          [_, number] -> String.to_integer(number)
          _ -> 5  # Default 5GB
        end
    end
  end

  defp estimate_infrastructure_cost(memory_gb, cpu_cores) do
    # Rough AWS pricing estimate (for planning purposes)
    memory_cost = memory_gb * 0.10  # $0.10 per GB/month
    cpu_cost = cpu_cores * 15.0     # $15 per core/month

    memory_cost + cpu_cost
  end

  defp analyze_resource_efficiency(allocations) do
    # Analyze allocations for optimization opportunities
    high_memory_repos = allocations
    |> Enum.filter(fn allocation ->
        memory_gb = parse_memory_limit(Map.get(allocation, :memory_limit, "0GB"))
        memory_gb > 6
    end)

    suggestions = []

    suggestions = if length(high_memory_repos) > 2 do
      ["Consider memory pooling for high-memory repositories" | suggestions]
    else
      suggestions
    end

    suggestions = if length(allocations) > 20 do
      ["Consider repository sharding for better resource distribution" | suggestions]
    else
      suggestions
    end

    suggestions
  end

  defp calculate_potential_savings(optimization_suggestions) do
    # Estimate potential cost savings from optimizations
    base_savings = length(optimization_suggestions) * 50.0  # $50 per optimization

    %{
      estimated_monthly_savings: base_savings,
      optimization_count: length(optimization_suggestions)
    }
  end

  defp generate_allocation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
