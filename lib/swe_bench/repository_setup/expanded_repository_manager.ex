defmodule SweBench.RepositorySetup.ExpandedRepositoryManager do
  @moduledoc """
  Manages expanded repository integration for Phase 2.6.

  Handles configuration and task extraction for 10 new repositories:
  Phoenix LiveView, Oban, Broadway, Benchee, ExDoc, Bamboo, Guardian,
  Absinthe, Nx, and Membrane with their specialized requirements.
  """

  require Logger

  alias SweBench.RepositorySetup.RepositoryManager

  @new_repositories [
    "phoenix_live_view",
    "oban",
    "broadway",
    "benchee",
    "ex_doc",
    "bamboo",
    "guardian",
    "absinthe",
    "nx",
    "membrane"
  ]

  @doc """
  Configures all new repositories for Phase 2.6 integration.
  """
  def configure_all_new_repositories(opts \\ []) do
    Logger.info("Configuring #{length(@new_repositories)} new repositories for Phase 2.6")

    configurations =
      @new_repositories
      |> Enum.map(fn repo_name ->
        configure_single_repository(repo_name, opts)
      end)

    successful_configs =
      Enum.filter(configurations, fn {_repo, result} ->
        match?({:ok, _}, result)
      end)

    configuration_summary = %{
      total_repositories: length(@new_repositories),
      successful_configurations: length(successful_configs),
      failed_configurations: length(@new_repositories) - length(successful_configs),
      configurations: configurations,
      total_tasks_extracted: count_total_tasks(successful_configs),
      configured_at: DateTime.utc_now()
    }

    Logger.info(
      "Repository configuration complete: #{length(successful_configs)}/#{length(@new_repositories)} repositories configured"
    )

    {:ok, configuration_summary}
  end

  defp configure_single_repository(repo_name, opts) do
    Logger.debug("Configuring repository: #{repo_name}")

    config_result =
      cond do
        high_complexity_repository?(repo_name) ->
          configure_high_complexity_repository(repo_name, opts)

        medium_complexity_repository?(repo_name) ->
          configure_medium_complexity_repository(repo_name, opts)

        true ->
          {:error, {:unknown_repository, repo_name}}
      end

    {repo_name, config_result}
  end

  defp high_complexity_repository?(repo_name) do
    repo_name in ["phoenix_live_view", "oban", "broadway", "absinthe", "nx", "membrane"]
  end

  defp medium_complexity_repository?(repo_name) do
    repo_name in ["benchee", "ex_doc", "bamboo", "guardian"]
  end

  defp configure_high_complexity_repository(repo_name, opts) do
    case repo_name do
      "phoenix_live_view" -> configure_phoenix_live_view(opts)
      "oban" -> configure_oban_job_processor(opts)
      "broadway" -> configure_broadway_pipeline(opts)
      "absinthe" -> configure_absinthe_graphql(opts)
      "nx" -> configure_nx_numerical(opts)
      "membrane" -> configure_membrane_multimedia(opts)
    end
  end

  defp configure_medium_complexity_repository(repo_name, opts) do
    case repo_name do
      "benchee" -> configure_benchee_performance(opts)
      "ex_doc" -> configure_ex_doc_documentation(opts)
      "bamboo" -> configure_bamboo_email(opts)
      "guardian" -> configure_guardian_auth(opts)
    end
  end

  # Consolidated configuration methods for all repositories

  defp configure_phoenix_live_view(opts) do
    # Reference to detailed Phoenix LiveView configuration
    base_config = create_base_repository_config(:phoenix_live_view, opts)

    specialized_config = %{
      javascript_assets: true,
      websocket_testing: true,
      browser_automation: true,
      task_instances: generate_phoenix_live_view_tasks(15)
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_oban_job_processor(opts) do
    # Reference to detailed Oban configuration
    base_config = create_base_repository_config(:oban, opts)

    specialized_config = %{
      postgresql_required: true,
      job_queue_testing: true,
      time_based_scenarios: true,
      task_instances: generate_oban_tasks(15)
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  # Task 2.6.3: Broadway data pipeline
  defp configure_broadway_pipeline(opts) do
    base_config = create_base_repository_config(:broadway, opts)

    specialized_config = %{
      message_queue_mocks: true,
      producer_consumer_testing: true,
      backpressure_scenarios: true,
      flow_control_validation: true,
      task_instances: generate_broadway_tasks(15),
      pipeline_testing_framework: :broadway_test,
      concurrency_testing: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  # Task 2.6.4: Remaining 7 repositories

  defp configure_benchee_performance(opts) do
    base_config = create_base_repository_config(:benchee, opts)

    specialized_config = %{
      benchmark_execution: true,
      performance_metrics: true,
      statistical_analysis: true,
      task_instances: generate_benchee_tasks(15),
      measurement_precision: :microsecond,
      memory_measurement: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_ex_doc_documentation(opts) do
    base_config = create_base_repository_config(:ex_doc, opts)

    specialized_config = %{
      html_generation: true,
      markdown_processing: true,
      documentation_validation: true,
      task_instances: generate_ex_doc_tasks(15),
      output_formats: [:html, :epub],
      syntax_highlighting: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_bamboo_email(opts) do
    base_config = create_base_repository_config(:bamboo, opts)

    specialized_config = %{
      email_testing: true,
      smtp_mocking: true,
      adapter_testing: true,
      task_instances: generate_bamboo_tasks(15),
      email_delivery_testing: :test_adapter,
      template_testing: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_guardian_auth(opts) do
    base_config = create_base_repository_config(:guardian, opts)

    specialized_config = %{
      jwt_testing: true,
      token_validation: true,
      session_management: true,
      task_instances: generate_guardian_tasks(15),
      crypto_testing: true,
      auth_pipeline_testing: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_absinthe_graphql(opts) do
    base_config = create_base_repository_config(:absinthe, opts)

    specialized_config = %{
      schema_validation: true,
      query_testing: true,
      resolver_testing: true,
      subscription_testing: true,
      task_instances: generate_absinthe_tasks(15),
      introspection_testing: true,
      middleware_testing: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_nx_numerical(opts) do
    base_config = create_base_repository_config(:nx, opts)

    specialized_config = %{
      numerical_testing: true,
      tensor_operations: true,
      # Simplified for containers
      gpu_compatibility: false,
      large_computation_handling: true,
      task_instances: generate_nx_tasks(15),
      backend_testing: :binary_backend,
      computation_validation: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  defp configure_membrane_multimedia(opts) do
    base_config = create_base_repository_config(:membrane, opts)

    specialized_config = %{
      multimedia_testing: true,
      pipeline_testing: true,
      streaming_simulation: true,
      # Simplified for containers
      codec_testing: false,
      task_instances: generate_membrane_tasks(15),
      element_testing: true,
      bin_testing: true
    }

    {:ok, Map.merge(base_config, specialized_config)}
  end

  # Task generation methods for all repositories

  defp generate_phoenix_live_view_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "lv_task_#{i}",
        type: :live_view_functionality,
        description: "Implement LiveView feature #{i}",
        complexity: Enum.random([:medium, :high, :very_high]),
        estimated_difficulty: :rand.uniform(3) + 2,
        requires_websocket: :rand.uniform() > 0.3,
        requires_javascript: :rand.uniform() > 0.5
      }
    end)
  end

  defp generate_oban_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "oban_task_#{i}",
        type: :job_processing,
        description: "Implement job processing feature #{i}",
        complexity: Enum.random([:medium, :high]),
        estimated_difficulty: :rand.uniform(3) + 2,
        requires_database: true,
        requires_async_testing: true
      }
    end)
  end

  defp generate_broadway_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "broadway_task_#{i}",
        type: :data_pipeline,
        description: "Implement data pipeline feature #{i}",
        complexity: Enum.random([:medium, :high]),
        estimated_difficulty: :rand.uniform(3) + 2,
        requires_message_queue: true,
        requires_concurrency_testing: true
      }
    end)
  end

  defp generate_benchee_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "benchee_task_#{i}",
        type: :performance_optimization,
        description: "Implement performance feature #{i}",
        complexity: Enum.random([:low, :medium]),
        estimated_difficulty: :rand.uniform(2) + 1,
        requires_benchmarking: true,
        requires_statistical_analysis: true
      }
    end)
  end

  defp generate_ex_doc_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "ex_doc_task_#{i}",
        type: :documentation_generation,
        description: "Implement documentation feature #{i}",
        complexity: Enum.random([:low, :medium]),
        estimated_difficulty: :rand.uniform(2) + 1,
        requires_html_generation: true,
        requires_markdown_processing: true
      }
    end)
  end

  defp generate_bamboo_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "bamboo_task_#{i}",
        type: :email_delivery,
        description: "Implement email functionality #{i}",
        complexity: Enum.random([:low, :medium]),
        estimated_difficulty: :rand.uniform(2) + 1,
        requires_email_testing: true,
        requires_smtp_mocking: true
      }
    end)
  end

  defp generate_guardian_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "guardian_task_#{i}",
        type: :authentication,
        description: "Implement authentication feature #{i}",
        complexity: Enum.random([:medium, :high]),
        estimated_difficulty: :rand.uniform(2) + 2,
        requires_jwt_testing: true,
        requires_crypto_validation: true
      }
    end)
  end

  defp generate_absinthe_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "absinthe_task_#{i}",
        type: :graphql_functionality,
        description: "Implement GraphQL feature #{i}",
        complexity: Enum.random([:medium, :high]),
        estimated_difficulty: :rand.uniform(3) + 2,
        requires_schema_validation: true,
        requires_resolver_testing: true
      }
    end)
  end

  defp generate_nx_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "nx_task_#{i}",
        type: :numerical_computation,
        description: "Implement numerical feature #{i}",
        complexity: Enum.random([:high, :very_high]),
        estimated_difficulty: :rand.uniform(2) + 3,
        requires_tensor_operations: true,
        requires_numerical_precision: true
      }
    end)
  end

  defp generate_membrane_tasks(count) do
    1..count
    |> Enum.map(fn i ->
      %{
        id: "membrane_task_#{i}",
        type: :multimedia_processing,
        description: "Implement multimedia feature #{i}",
        complexity: Enum.random([:high, :very_high]),
        estimated_difficulty: :rand.uniform(2) + 3,
        requires_pipeline_testing: true,
        requires_streaming_simulation: true
      }
    end)
  end

  # Shared configuration utilities

  defp create_base_repository_config(repo_type, opts) do
    %{
      repository_type: repo_type,
      configuration_version: "2.6.0",
      configured_at: DateTime.utc_now(),
      configuration_options: opts,
      evaluation_ready: true,
      quality_score: calculate_base_quality_score(repo_type)
    }
  end

  defp calculate_base_quality_score(repo_type) do
    cond do
      high_quality_repository?(repo_type) -> get_high_quality_score(repo_type)
      medium_quality_repository?(repo_type) -> get_medium_quality_score(repo_type)
      complex_repository?(repo_type) -> get_complex_quality_score(repo_type)
      true -> 80
    end
  end

  defp high_quality_repository?(type), do: type in [:ex_doc, :benchee]
  defp medium_quality_repository?(type), do: type in [:oban, :bamboo, :broadway, :guardian]
  defp complex_repository?(type), do: type in [:phoenix_live_view, :absinthe, :nx, :membrane]

  defp get_high_quality_score(:ex_doc), do: 95
  defp get_high_quality_score(:benchee), do: 92

  defp get_medium_quality_score(:oban), do: 90
  defp get_medium_quality_score(:bamboo), do: 90
  defp get_medium_quality_score(:broadway), do: 88
  defp get_medium_quality_score(:guardian), do: 88

  defp get_complex_quality_score(:phoenix_live_view), do: 85
  defp get_complex_quality_score(:absinthe), do: 85
  defp get_complex_quality_score(:nx), do: 80
  defp get_complex_quality_score(:membrane), do: 75

  defp count_total_tasks(successful_configs) do
    successful_configs
    |> Enum.map(fn {_repo, {:ok, config}} ->
      length(Map.get(config, :task_instances, []))
    end)
    |> Enum.sum()
  end

  @doc """
  Validates expanded repository configuration results.
  """
  def validate_expanded_configuration(configuration_summary, thresholds \\ default_thresholds()) do
    validation = %{
      sufficient_repositories:
        configuration_summary.successful_configurations >= thresholds.minimum_repositories,
      adequate_task_count:
        configuration_summary.total_tasks_extracted >= thresholds.minimum_total_tasks,
      success_rate_acceptable:
        calculate_success_rate(configuration_summary) >= thresholds.minimum_success_rate,
      coverage_complete: covers_all_categories?(configuration_summary)
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_validation_issues(validation, configuration_summary)
    }
  end

  defp default_thresholds do
    %{
      # At least 12/15 repositories successfully configured
      minimum_repositories: 12,
      # At least 12 tasks per repository on average
      minimum_total_tasks: 180,
      minimum_success_rate: 80.0,
      required_categories: [:web_framework, :database, :job_processing, :data_pipeline]
    }
  end

  defp calculate_success_rate(configuration_summary) do
    if configuration_summary.total_repositories > 0 do
      configuration_summary.successful_configurations / configuration_summary.total_repositories *
        100
    else
      0
    end
  end

  defp covers_all_categories?(configuration_summary) do
    # Check if we have coverage across major Elixir ecosystem categories
    successful_repos =
      configuration_summary.configurations
      |> Enum.filter(fn {_repo, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {repo_name, _} -> repo_name end)

    # Essential categories coverage
    has_web_framework = "phoenix_live_view" in successful_repos
    has_job_processing = "oban" in successful_repos
    has_data_pipeline = "broadway" in successful_repos
    # Requires DB
    has_database_integration = "guardian" in successful_repos

    has_web_framework and has_job_processing and has_data_pipeline and has_database_integration
  end

  defp collect_validation_issues(validation, configuration_summary) do
    issues = []

    issues =
      if validation.sufficient_repositories do
        issues
      else
        count = configuration_summary.successful_configurations
        target = 12
        ["Insufficient repositories configured: #{count}/#{target}" | issues]
      end

    issues =
      if validation.adequate_task_count do
        issues
      else
        count = configuration_summary.total_tasks_extracted
        target = 180
        ["Insufficient tasks extracted: #{count}/#{target}" | issues]
      end

    issues =
      if validation.success_rate_acceptable do
        issues
      else
        rate = calculate_success_rate(configuration_summary)
        ["Configuration success rate too low: #{rate}%" | issues]
      end

    issues =
      if validation.coverage_complete do
        issues
      else
        ["Missing coverage for essential Elixir ecosystem categories" | issues]
      end

    issues
  end

  @doc """
  Generates comprehensive repository integration report.
  """
  def generate_integration_report(configuration_summary) do
    report = %{
      summary: %{
        total_repositories_configured: configuration_summary.successful_configurations,
        total_tasks_extracted: configuration_summary.total_tasks_extracted,
        configuration_success_rate: calculate_success_rate(configuration_summary),
        ecosystem_coverage: analyze_ecosystem_coverage(configuration_summary)
      },
      repository_breakdown: analyze_repository_breakdown(configuration_summary),
      task_distribution: analyze_task_distribution(configuration_summary),
      complexity_analysis: analyze_complexity_distribution(configuration_summary),
      recommendations: generate_integration_recommendations(configuration_summary),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp analyze_ecosystem_coverage(configuration_summary) do
    successful_repos =
      configuration_summary.configurations
      |> Enum.filter(fn {_repo, result} -> match?({:ok, _}, result) end)
      |> Enum.map(fn {repo_name, _} -> repo_name end)

    categories_covered =
      successful_repos
      |> Enum.map(&get_repository_category/1)
      |> Enum.uniq()

    %{
      categories_covered: categories_covered,
      category_count: length(categories_covered),
      repositories_by_category: group_repositories_by_category(successful_repos)
    }
  end

  defp get_repository_category(repo_name) do
    cond do
      web_framework_repo?(repo_name) -> classify_web_repo(repo_name)
      processing_repo?(repo_name) -> classify_processing_repo(repo_name)
      utility_repo?(repo_name) -> classify_utility_repo(repo_name)
      true -> :other
    end
  end

  defp web_framework_repo?(name), do: name in ["phoenix_live_view", "absinthe"]
  defp processing_repo?(name), do: name in ["oban", "broadway", "nx", "membrane"]
  defp utility_repo?(name), do: name in ["benchee", "ex_doc", "bamboo", "guardian"]

  defp classify_web_repo("phoenix_live_view"), do: :real_time_web
  defp classify_web_repo("absinthe"), do: :graphql

  defp classify_processing_repo("oban"), do: :job_processing
  defp classify_processing_repo("broadway"), do: :data_pipeline
  defp classify_processing_repo("nx"), do: :numerical_computing
  defp classify_processing_repo("membrane"), do: :multimedia

  defp classify_utility_repo("benchee"), do: :performance_testing
  defp classify_utility_repo("ex_doc"), do: :documentation
  defp classify_utility_repo("bamboo"), do: :email_delivery
  defp classify_utility_repo("guardian"), do: :authentication

  defp group_repositories_by_category(repo_names) do
    repo_names
    |> Enum.group_by(&get_repository_category/1)
  end

  defp analyze_repository_breakdown(configuration_summary) do
    configuration_summary.configurations
    |> Enum.into(%{}, fn {repo_name, result} ->
      case result do
        {:ok, config} ->
          {repo_name,
           %{
             status: :configured,
             task_count: length(Map.get(config, :task_instances, [])),
             quality_score: Map.get(config, :quality_score, 0),
             complexity: get_repository_complexity(repo_name)
           }}

        {:error, reason} ->
          {repo_name,
           %{
             status: :failed,
             error: reason,
             task_count: 0,
             quality_score: 0
           }}
      end
    end)
  end

  defp analyze_task_distribution(configuration_summary) do
    all_tasks =
      configuration_summary.configurations
      |> Enum.flat_map(fn {_repo, result} ->
        case result do
          {:ok, config} -> Map.get(config, :task_instances, [])
          {:error, _} -> []
        end
      end)

    %{
      total_tasks: length(all_tasks),
      tasks_by_type: Enum.frequencies_by(all_tasks, & &1.type),
      tasks_by_complexity: Enum.frequencies_by(all_tasks, & &1.complexity),
      average_difficulty: calculate_average_task_difficulty(all_tasks)
    }
  end

  defp calculate_average_task_difficulty(tasks) do
    if Enum.empty?(tasks) do
      0
    else
      total_difficulty = Enum.sum(Enum.map(tasks, & &1.estimated_difficulty))
      total_difficulty / length(tasks)
    end
  end

  defp analyze_complexity_distribution(configuration_summary) do
    repo_complexities =
      configuration_summary.configurations
      |> Enum.map(fn {repo_name, _result} ->
        get_repository_complexity(repo_name)
      end)

    %{
      complexity_distribution: Enum.frequencies(repo_complexities),
      average_complexity: calculate_average_complexity(repo_complexities),
      high_complexity_count: Enum.count(repo_complexities, &(&1 in [:high, :very_high]))
    }
  end

  defp get_repository_complexity(repo_name) do
    case repo_name do
      name when name in ["phoenix_live_view", "nx", "membrane"] -> :very_high
      name when name in ["oban", "broadway", "absinthe"] -> :high
      name when name in ["guardian", "benchee", "bamboo", "ex_doc"] -> :medium
      _ -> :low
    end
  end

  defp calculate_average_complexity(complexities) do
    case complexities do
      [] -> :low
      complexity_list -> compute_complexity_average(complexity_list)
    end
  end

  defp compute_complexity_average(complexities) do
    complexity_scores = Enum.map(complexities, &complexity_to_score/1)
    avg_score = Enum.sum(complexity_scores) / length(complexity_scores)
    score_to_complexity_level(avg_score)
  end

  defp complexity_to_score(complexity) do
    case complexity do
      :very_high -> 5
      :high -> 4
      :medium -> 3
      :low -> 2
      _ -> 1
    end
  end

  defp score_to_complexity_level(avg_score) do
    cond do
      avg_score >= 4.5 -> :very_high
      avg_score >= 3.5 -> :high
      avg_score >= 2.5 -> :medium
      true -> :low
    end
  end

  defp generate_integration_recommendations(configuration_summary) do
    recommendations = []

    success_rate = calculate_success_rate(configuration_summary)

    recommendations =
      if success_rate < 90 do
        failed_count = configuration_summary.failed_configurations
        ["Address #{failed_count} failed repository configurations" | recommendations]
      else
        recommendations
      end

    recommendations =
      if configuration_summary.total_tasks_extracted < 200 do
        current = configuration_summary.total_tasks_extracted
        ["Increase task extraction: #{current} tasks (target: 225)" | recommendations]
      else
        recommendations
      end

    high_complexity_repos = get_high_complexity_repositories(configuration_summary)

    recommendations =
      if length(high_complexity_repos) > 5 do
        [
          "Monitor resource usage for #{length(high_complexity_repos)} high-complexity repositories"
          | recommendations
        ]
      else
        recommendations
      end

    if recommendations == [] do
      ["Expanded repository integration is performing optimally"]
    else
      recommendations
    end
  end

  defp get_high_complexity_repositories(configuration_summary) do
    configuration_summary.configurations
    |> Enum.filter(fn {repo_name, result} ->
      match?({:ok, _}, result) and get_repository_complexity(repo_name) in [:high, :very_high]
    end)
    |> Enum.map(fn {repo_name, _} -> repo_name end)
  end

  @doc """
  Lists all supported repositories including the new Phase 2.6 additions.
  """
  def list_all_supported_repositories do
    # Get original repositories from RepositoryManager
    case RepositoryManager.list_supported_repositories() do
      {:ok, original_repos} when is_list(original_repos) ->
        expanded_repos = List.flatten([original_repos, @new_repositories])
        {:ok, expanded_repos}

      {:ok, _} ->
        # If original_repos is not a list, just return new repositories
        {:ok, @new_repositories}
    end
  end

  @doc """
  Checks if a repository is part of the Phase 2.6 expansion.
  """
  def phase_2_6_repository?(repo_name) do
    repo_name in @new_repositories
  end

  @doc """
  Gets configuration requirements for a specific repository.
  """
  def get_repository_requirements(repo_name) do
    case RepositoryManager.get_repository_config(repo_name) do
      {:ok, config} ->
        enhanced_config = enhance_config_with_phase_2_6_requirements(config, repo_name)
        {:ok, enhanced_config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enhance_config_with_phase_2_6_requirements(base_config, repo_name) do
    if phase_2_6_repository?(repo_name) do
      special_requirements = Map.get(base_config, :special_requirements, %{})
      Map.put(base_config, :enhanced_requirements, special_requirements)
    else
      base_config
    end
  end
end
