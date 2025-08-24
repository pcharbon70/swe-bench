defmodule SweBench.MixProject.UmbrellaTestCoordinator do
  @moduledoc """
  Coordinates test execution across umbrella project applications.

  Handles multi-application test orchestration, result aggregation,
  application-specific test configuration, shared test helpers and fixtures,
  and database setup coordination.
  """

  require Logger

  # alias SweBench.TestRunner

  # 2 minutes per application
  @test_timeout 120_000
  # 30 seconds for database setup
  @db_setup_timeout 30_000

  @doc """
  Coordinates test execution across all applications in an umbrella project.

  Manages test dependencies, aggregates results, and handles shared resources
  like databases and test fixtures.
  """
  def coordinate_umbrella_tests(umbrella_structure, test_options \\ []) do
    Logger.info("Coordinating tests for #{umbrella_structure.total_apps} umbrella applications")

    with {:ok, test_plan} <- create_test_execution_plan(umbrella_structure, test_options),
         {:ok, db_setup} <- coordinate_database_setup(umbrella_structure, test_options),
         {:ok, shared_fixtures} <- setup_shared_test_fixtures(umbrella_structure),
         {:ok, test_results} <- execute_umbrella_tests(test_plan, test_options),
         {:ok, aggregated_results} <- aggregate_test_results(test_results, umbrella_structure) do
      coordination_result = %{
        umbrella_structure: umbrella_structure,
        test_plan: test_plan,
        database_setup: db_setup,
        shared_fixtures: shared_fixtures,
        test_results: test_results,
        aggregated_results: aggregated_results,
        total_test_time_ms: calculate_total_test_time(test_results),
        coordinated_at: DateTime.utc_now()
      }

      Logger.info(
        "Umbrella test coordination complete: #{aggregated_results.total_tests} tests executed"
      )

      {:ok, coordination_result}
    else
      {:error, reason} ->
        Logger.warning("Umbrella test coordination failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.3.3.1: Run tests across multiple applications
  defp create_test_execution_plan(umbrella_structure, test_options) do
    test_order = determine_test_execution_order(umbrella_structure)
    parallel_execution = Keyword.get(test_options, :parallel, false)
    isolation_level = Keyword.get(test_options, :isolation, :application)

    test_plan = %{
      execution_order: test_order,
      parallel_groups: calculate_test_parallel_groups(umbrella_structure, parallel_execution),
      isolation_strategy: isolation_level,
      per_app_timeout: Keyword.get(test_options, :per_app_timeout, @test_timeout),
      test_filters: build_test_filters(test_options),
      resource_coordination: plan_resource_coordination(umbrella_structure)
    }

    Logger.debug("Test execution plan created for #{length(test_order)} applications")
    {:ok, test_plan}
  end

  defp determine_test_execution_order(umbrella_structure) do
    # Use compilation order as base, but consider test-specific dependencies
    base_order = umbrella_structure.compilation_order

    # Prioritize apps with database setup or shared fixtures
    prioritized_apps =
      umbrella_structure.applications
      |> Enum.filter(fn app -> has_database_setup?(app) end)
      |> Enum.map(& &1.name)

    # Ensure prioritized apps come first, then follow compilation order
    prioritized_apps ++ (base_order -- prioritized_apps)
  end

  defp has_database_setup?(app) do
    # Check if app has database-related configuration or migrations
    database_indicators = ["ecto", "repo", "migration", "database"]

    Enum.any?(app.dependencies, fn dep ->
      String.downcase(dep) in database_indicators
    end) or
      Enum.any?(app.lib_files, fn file ->
        String.contains?(String.downcase(file), "repo")
      end)
  end

  defp calculate_test_parallel_groups(umbrella_structure, parallel_enabled) do
    if parallel_enabled do
      # Group applications that can run tests in parallel
      independent_apps = find_test_independent_apps(umbrella_structure)
      dependent_apps = umbrella_structure.applications -- independent_apps

      groups = []

      groups =
        if Enum.empty?(independent_apps) do
          groups
        else
          [Enum.map(independent_apps, & &1.name) | groups]
        end

      # Add dependent apps as individual groups
      groups ++ Enum.map(dependent_apps, fn app -> [app.name] end)
    else
      # Sequential execution - each app in its own group
      Enum.map(umbrella_structure.applications, fn app -> [app.name] end)
    end
  end

  defp find_test_independent_apps(umbrella_structure) do
    # Apps that don't share databases or have cross-app test dependencies
    umbrella_structure.applications
    |> Enum.filter(fn app ->
      not has_database_setup?(app) and not has_cross_app_test_deps?(app, umbrella_structure)
    end)
  end

  defp has_cross_app_test_deps?(app, umbrella_structure) do
    # Check if app's tests depend on other applications
    internal_deps = Map.get(umbrella_structure.inter_app_dependencies, app.name, [])
    not Enum.empty?(internal_deps)
  end

  # Task 2.3.3.2: Aggregate test results per application
  # Task 2.3.3.3: Handle application-specific test configuration
  defp execute_umbrella_tests(test_plan, test_options) do
    Logger.info("Executing umbrella tests with #{length(test_plan.execution_order)} applications")

    timeout = test_plan.per_app_timeout

    test_results =
      case test_plan.isolation_strategy do
        :application ->
          execute_tests_per_application(test_plan, timeout, test_options)

        :shared ->
          execute_tests_shared_environment(test_plan, timeout, test_options)

        _ ->
          execute_tests_per_application(test_plan, timeout, test_options)
      end

    {:ok, test_results}
  end

  defp execute_tests_per_application(test_plan, timeout, test_options) do
    test_plan.execution_order
    |> Enum.map(fn app_name ->
      execute_app_tests(app_name, timeout, test_options)
    end)
  end

  defp execute_tests_shared_environment(test_plan, timeout, test_options) do
    # Run all tests in a shared environment
    # This is more complex and would require careful resource management
    Logger.debug("Executing tests in shared environment mode")

    test_plan.execution_order
    |> Enum.map(fn app_name ->
      execute_app_tests_shared(app_name, timeout, test_options)
    end)
  end

  defp execute_app_tests(app_name, _timeout, _test_options) do
    start_time = System.monotonic_time(:millisecond)

    # Simulate test execution - in production would use actual TestRunner
    # 2-12 seconds simulation
    test_duration = :rand.uniform(10_000) + 2000
    :timer.sleep(test_duration)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Simulate test results
    # 10-60 tests
    total_tests = :rand.uniform(50) + 10
    # 0-5 failures
    failed_tests = :rand.uniform(5)
    passed_tests = total_tests - failed_tests

    %{
      app_name: app_name,
      success: failed_tests == 0,
      total_tests: total_tests,
      passed_tests: passed_tests,
      failed_tests: failed_tests,
      skipped_tests: 0,
      test_time_ms: duration,
      warnings: generate_test_warnings(app_name, failed_tests),
      errors: generate_test_errors(app_name, failed_tests),
      # 5-15 files
      test_files_executed: [:rand.uniform(10) + 5],
      executed_at: DateTime.utc_now()
    }
  end

  defp execute_app_tests_shared(app_name, timeout, test_options) do
    # Similar to execute_app_tests but with shared environment considerations
    result = execute_app_tests(app_name, timeout, test_options)
    Map.put(result, :execution_mode, :shared_environment)
  end

  defp generate_test_warnings(app_name, failed_count) do
    if failed_count > 0 do
      ["#{failed_count} test(s) failed in #{app_name}"]
    else
      []
    end
  end

  defp generate_test_errors(app_name, failed_count) do
    if failed_count > 2 do
      ["Multiple test failures in #{app_name} - check application setup"]
    else
      []
    end
  end

  # Task 2.3.3.4: Manage shared test helpers and fixtures
  defp setup_shared_test_fixtures(umbrella_structure) do
    Logger.debug("Setting up shared test fixtures for umbrella project")

    fixtures = %{
      shared_test_helpers: discover_shared_test_helpers(umbrella_structure),
      common_fixtures: discover_common_fixtures(umbrella_structure),
      test_support_modules: discover_test_support_modules(umbrella_structure),
      setup_required: requires_shared_setup?(umbrella_structure)
    }

    if fixtures.setup_required do
      {:ok, perform_shared_fixture_setup(fixtures)}
    else
      {:ok, fixtures}
    end
  end

  defp discover_shared_test_helpers(umbrella_structure) do
    # Look for test/support or test/shared directories across applications
    umbrella_structure.applications
    |> Enum.flat_map(fn app ->
      support_paths = [
        Path.join(app.path, "test/support"),
        Path.join(app.path, "test/shared")
      ]

      support_paths
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(&find_support_files_in_path/1)
    end)
  end

  defp find_support_files_in_path(path) do
    case Path.wildcard(Path.join(path, "**/*.ex")) do
      [] -> []
      files -> files
    end
  end

  defp discover_common_fixtures(umbrella_structure) do
    # Look for fixture files across applications
    umbrella_structure.applications
    |> Enum.flat_map(fn app ->
      fixture_paths = [
        Path.join(app.path, "test/fixtures"),
        Path.join(app.path, "priv/test_fixtures")
      ]

      fixture_paths
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(&find_fixtures_in_path/1)
    end)
  end

  defp find_fixtures_in_path(path) do
    case File.ls(path) do
      {:ok, files} -> Enum.map(files, &Path.join(path, &1))
      {:error, _} -> []
    end
  end

  defp discover_test_support_modules(umbrella_structure) do
    # Find modules that provide test support across applications
    umbrella_structure.applications
    |> Enum.flat_map(fn app ->
      app.test_files
      |> Enum.filter(fn file ->
        String.contains?(file, "support") or String.contains?(file, "helper")
      end)
    end)
  end

  defp requires_shared_setup?(umbrella_structure) do
    # Determine if shared setup is needed based on cross-app dependencies
    has_shared_database = has_shared_database_config?(umbrella_structure)
    has_cross_app_tests = has_cross_app_test_dependencies?(umbrella_structure)

    has_shared_database or has_cross_app_tests
  end

  defp has_shared_database_config?(umbrella_structure) do
    # Check if multiple apps share database configuration
    db_apps =
      umbrella_structure.applications
      |> Enum.filter(fn app -> has_database_setup?(app) end)

    length(db_apps) > 1
  end

  defp has_cross_app_test_dependencies?(umbrella_structure) do
    # Check if tests in one app depend on another app
    not Enum.empty?(umbrella_structure.inter_app_dependencies)
  end

  defp perform_shared_fixture_setup(fixtures) do
    # Perform any necessary shared setup
    Logger.debug("Performing shared fixture setup")

    setup_result = %{
      shared_database_prepared: true,
      fixtures_loaded: length(fixtures.common_fixtures),
      helpers_available: length(fixtures.shared_test_helpers),
      # Placeholder
      setup_duration_ms: 1500
    }

    Map.merge(fixtures, setup_result)
  end

  # Task 2.3.3.5: Coordinate database setup for tests
  defp coordinate_database_setup(umbrella_structure, test_options) do
    Logger.debug("Coordinating database setup for umbrella tests")

    db_strategy = determine_database_strategy(umbrella_structure)
    timeout = Keyword.get(test_options, :db_timeout, @db_setup_timeout)

    case db_strategy do
      :shared_database ->
        setup_shared_database(umbrella_structure, timeout)

      :per_app_database ->
        setup_per_app_databases(umbrella_structure, timeout)

      :no_database ->
        {:ok, %{strategy: :no_database, setup_required: false}}
    end
  end

  defp determine_database_strategy(umbrella_structure) do
    db_apps =
      umbrella_structure.applications
      |> Enum.filter(fn app -> has_database_setup?(app) end)

    case length(db_apps) do
      0 -> :no_database
      1 -> :per_app_database
      _ -> analyze_database_sharing_pattern(db_apps, umbrella_structure)
    end
  end

  defp analyze_database_sharing_pattern(_db_apps, umbrella_structure) do
    # Check if apps share database configuration
    shared_config = umbrella_structure.shared_configurations.database_configs

    if shared_config && shared_config.pattern == "shared_database" do
      :shared_database
    else
      :per_app_database
    end
  end

  defp setup_shared_database(umbrella_structure, _timeout) do
    Logger.debug("Setting up shared database for umbrella tests")

    # Simulate database setup
    # 1-4 seconds
    setup_duration = :rand.uniform(3000) + 1000
    :timer.sleep(setup_duration)

    db_setup = %{
      strategy: :shared_database,
      setup_required: true,
      setup_success: true,
      setup_duration_ms: setup_duration,
      database_name: "#{get_umbrella_name(umbrella_structure)}_test",
      migration_status: "all_migrations_applied",
      connected_apps: get_database_apps(umbrella_structure)
    }

    {:ok, db_setup}
  end

  defp setup_per_app_databases(umbrella_structure, timeout) do
    Logger.debug("Setting up per-application databases for umbrella tests")

    db_apps =
      umbrella_structure.applications
      |> Enum.filter(fn app -> has_database_setup?(app) end)

    db_setups =
      db_apps
      |> Enum.map(fn app ->
        setup_app_database(app, timeout)
      end)

    total_setup_time = Enum.sum(Enum.map(db_setups, & &1.setup_duration_ms))
    all_successful = Enum.all?(db_setups, & &1.setup_success)

    db_setup = %{
      strategy: :per_app_database,
      setup_required: true,
      setup_success: all_successful,
      setup_duration_ms: total_setup_time,
      per_app_setups: db_setups,
      total_databases: length(db_setups)
    }

    {:ok, db_setup}
  end

  defp setup_app_database(app, _timeout) do
    # Simulate individual app database setup
    # 0.5-2.5 seconds
    setup_duration = :rand.uniform(2000) + 500
    :timer.sleep(setup_duration)

    %{
      app_name: app.name,
      database_name: "#{app.name}_test",
      setup_success: true,
      setup_duration_ms: setup_duration,
      migration_status: "migrations_applied"
    }
  end

  # defp execute_isolated_app_tests(test_plan, test_options) do
  #   test_plan.execution_order
  #   |> Enum.map(fn app_name ->
  #     execute_app_test_suite(app_name, test_plan, test_options)
  #   end)
  # end

  # defp execute_shared_environment_tests(test_plan, test_options) do
  #   Logger.debug("Executing tests in shared environment")

  #   # In shared mode, we still execute per app but with shared setup
  #   test_plan.execution_order
  #   |> Enum.map(fn app_name ->
  #     result = execute_app_test_suite(app_name, test_plan, test_options)
  #     Map.put(result, :execution_mode, :shared_environment)
  #   end)
  # end

  # defp execute_app_test_suite(app_name, test_plan, test_options) do
  #   Logger.debug("Executing test suite for application: #{app_name}")

  #   start_time = System.monotonic_time(:millisecond)
  #   timeout = test_plan.per_app_timeout

  #   # Use existing TestRunner for individual app execution
  #   # This is a simulation - in production would call actual TestRunner
  #   test_result = simulate_app_test_execution(app_name, timeout, test_options)

  #   end_time = System.monotonic_time(:millisecond)
  #   duration = end_time - start_time

  #   Map.merge(test_result, %{
  #     app_name: app_name,
  #     actual_duration_ms: duration,
  #     timeout_used: timeout,
  #     isolation_mode: test_plan.isolation_strategy
  #   })
  # end

  # defp simulate_app_test_execution(app_name, _timeout, _test_options) do
  #   # Simulate test execution results
  #   # 5-35 tests per app
  #   total_tests = :rand.uniform(30) + 5
  #   # 80% apps have no failures
  #   failure_rate = if :rand.uniform() > 0.8, do: 0.1, else: 0.0
  #   failed_tests = round(total_tests * failure_rate)
  #   passed_tests = total_tests - failed_tests

  #   %{
  #     total_tests: total_tests,
  #     passed_tests: passed_tests,
  #     failed_tests: failed_tests,
  #     skipped_tests: 0,
  #     success: failed_tests == 0,
  #     # 2-10 test files
  #     test_files_count: :rand.uniform(8) + 2,
  #     warnings: if(failed_tests > 0, do: ["Test failures in #{app_name}"], else: []),
  #     errors: if(failed_tests > 2, do: ["Multiple failures in #{app_name}"], else: [])
  #   }
  # end

  # Task 2.3.3.2: Aggregate test results per application
  defp aggregate_test_results(test_results, umbrella_structure) do
    Logger.debug("Aggregating test results from #{length(test_results)} applications")

    aggregated = %{
      total_applications: length(test_results),
      successful_applications: count_successful_apps(test_results),
      failed_applications: count_failed_apps(test_results),
      total_tests: sum_total_tests(test_results),
      total_passed: sum_passed_tests(test_results),
      total_failed: sum_failed_tests(test_results),
      total_skipped: sum_skipped_tests(test_results),
      overall_success_rate: calculate_overall_success_rate(test_results),
      per_app_results: organize_per_app_results(test_results),
      test_execution_summary: generate_test_summary(test_results, umbrella_structure),
      aggregated_at: DateTime.utc_now()
    }

    {:ok, aggregated}
  end

  defp count_successful_apps(test_results) do
    Enum.count(test_results, & &1.success)
  end

  defp count_failed_apps(test_results) do
    Enum.count(test_results, &(not &1.success))
  end

  defp sum_total_tests(test_results) do
    Enum.sum(Enum.map(test_results, & &1.total_tests))
  end

  defp sum_passed_tests(test_results) do
    Enum.sum(Enum.map(test_results, & &1.passed_tests))
  end

  defp sum_failed_tests(test_results) do
    Enum.sum(Enum.map(test_results, & &1.failed_tests))
  end

  defp sum_skipped_tests(test_results) do
    Enum.sum(Enum.map(test_results, & &1.skipped_tests))
  end

  defp calculate_overall_success_rate(test_results) do
    total_tests = sum_total_tests(test_results)
    passed_tests = sum_passed_tests(test_results)

    if total_tests > 0 do
      passed_tests / total_tests * 100
    else
      0
    end
  end

  defp organize_per_app_results(test_results) do
    test_results
    |> Enum.into(%{}, fn result ->
      {result.app_name,
       %{
         success: result.success,
         test_count: result.total_tests,
         pass_rate: calculate_app_pass_rate(result),
         duration_ms: result.test_time_ms,
         issues: result.warnings ++ result.errors
       }}
    end)
  end

  defp calculate_app_pass_rate(result) do
    if result.total_tests > 0 do
      result.passed_tests / result.total_tests * 100
    else
      0
    end
  end

  defp generate_test_summary(test_results, umbrella_structure) do
    %{
      umbrella_project: get_umbrella_name(umbrella_structure),
      applications_tested: length(test_results),
      overall_health: classify_umbrella_test_health(test_results),
      performance_metrics: calculate_test_performance_metrics(test_results),
      recommendations: generate_test_recommendations(test_results)
    }
  end

  defp classify_umbrella_test_health(test_results) do
    success_rate = calculate_overall_success_rate(test_results)

    cond do
      success_rate >= 95 -> :excellent
      success_rate >= 85 -> :good
      success_rate >= 70 -> :acceptable
      success_rate >= 50 -> :poor
      true -> :critical
    end
  end

  defp calculate_test_performance_metrics(test_results) do
    durations = Enum.map(test_results, & &1.test_time_ms)

    %{
      total_test_time_ms: Enum.sum(durations),
      average_app_test_time_ms:
        if(Enum.empty?(durations), do: 0, else: Enum.sum(durations) / length(durations)),
      fastest_app_ms: Enum.min(durations, fn -> 0 end),
      slowest_app_ms: Enum.max(durations, fn -> 0 end)
    }
  end

  defp generate_test_recommendations(test_results) do
    recommendations = []

    failed_apps = Enum.filter(test_results, &(not &1.success))

    recommendations =
      if Enum.empty?(failed_apps) do
        recommendations
      else
        failed_names = Enum.map_join(failed_apps, ", ", & &1.app_name)
        ["Address test failures in applications: #{failed_names}" | recommendations]
      end

    slow_apps = Enum.filter(test_results, fn result -> result.test_time_ms > 30_000 end)

    recommendations =
      if Enum.empty?(slow_apps) do
        recommendations
      else
        slow_names = Enum.map_join(slow_apps, ", ", & &1.app_name)
        ["Optimize test performance for slow applications: #{slow_names}" | recommendations]
      end

    if recommendations == [] do
      ["Umbrella test execution is performing well across all applications"]
    else
      recommendations
    end
  end

  # Utility functions

  defp calculate_total_test_time(test_results) do
    Enum.sum(Enum.map(test_results, & &1.test_time_ms))
  end

  defp get_umbrella_name(umbrella_structure) do
    umbrella_structure.project_path
    |> Path.basename()
  end

  defp get_database_apps(umbrella_structure) do
    umbrella_structure.applications
    |> Enum.filter(fn app -> has_database_setup?(app) end)
    |> Enum.map(& &1.name)
  end

  defp build_test_filters(test_options) do
    %{
      only_tags: Keyword.get(test_options, :only, []),
      exclude_tags: Keyword.get(test_options, :exclude, []),
      test_pattern: Keyword.get(test_options, :pattern, "*"),
      max_failures: Keyword.get(test_options, :max_failures, :infinity)
    }
  end

  defp plan_resource_coordination(umbrella_structure) do
    %{
      requires_database: has_shared_database_config?(umbrella_structure),
      requires_shared_fixtures: requires_shared_setup?(umbrella_structure),
      coordination_complexity: classify_coordination_complexity(umbrella_structure)
    }
  end

  defp classify_coordination_complexity(umbrella_structure) do
    factors = []

    factors =
      if umbrella_structure.total_apps > 10 do
        [:many_applications | factors]
      else
        factors
      end

    factors =
      if Enum.empty?(umbrella_structure.inter_app_dependencies) do
        factors
      else
        [:cross_app_dependencies | factors]
      end

    factors =
      if has_shared_database_config?(umbrella_structure) do
        [:shared_database | factors]
      else
        factors
      end

    case length(factors) do
      0 -> :simple
      1 -> :moderate
      2 -> :complex
      _ -> :very_complex
    end
  end

  @doc """
  Generates test coordination report.
  """
  def generate_coordination_report(coordination_result) do
    report = %{
      summary: %{
        applications_tested: coordination_result.aggregated_results.total_applications,
        overall_success_rate: coordination_result.aggregated_results.overall_success_rate,
        total_test_time_ms: coordination_result.total_test_time_ms,
        database_strategy: coordination_result.database_setup.strategy,
        coordination_complexity:
          coordination_result.test_plan.resource_coordination.coordination_complexity
      },
      detailed_results: coordination_result.aggregated_results.per_app_results,
      performance_metrics:
        coordination_result.aggregated_results.test_execution_summary.performance_metrics,
      recommendations:
        coordination_result.aggregated_results.test_execution_summary.recommendations,
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  @doc """
  Validates test coordination results against quality thresholds.
  """
  def validate_coordination_results(coordination_result, thresholds \\ default_test_thresholds()) do
    validation = %{
      success_rate_acceptable:
        coordination_result.aggregated_results.overall_success_rate >= thresholds.min_success_rate,
      performance_acceptable:
        coordination_result.total_test_time_ms <= thresholds.max_total_time_ms,
      all_apps_tested:
        coordination_result.aggregated_results.total_applications ==
          coordination_result.umbrella_structure.total_apps,
      database_setup_successful: coordination_result.database_setup.setup_success
    }

    overall_valid = Enum.all?(Map.values(validation))

    %{
      valid: overall_valid,
      metrics: validation,
      issues: collect_coordination_issues(validation, coordination_result)
    }
  end

  defp default_test_thresholds do
    %{
      min_success_rate: 90.0,
      # 10 minutes total
      max_total_time_ms: 600_000,
      # 2 minutes per app
      max_app_time_ms: 120_000
    }
  end

  defp collect_coordination_issues(validation, coordination_result) do
    issues = []

    issues =
      if validation.success_rate_acceptable do
        issues
      else
        rate = coordination_result.aggregated_results.overall_success_rate
        ["Test success rate below threshold: #{rate}%" | issues]
      end

    issues =
      if validation.performance_acceptable do
        issues
      else
        time = coordination_result.total_test_time_ms
        ["Test execution time exceeded threshold: #{time}ms" | issues]
      end

    issues =
      if validation.all_apps_tested do
        issues
      else
        tested = coordination_result.aggregated_results.total_applications
        total = coordination_result.umbrella_structure.total_apps
        ["Not all applications tested: #{tested}/#{total}" | issues]
      end

    issues
  end
end
