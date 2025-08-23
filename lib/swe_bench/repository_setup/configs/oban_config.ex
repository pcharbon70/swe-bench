defmodule SweBench.RepositorySetup.Configs.ObanConfig do
  @moduledoc """
  Configuration module for Oban job processor repository integration.

  Handles PostgreSQL setup with Oban tables, job queue testing configuration,
  time-based test scenarios, task instance generation, and job retry
  mechanism testing for comprehensive Oban evaluation.
  """

  require Logger

  @oban_tables [
    "oban_jobs",
    "oban_peers",
    "oban_beats"
  ]

  @job_states [:available, :scheduled, :executing, :retryable, :completed, :discarded, :cancelled]

  @doc """
  Configures Oban job processor repository for evaluation.

  Handles all special requirements including PostgreSQL setup, job queue
  testing, time-based scenarios, and retry mechanism validation.
  """
  def configure_repository(repo_path, opts \\ []) do
    Logger.info("Configuring Oban job processor repository at #{repo_path}")

    with {:ok, postgresql_config} <- setup_postgresql_with_oban(repo_path, opts),
         {:ok, job_queue_config} <- configure_job_queue_testing(repo_path, opts),
         {:ok, time_scenario_config} <- handle_time_based_scenarios(repo_path, opts),
         {:ok, task_instances} <- generate_task_instances(repo_path, opts),
         {:ok, retry_validation} <- test_job_retry_mechanisms(repo_path, opts) do
      configuration = %{
        repository_type: :oban_job_processor,
        postgresql_configuration: postgresql_config,
        job_queue_configuration: job_queue_config,
        time_scenario_configuration: time_scenario_config,
        task_instances: task_instances,
        retry_mechanism_validation: retry_validation,
        total_tasks_extracted: length(task_instances),
        configured_at: DateTime.utc_now()
      }

      Logger.info("Oban configuration complete: #{length(task_instances)} tasks extracted")
      {:ok, configuration}
    else
      {:error, reason} ->
        Logger.warning("Oban configuration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.6.2.1: Set up PostgreSQL with Oban tables
  defp setup_postgresql_with_oban(repo_path, _opts) do
    Logger.debug("Setting up PostgreSQL with Oban tables")

    with {:ok, db_config} <- detect_database_configuration(repo_path),
         {:ok, oban_migration} <- analyze_oban_migration_setup(repo_path),
         {:ok, table_validation} <- validate_oban_table_structure(repo_path) do
      postgresql_config = %{
        database_configured: db_config.configured,
        database_type: db_config.type,
        oban_migration_present: oban_migration.migration_exists,
        oban_tables_configured: table_validation.tables_configured,
        migration_files: oban_migration.migration_files,
        table_structure_valid: table_validation.structure_valid,
        postgresql_score:
          calculate_postgresql_setup_score(db_config, oban_migration, table_validation)
      }

      {:ok, postgresql_config}
    end
  end

  defp detect_database_configuration(repo_path) do
    # Check for database configuration
    config_files = [
      "config/config.exs",
      "config/dev.exs",
      "config/test.exs"
    ]

    db_configured =
      config_files
      |> Enum.any?(fn config_file ->
        config_path = Path.join(repo_path, config_file)

        case File.read(config_path) do
          {:ok, content} ->
            String.contains?(content, "Ecto.Repo") or
              String.contains?(content, "database") or
              String.contains?(content, "postgres")

          {:error, _} ->
            false
        end
      end)

    db_type = if db_configured, do: :postgresql, else: :none

    {:ok, %{configured: db_configured, type: db_type}}
  end

  defp analyze_oban_migration_setup(repo_path) do
    # Look for Oban migration files
    migration_dir = Path.join(repo_path, "priv/repo/migrations")

    if File.dir?(migration_dir) do
      case File.ls(migration_dir) do
        {:ok, files} ->
          process_migration_files(files, migration_dir)

        {:error, reason} ->
          {:error, {:migration_dir_read_failed, reason}}
      end
    else
      {:ok, %{migration_exists: false, migration_files: [], migration_count: 0}}
    end
  end

  defp process_migration_files(files, migration_dir) do
    oban_migrations =
      files
      |> Enum.filter(&oban_migration_file?/1)
      |> Enum.map(&Path.join(migration_dir, &1))

    {:ok,
     %{
       migration_exists: oban_migrations != [],
       migration_files: oban_migrations,
       migration_count: length(oban_migrations)
     }}
  end

  defp oban_migration_file?(file) do
    String.contains?(file, "oban") or String.contains?(file, "job")
  end

  defp validate_oban_table_structure(repo_path) do
    # Analyze if Oban table structure is properly defined
    migration_files = find_oban_migration_files(repo_path)

    table_structure_analysis =
      migration_files
      |> Enum.map(&analyze_migration_file/1)

    tables_configured =
      @oban_tables
      |> Enum.all?(fn table ->
        Enum.any?(table_structure_analysis, fn analysis ->
          table in analysis.tables_created
        end)
      end)

    {:ok,
     %{
       tables_configured: tables_configured,
       structure_valid: tables_configured,
       analysis_details: table_structure_analysis
     }}
  end

  defp find_oban_migration_files(repo_path) do
    migration_patterns = [
      "priv/repo/migrations/*oban*.exs",
      "priv/repo/migrations/*job*.exs"
    ]

    migration_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
  end

  defp analyze_migration_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        tables_created =
          @oban_tables
          |> Enum.filter(fn table ->
            String.contains?(content, table) or
              String.contains?(content, "create table")
          end)

        %{
          file_path: file_path,
          tables_created: tables_created,
          has_oban_tables: not Enum.empty?(tables_created)
        }

      {:error, _} ->
        %{file_path: file_path, tables_created: [], has_oban_tables: false}
    end
  end

  defp calculate_postgresql_setup_score(db_config, oban_migration, table_validation) do
    base_score = 100

    # Penalty for missing database configuration
    db_penalty = if db_config.configured, do: 0, else: 40

    # Penalty for missing Oban migrations
    migration_penalty = if oban_migration.migration_exists, do: 0, else: 30

    # Penalty for improper table structure
    table_penalty = if table_validation.structure_valid, do: 0, else: 25

    final_score = base_score - db_penalty - migration_penalty - table_penalty
    max(0, final_score)
  end

  # Task 2.6.2.2: Configure job queue testing
  defp configure_job_queue_testing(repo_path, opts) do
    Logger.debug("Configuring job queue testing for Oban")

    with {:ok, job_modules} <- discover_job_modules(repo_path),
         {:ok, test_setup} <- analyze_job_testing_setup(repo_path),
         {:ok, queue_config} <- create_queue_testing_configuration(job_modules, opts) do
      job_queue_config = %{
        job_modules: job_modules,
        job_module_count: length(job_modules),
        test_setup: test_setup,
        queue_configuration: queue_config,
        testing_framework: detect_job_testing_framework(repo_path),
        queue_testing_score: calculate_queue_testing_score(job_modules, test_setup)
      }

      {:ok, job_queue_config}
    end
  end

  defp discover_job_modules(repo_path) do
    # Find Oban job modules
    job_patterns = [
      "lib/**/jobs/**/*.ex",
      "lib/**/*_job.ex",
      "lib/**/*_worker.ex"
    ]

    job_files =
      job_patterns
      |> Enum.flat_map(fn pattern ->
        Path.wildcard(Path.join(repo_path, pattern))
      end)

    job_modules =
      job_files
      |> Enum.map(fn file_path ->
        analyze_job_module(file_path, repo_path)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, job_modules}
  end

  defp analyze_job_module(file_path, repo_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "use Oban.Worker") or String.contains?(content, "Oban.Job") do
          %{
            file_path: Path.relative_to(file_path, repo_path),
            module_name: extract_module_name(content),
            job_type: classify_job_type(content),
            has_perform_function: String.contains?(content, "def perform"),
            retry_configuration: extract_retry_config(content)
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
  end

  defp classify_job_type(content) do
    cond do
      String.contains?(content, "email") -> :email_job
      String.contains?(content, "notification") -> :notification_job
      String.contains?(content, "import") -> :import_job
      String.contains?(content, "export") -> :export_job
      String.contains?(content, "cleanup") -> :cleanup_job
      true -> :generic_job
    end
  end

  defp extract_retry_config(content) do
    # Look for retry configuration patterns
    cond do
      String.contains?(content, "max_attempts") -> :configured_retries
      String.contains?(content, "retry") -> :basic_retries
      true -> :no_retry_config
    end
  end

  defp analyze_job_testing_setup(repo_path) do
    # Find job-related test files
    job_test_patterns = [
      "test/**/jobs/**/*_test.exs",
      "test/**/*_job_test.exs",
      "test/**/*_worker_test.exs"
    ]

    job_test_files =
      job_test_patterns
      |> Enum.flat_map(fn pattern ->
        Path.wildcard(Path.join(repo_path, pattern))
      end)

    test_analysis =
      job_test_files
      |> Enum.map(fn test_file ->
        analyze_job_test_file(test_file, repo_path)
      end)

    {:ok,
     %{
       test_files: test_analysis,
       test_file_count: length(test_analysis),
       has_job_tests: not Enum.empty?(test_analysis),
       test_coverage: classify_job_test_coverage(length(test_analysis))
     }}
  end

  defp analyze_job_test_file(test_file, repo_path) do
    case File.read(test_file) do
      {:ok, content} ->
        %{
          file_path: Path.relative_to(test_file, repo_path),
          test_type: classify_job_test_type(content),
          has_async_testing: String.contains?(content, "async"),
          has_queue_testing: String.contains?(content, "queue"),
          has_retry_testing: String.contains?(content, "retry")
        }

      {:error, _} ->
        %{file_path: Path.relative_to(test_file, repo_path), test_type: :unknown}
    end
  end

  defp classify_job_test_type(content) do
    cond do
      String.contains?(content, "perform") -> :job_execution_test
      String.contains?(content, "enqueue") -> :job_enqueue_test
      String.contains?(content, "retry") -> :job_retry_test
      String.contains?(content, "schedule") -> :job_schedule_test
      true -> :generic_job_test
    end
  end

  defp classify_job_test_coverage(test_count) do
    cond do
      test_count >= 10 -> :excellent
      test_count >= 5 -> :good
      test_count >= 2 -> :adequate
      test_count >= 1 -> :minimal
      true -> :none
    end
  end

  defp create_queue_testing_configuration(job_modules, opts) do
    queue_config = %{
      default_queue: Keyword.get(opts, :default_queue, "default"),
      test_queues: generate_test_queues(job_modules),
      concurrency_settings: %{
        test_concurrency: Keyword.get(opts, :test_concurrency, 1),
        max_concurrent_jobs: Keyword.get(opts, :max_concurrent, 10)
      },
      job_timeout: Keyword.get(opts, :job_timeout, 60_000),
      testing_mode: Keyword.get(opts, :testing_mode, :synchronous)
    }

    {:ok, queue_config}
  end

  defp generate_test_queues(job_modules) do
    job_modules
    |> Enum.map(& &1.job_type)
    |> Enum.uniq()
    |> Enum.map(fn job_type ->
      %{
        name: "test_#{job_type}",
        limit: 5,
        paused: false
      }
    end)
  end

  defp detect_job_testing_framework(repo_path) do
    test_helper_path = Path.join(repo_path, "test/test_helper.exs")

    case File.read(test_helper_path) do
      {:ok, content} ->
        cond do
          String.contains?(content, "Oban.Testing") -> :oban_testing
          String.contains?(content, "Ecto.Adapters.SQL.Sandbox") -> :ecto_sandbox
          true -> :exunit
        end

      {:error, _} ->
        :exunit
    end
  end

  defp calculate_queue_testing_score(job_modules, test_setup) do
    base_score = 100

    # Bonus for having job modules
    job_bonus = min(30, length(job_modules) * 5)

    # Bonus for comprehensive test setup
    test_bonus =
      case test_setup.test_coverage do
        :excellent -> 25
        :good -> 20
        :adequate -> 15
        :minimal -> 10
        :none -> 0
      end

    final_score = base_score + job_bonus + test_bonus
    min(100, final_score)
  end

  # Task 2.6.2.3: Handle time-based test scenarios
  defp handle_time_based_scenarios(repo_path, _opts) do
    Logger.debug("Handling time-based test scenarios for Oban")

    with {:ok, scheduled_jobs} <- find_scheduled_job_patterns(repo_path),
         {:ok, cron_jobs} <- find_cron_job_patterns(repo_path),
         {:ok, time_testing} <- analyze_time_based_testing(repo_path) do
      time_config = %{
        scheduled_jobs: scheduled_jobs,
        scheduled_job_count: length(scheduled_jobs),
        cron_jobs: cron_jobs,
        cron_job_count: length(cron_jobs),
        time_testing_setup: time_testing,
        time_scenario_support:
          assess_time_scenario_support(scheduled_jobs, cron_jobs, time_testing),
        time_testing_score: calculate_time_testing_score(scheduled_jobs, cron_jobs, time_testing)
      }

      {:ok, time_config}
    end
  end

  defp find_scheduled_job_patterns(repo_path) do
    job_files = find_all_job_files(repo_path)

    scheduled_jobs =
      job_files
      |> Enum.map(fn file_path ->
        analyze_scheduled_job_patterns(file_path, repo_path)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, scheduled_jobs}
  end

  defp find_cron_job_patterns(repo_path) do
    # Look for cron job configurations
    config_files = [
      "config/config.exs",
      "lib/**/application.ex"
    ]

    cron_jobs =
      config_files
      |> Enum.flat_map(fn pattern ->
        Path.wildcard(Path.join(repo_path, pattern))
      end)
      |> Enum.map(fn file_path ->
        analyze_cron_job_config(file_path, repo_path)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, cron_jobs}
  end

  defp find_all_job_files(repo_path) do
    job_patterns = [
      "lib/**/jobs/**/*.ex",
      "lib/**/*_job.ex"
    ]

    job_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
  end

  defp analyze_scheduled_job_patterns(file_path, repo_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "schedule_in") or String.contains?(content, "scheduled_at") do
          %{
            file_path: Path.relative_to(file_path, repo_path),
            scheduling_type: determine_scheduling_type(content),
            delay_patterns: extract_delay_patterns(content)
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp analyze_cron_job_config(file_path, repo_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "crontab") or String.contains?(content, "cron") do
          %{
            file_path: Path.relative_to(file_path, repo_path),
            cron_type: :periodic_job,
            cron_expressions: extract_cron_expressions(content)
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp determine_scheduling_type(content) do
    cond do
      String.contains?(content, "schedule_in") -> :relative_scheduling
      String.contains?(content, "scheduled_at") -> :absolute_scheduling
      String.contains?(content, "perform_at") -> :timestamp_scheduling
      true -> :immediate_scheduling
    end
  end

  defp extract_delay_patterns(content) do
    # Extract delay patterns from job scheduling
    patterns = []

    patterns =
      if String.contains?(content, "minutes") do
        [:minute_delays | patterns]
      else
        patterns
      end

    patterns =
      if String.contains?(content, "hours") do
        [:hour_delays | patterns]
      else
        patterns
      end

    patterns =
      if String.contains?(content, "days") do
        [:day_delays | patterns]
      else
        patterns
      end

    patterns
  end

  defp extract_cron_expressions(content) do
    # Simple cron expression extraction
    matches = Regex.scan(~r/"([0-9\*\-\/\s]+)"/, content)

    matches
    |> Enum.map(fn [_, expr] -> expr end)
    |> Enum.filter(fn expr ->
      String.contains?(expr, "*") or String.match?(expr, ~r/\d+/)
    end)
  end

  defp analyze_time_based_testing(repo_path) do
    # Look for time-based testing patterns
    test_files = find_oban_test_files(repo_path)

    time_testing_analysis =
      test_files
      |> Enum.map(fn test_file ->
        analyze_time_testing_in_file(test_file, repo_path)
      end)

    {:ok,
     %{
       test_files_analyzed: length(test_files),
       time_based_tests: time_testing_analysis,
       has_time_testing: Enum.any?(time_testing_analysis, & &1.has_time_testing)
     }}
  end

  defp find_oban_test_files(repo_path) do
    test_patterns = [
      "test/**/*oban*_test.exs",
      "test/**/*job*_test.exs"
    ]

    test_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
  end

  defp analyze_time_testing_in_file(test_file, repo_path) do
    case File.read(test_file) do
      {:ok, content} ->
        time_patterns = []

        time_patterns =
          if String.contains?(content, "DateTime") do
            [:datetime_testing | time_patterns]
          else
            time_patterns
          end

        time_patterns =
          if String.contains?(content, "schedule") do
            [:schedule_testing | time_patterns]
          else
            time_patterns
          end

        time_patterns =
          if String.contains?(content, "delay") do
            [:delay_testing | time_patterns]
          else
            time_patterns
          end

        %{
          file_path: Path.relative_to(test_file, repo_path),
          has_time_testing: not Enum.empty?(time_patterns),
          time_patterns: time_patterns
        }

      {:error, _} ->
        %{
          file_path: Path.relative_to(test_file, repo_path),
          has_time_testing: false,
          time_patterns: []
        }
    end
  end

  defp assess_time_scenario_support(scheduled_jobs, cron_jobs, time_testing) do
    support_level =
      case {length(scheduled_jobs), length(cron_jobs), time_testing.has_time_testing} do
        {s, c, true} when s > 0 or c > 0 -> :comprehensive
        {s, c, false} when s > 0 or c > 0 -> :basic
        {0, 0, true} -> :testing_only
        {0, 0, false} -> :none
      end

    %{
      support_level: support_level,
      scheduled_job_support: length(scheduled_jobs) > 0,
      cron_job_support: length(cron_jobs) > 0,
      time_testing_support: time_testing.has_time_testing
    }
  end

  defp calculate_time_testing_score(scheduled_jobs, cron_jobs, time_testing) do
    base_score = 100

    # Bonus for scheduled jobs
    scheduled_bonus = min(25, length(scheduled_jobs) * 8)

    # Bonus for cron jobs
    cron_bonus = min(20, length(cron_jobs) * 10)

    # Bonus for time-based testing
    testing_bonus = if time_testing.has_time_testing, do: 15, else: 0

    final_score = base_score + scheduled_bonus + cron_bonus + testing_bonus
    min(100, final_score)
  end

  # Task 2.6.2.4: Generate 15 task instances
  defp generate_task_instances(repo_path, opts) do
    Logger.debug("Generating task instances for Oban")

    target_tasks = Keyword.get(opts, :target_tasks, 15)

    with {:ok, job_implementation_tasks} <- extract_job_implementation_tasks(repo_path),
         {:ok, queue_management_tasks} <- extract_queue_management_tasks(repo_path),
         {:ok, retry_mechanism_tasks} <- extract_retry_mechanism_tasks(repo_path),
         {:ok, scheduling_tasks} <- extract_scheduling_tasks(repo_path) do
      all_tasks =
        job_implementation_tasks ++
          queue_management_tasks ++ retry_mechanism_tasks ++ scheduling_tasks

      # Select best quality tasks up to target
      selected_tasks = select_highest_quality_oban_tasks(all_tasks, target_tasks)

      {:ok, selected_tasks}
    end
  end

  defp extract_job_implementation_tasks(repo_path) do
    case discover_job_modules(repo_path) do
      {:ok, modules} ->
        tasks =
          modules
          |> Enum.take(8)
          |> Enum.map(fn job_module ->
            create_job_implementation_task(job_module, repo_path)
          end)

        {:ok, tasks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_queue_management_tasks(repo_path) do
    # Generate tasks related to queue management
    queue_tasks = [
      create_queue_management_task("queue_configuration", repo_path),
      create_queue_management_task("queue_monitoring", repo_path),
      create_queue_management_task("queue_prioritization", repo_path)
    ]

    {:ok, queue_tasks}
  end

  defp extract_retry_mechanism_tasks(repo_path) do
    # Generate tasks related to retry mechanisms
    retry_tasks = [
      create_retry_task("exponential_backoff", repo_path),
      create_retry_task("max_attempts_configuration", repo_path),
      create_retry_task("retry_condition_logic", repo_path)
    ]

    {:ok, retry_tasks}
  end

  defp extract_scheduling_tasks(repo_path) do
    # Generate tasks related to job scheduling
    scheduling_tasks = [
      create_scheduling_task("job_scheduling", repo_path),
      create_scheduling_task("cron_job_setup", repo_path)
    ]

    {:ok, scheduling_tasks}
  end

  defp create_job_implementation_task(job_module, _repo_path) do
    %{
      id: generate_task_id("job", job_module.file_path),
      type: :job_implementation,
      file_path: job_module.file_path,
      description: "Implement job functionality in #{job_module.module_name}",
      complexity: :medium,
      estimated_difficulty: 3,
      job_type: job_module.job_type,
      requires_database: true,
      requires_async_testing: true
    }
  end

  defp create_queue_management_task(task_type, _repo_path) do
    %{
      id: generate_task_id("queue", task_type),
      type: :queue_management,
      # Common location for queue config
      file_path: "lib/application.ex",
      description: "Configure Oban #{task_type} functionality",
      complexity: :medium,
      estimated_difficulty: 3,
      requires_database: true,
      requires_async_testing: false
    }
  end

  defp create_retry_task(task_type, _repo_path) do
    %{
      id: generate_task_id("retry", task_type),
      type: :retry_mechanism,
      file_path: "lib/jobs/",
      description: "Implement Oban #{task_type} functionality",
      complexity: :high,
      estimated_difficulty: 4,
      requires_database: true,
      requires_async_testing: true
    }
  end

  defp create_scheduling_task(task_type, _repo_path) do
    %{
      id: generate_task_id("sched", task_type),
      type: :job_scheduling,
      file_path: "lib/schedulers/",
      description: "Implement Oban #{task_type} functionality",
      complexity: :high,
      estimated_difficulty: 4,
      requires_database: true,
      requires_async_testing: true
    }
  end

  defp select_highest_quality_oban_tasks(all_tasks, target_count) do
    # Prioritize tasks based on complexity and educational value
    all_tasks
    |> Enum.sort_by(fn task ->
      complexity_score =
        case task.complexity do
          :very_high -> 5
          :high -> 4
          :medium -> 3
          :low -> 2
          _ -> 1
        end

      difficulty_score = task.estimated_difficulty

      # Higher scores first
      -(complexity_score + difficulty_score)
    end)
    |> Enum.take(target_count)
  end

  # Task 2.6.2.5: Test job retry mechanisms
  defp test_job_retry_mechanisms(repo_path, _opts) do
    Logger.debug("Testing job retry mechanisms")

    with {:ok, retry_configurations} <- analyze_retry_configurations(repo_path),
         {:ok, retry_tests} <- find_retry_mechanism_tests(repo_path),
         {:ok, backoff_strategies} <- analyze_backoff_strategies(repo_path) do
      retry_validation = %{
        retry_configurations: retry_configurations,
        retry_tests: retry_tests,
        backoff_strategies: backoff_strategies,
        retry_mechanism_completeness:
          assess_retry_completeness(retry_configurations, retry_tests, backoff_strategies),
        retry_testing_score:
          calculate_retry_testing_score(retry_configurations, retry_tests, backoff_strategies)
      }

      {:ok, retry_validation}
    end
  end

  defp analyze_retry_configurations(repo_path) do
    job_files = find_all_job_files(repo_path)

    retry_configs =
      job_files
      |> Enum.map(fn file_path ->
        extract_retry_configuration_from_file(file_path, repo_path)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, retry_configs}
  end

  defp extract_retry_configuration_from_file(file_path, repo_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "max_attempts") or String.contains?(content, "retry") do
          %{
            file_path: Path.relative_to(file_path, repo_path),
            max_attempts: extract_max_attempts(content),
            retry_strategy: extract_retry_strategy(content),
            has_custom_retry_logic: String.contains?(content, "retry_job")
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp extract_max_attempts(content) do
    case Regex.run(~r/max_attempts:\s*(\d+)/, content) do
      [_, attempts] -> String.to_integer(attempts)
      # Default Oban max attempts
      _ -> 3
    end
  end

  defp extract_retry_strategy(content) do
    cond do
      String.contains?(content, "exponential") -> :exponential_backoff
      String.contains?(content, "linear") -> :linear_backoff
      String.contains?(content, "constant") -> :constant_backoff
      true -> :default_strategy
    end
  end

  defp find_retry_mechanism_tests(repo_path) do
    test_files = find_oban_test_files(repo_path)

    retry_tests =
      test_files
      |> Enum.map(fn test_file ->
        analyze_retry_testing_in_file(test_file, repo_path)
      end)
      |> Enum.filter(& &1.has_retry_testing)

    {:ok, retry_tests}
  end

  defp analyze_retry_testing_in_file(test_file, repo_path) do
    case File.read(test_file) do
      {:ok, content} ->
        retry_patterns = []

        retry_patterns =
          if String.contains?(content, "retry") do
            [:retry_testing | retry_patterns]
          else
            retry_patterns
          end

        retry_patterns =
          if String.contains?(content, "attempt") do
            [:attempt_testing | retry_patterns]
          else
            retry_patterns
          end

        retry_patterns =
          if String.contains?(content, "backoff") do
            [:backoff_testing | retry_patterns]
          else
            retry_patterns
          end

        %{
          file_path: Path.relative_to(test_file, repo_path),
          has_retry_testing: not Enum.empty?(retry_patterns),
          retry_patterns: retry_patterns
        }

      {:error, _} ->
        %{
          file_path: Path.relative_to(test_file, repo_path),
          has_retry_testing: false,
          retry_patterns: []
        }
    end
  end

  defp analyze_backoff_strategies(repo_path) do
    # Analyze backoff strategy implementations
    job_files = find_all_job_files(repo_path)

    backoff_strategies =
      job_files
      |> Enum.map(fn file_path ->
        extract_backoff_strategy(file_path, repo_path)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, backoff_strategies}
  end

  defp extract_backoff_strategy(file_path, repo_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "backoff") do
          %{
            file_path: Path.relative_to(file_path, repo_path),
            strategy_type: extract_retry_strategy(content),
            has_custom_backoff:
              String.contains?(content, "def backoff") or
                String.contains?(content, "defp backoff")
          }
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp assess_retry_completeness(retry_configs, retry_tests, backoff_strategies) do
    completeness_factors = []

    completeness_factors =
      if Enum.empty?(retry_configs) do
        completeness_factors
      else
        [:retry_configuration | completeness_factors]
      end

    completeness_factors =
      if Enum.empty?(retry_tests) do
        completeness_factors
      else
        [:retry_testing | completeness_factors]
      end

    completeness_factors =
      if Enum.empty?(backoff_strategies) do
        completeness_factors
      else
        [:backoff_strategies | completeness_factors]
      end

    case length(completeness_factors) do
      3 -> :comprehensive
      2 -> :good
      1 -> :basic
      0 -> :none
    end
  end

  defp calculate_retry_testing_score(retry_configs, retry_tests, backoff_strategies) do
    base_score = 100

    # Bonus for retry configurations
    config_bonus = min(25, length(retry_configs) * 8)

    # Bonus for retry tests
    test_bonus = min(30, length(retry_tests) * 10)

    # Bonus for backoff strategies
    backoff_bonus = min(20, length(backoff_strategies) * 15)

    final_score = base_score + config_bonus + test_bonus + backoff_bonus
    min(100, final_score)
  end

  # Utility functions

  defp generate_task_id(prefix, identifier) do
    hash =
      :crypto.hash(:md5, to_string(identifier))
      |> Base.encode16()
      |> String.slice(0, 8)

    "#{prefix}_#{hash}"
  end
end
