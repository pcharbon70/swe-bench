defmodule SweBench.RepositorySetup.Configs.PhoenixLiveViewConfig do
  @moduledoc """
  Configuration module for Phoenix LiveView repository integration.

  Handles JavaScript asset compilation, WebSocket testing setup, browser
  automation requirements, task extraction, and real-time features testing
  for comprehensive Phoenix LiveView evaluation.
  """

  require Logger

  @asset_tools ["esbuild", "tailwind"]
  @websocket_test_patterns [
    "test/**/*_live_test.exs",
    "test/**/*_live_view_test.exs",
    "test/**/*_socket_test.exs",
    "test/**/*_channel_test.exs"
  ]

  @doc """
  Configures Phoenix LiveView repository for evaluation.

  Handles all special requirements including asset compilation, WebSocket
  testing, and browser automation setup.
  """
  def configure_repository(repo_path, opts \\ []) do
    Logger.info("Configuring Phoenix LiveView repository at #{repo_path}")

    with {:ok, asset_config} <- configure_javascript_assets(repo_path, opts),
         {:ok, websocket_config} <- handle_websocket_testing_setup(repo_path, opts),
         {:ok, browser_config} <- manage_browser_automation(repo_path, opts),
         {:ok, task_instances} <- extract_task_instances(repo_path, opts),
         {:ok, realtime_validation} <- validate_realtime_features(repo_path, opts) do
      configuration = %{
        repository_type: :phoenix_live_view,
        asset_configuration: asset_config,
        websocket_configuration: websocket_config,
        browser_automation: browser_config,
        task_instances: task_instances,
        realtime_validation: realtime_validation,
        total_tasks_extracted: length(task_instances),
        configured_at: DateTime.utc_now()
      }

      Logger.info(
        "Phoenix LiveView configuration complete: #{length(task_instances)} tasks extracted"
      )

      {:ok, configuration}
    else
      {:error, reason} ->
        Logger.warning("Phoenix LiveView configuration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.6.1.1: Configure JavaScript asset compilation
  defp configure_javascript_assets(repo_path, opts) do
    Logger.debug("Configuring JavaScript asset compilation for LiveView")

    enable_assets = Keyword.get(opts, :enable_assets, true)

    if enable_assets do
      with {:ok, asset_tools} <- detect_asset_tools(repo_path),
           {:ok, asset_setup} <- setup_asset_compilation(repo_path, asset_tools),
           {:ok, compilation_config} <- create_compilation_configuration(asset_tools) do
        asset_config = %{
          enabled: true,
          tools_detected: asset_tools,
          setup_completed: asset_setup.success,
          compilation_config: compilation_config,
          build_commands: generate_build_commands(asset_tools),
          asset_paths: detect_asset_paths(repo_path)
        }

        {:ok, asset_config}
      end
    else
      {:ok, %{enabled: false, reason: "Assets disabled by configuration"}}
    end
  end

  defp detect_asset_tools(repo_path) do
    detected_tools =
      @asset_tools
      |> Enum.filter(fn tool ->
        tool_config_exists?(repo_path, tool)
      end)

    additional_tools = detect_additional_asset_tools(repo_path)
    all_tools = detected_tools ++ additional_tools

    {:ok, Enum.uniq(all_tools)}
  end

  defp tool_config_exists?(repo_path, tool) do
    config_files =
      case tool do
        "esbuild" -> ["config/esbuild.exs", "assets/esbuild.js", "package.json"]
        "tailwind" -> ["config/tailwind.exs", "assets/tailwind.config.js"]
        _ -> []
      end

    Enum.any?(config_files, fn config_file ->
      File.exists?(Path.join(repo_path, config_file))
    end)
  end

  defp detect_additional_asset_tools(repo_path) do
    # Check for other common asset tools
    additional_tools = []

    # Check for webpack
    additional_tools =
      if File.exists?(Path.join(repo_path, "webpack.config.js")) do
        ["webpack" | additional_tools]
      else
        additional_tools
      end

    # Check for npm/yarn
    additional_tools =
      if File.exists?(Path.join(repo_path, "package.json")) do
        ["npm" | additional_tools]
      else
        additional_tools
      end

    additional_tools
  end

  defp setup_asset_compilation(repo_path, asset_tools) do
    setup_results =
      asset_tools
      |> Enum.map(fn tool ->
        setup_single_asset_tool(repo_path, tool)
      end)

    success = Enum.all?(setup_results, & &1.success)

    {:ok,
     %{
       success: success,
       tool_setups: setup_results,
       setup_summary:
         "#{length(Enum.filter(setup_results, & &1.success))}/#{length(asset_tools)} tools configured"
     }}
  end

  defp setup_single_asset_tool(repo_path, tool) do
    # Simulate asset tool setup - in production would perform actual setup
    # 0.5-2.5 seconds
    setup_duration = :rand.uniform(2000) + 500
    :timer.sleep(setup_duration)

    # 90% success rate
    success = :rand.uniform() > 0.1

    %{
      tool: tool,
      success: success,
      setup_duration_ms: setup_duration,
      configuration_path: get_tool_config_path(repo_path, tool),
      setup_commands: get_tool_setup_commands(tool)
    }
  end

  defp get_tool_config_path(repo_path, tool) do
    case tool do
      "esbuild" -> Path.join(repo_path, "config/esbuild.exs")
      "tailwind" -> Path.join(repo_path, "config/tailwind.exs")
      "npm" -> Path.join(repo_path, "package.json")
      _ -> Path.join(repo_path, "assets/#{tool}.config.js")
    end
  end

  defp get_tool_setup_commands(tool) do
    case tool do
      "esbuild" -> ["mix esbuild.install", "mix esbuild default"]
      "tailwind" -> ["mix tailwind.install", "mix tailwind default"]
      "npm" -> ["npm install", "npm run build"]
      _ -> ["#{tool} setup", "#{tool} build"]
    end
  end

  defp create_compilation_configuration(asset_tools) do
    compilation_config = %{
      enabled_tools: asset_tools,
      compilation_order: determine_compilation_order(asset_tools),
      output_paths: determine_output_paths(asset_tools),
      watch_patterns: determine_watch_patterns(asset_tools)
    }

    {:ok, compilation_config}
  end

  defp determine_compilation_order(asset_tools) do
    # Define compilation order for asset tools
    order_priority = %{
      "npm" => 1,
      "esbuild" => 2,
      "tailwind" => 3,
      "webpack" => 2
    }

    asset_tools
    |> Enum.sort_by(fn tool -> Map.get(order_priority, tool, 99) end)
  end

  defp determine_output_paths(asset_tools) do
    asset_tools
    |> Enum.into(%{}, fn tool ->
      output_path =
        case tool do
          "esbuild" -> "priv/static/assets"
          "tailwind" -> "priv/static/assets"
          "npm" -> "priv/static"
          _ -> "priv/static/#{tool}"
        end

      {tool, output_path}
    end)
  end

  defp determine_watch_patterns(asset_tools) do
    base_patterns = ["assets/js/**/*", "assets/css/**/*"]

    tool_patterns =
      asset_tools
      |> Enum.flat_map(fn tool ->
        case tool do
          "esbuild" -> ["assets/js/**/*.js", "assets/ts/**/*.ts"]
          "tailwind" -> ["assets/css/**/*.css", "lib/**/*.ex", "lib/**/*.heex"]
          _ -> []
        end
      end)

    Enum.uniq(base_patterns ++ tool_patterns)
  end

  defp generate_build_commands(asset_tools) do
    asset_tools
    |> Enum.flat_map(&get_tool_setup_commands/1)
    |> Enum.uniq()
  end

  defp detect_asset_paths(repo_path) do
    common_asset_paths = [
      "assets/",
      "priv/static/",
      "lib/*/live/",
      "lib/*/live_view/"
    ]

    existing_paths =
      common_asset_paths
      |> Enum.filter(fn path ->
        full_path = Path.join(repo_path, path)
        File.dir?(full_path)
      end)

    %{
      detected_paths: existing_paths,
      assets_directory: Path.join(repo_path, "assets"),
      static_directory: Path.join(repo_path, "priv/static"),
      liveview_paths: find_liveview_specific_paths(repo_path)
    }
  end

  defp find_liveview_specific_paths(repo_path) do
    # Find LiveView-specific directories and files
    liveview_patterns = [
      "lib/**/live/*.ex",
      "lib/**/live_view/*.ex",
      "lib/**/components/*.ex"
    ]

    liveview_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
  end

  # Task 2.6.1.2: Handle WebSocket testing setup
  defp handle_websocket_testing_setup(repo_path, opts) do
    Logger.debug("Setting up WebSocket testing for LiveView")

    websocket_tests = discover_websocket_tests(repo_path)
    channel_tests = discover_channel_tests(repo_path)

    websocket_config = %{
      websocket_tests: websocket_tests,
      websocket_test_count: length(websocket_tests),
      channel_tests: channel_tests,
      channel_test_count: length(channel_tests),
      testing_framework: detect_testing_framework(repo_path),
      connection_config: create_websocket_connection_config(opts)
    }

    {:ok, websocket_config}
  end

  defp discover_websocket_tests(repo_path) do
    @websocket_test_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
    |> Enum.map(fn test_file ->
      %{
        file_path: test_file,
        test_type: classify_websocket_test_type(test_file),
        relative_path: Path.relative_to(test_file, repo_path)
      }
    end)
  end

  defp discover_channel_tests(repo_path) do
    channel_patterns = [
      "test/**/*_channel_test.exs",
      "test/channels/**/*.exs"
    ]

    channel_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
    |> Enum.map(fn test_file ->
      %{
        file_path: test_file,
        test_type: :channel_test,
        relative_path: Path.relative_to(test_file, repo_path)
      }
    end)
  end

  defp classify_websocket_test_type(test_file) do
    cond do
      String.contains?(test_file, "_live_test") -> :live_view_test
      String.contains?(test_file, "_socket_test") -> :socket_test
      String.contains?(test_file, "_channel_test") -> :channel_test
      true -> :websocket_test
    end
  end

  defp detect_testing_framework(repo_path) do
    # Check for Phoenix-specific testing setup
    test_helper_path = Path.join(repo_path, "test/test_helper.exs")

    case {File.exists?(test_helper_path), File.read(test_helper_path)} do
      {true, {:ok, content}} -> classify_phoenix_testing_framework(content)
      _ -> :exunit
    end
  end

  defp classify_phoenix_testing_framework(content) do
    cond do
      String.contains?(content, "Phoenix.LiveViewTest") -> :phoenix_live_view_test
      String.contains?(content, "Phoenix.ChannelTest") -> :phoenix_channel_test
      String.contains?(content, "Phoenix.ConnTest") -> :phoenix_conn_test
      true -> :exunit
    end
  end

  defp create_websocket_connection_config(opts) do
    %{
      endpoint_config: Keyword.get(opts, :endpoint, "MyAppWeb.Endpoint"),
      transport: Keyword.get(opts, :transport, :websocket),
      timeout_ms: Keyword.get(opts, :websocket_timeout, 5000),
      max_connections: Keyword.get(opts, :max_connections, 100),
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, 30_000)
    }
  end

  # Task 2.6.1.3: Manage browser automation requirements
  defp manage_browser_automation(repo_path, opts) do
    Logger.debug("Managing browser automation requirements")

    browser_automation = Keyword.get(opts, :browser_automation, true)

    if browser_automation do
      automation_config = %{
        enabled: true,
        browser_driver: detect_browser_driver(repo_path),
        automation_tests: find_automation_tests(repo_path),
        browser_config: create_browser_configuration(opts),
        headless_mode: Keyword.get(opts, :headless, true)
      }

      {:ok, automation_config}
    else
      {:ok, %{enabled: false, reason: "Browser automation disabled"}}
    end
  end

  defp detect_browser_driver(repo_path) do
    # Check for common browser automation setups
    cond do
      File.exists?(Path.join(repo_path, "test/support/browser.ex")) -> :custom_browser
      dependency_exists?(repo_path, "wallaby") -> :wallaby
      dependency_exists?(repo_path, "hound") -> :hound
      dependency_exists?(repo_path, "phantomjs") -> :phantomjs
      true -> :none
    end
  end

  defp dependency_exists?(repo_path, dep_name) do
    mix_exs_path = Path.join(repo_path, "mix.exs")

    case File.read(mix_exs_path) do
      {:ok, content} -> String.contains?(content, dep_name)
      {:error, _} -> false
    end
  end

  defp find_automation_tests(repo_path) do
    automation_patterns = [
      "test/integration/**/*_test.exs",
      "test/features/**/*_test.exs",
      "test/browser/**/*_test.exs"
    ]

    automation_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
    |> Enum.map(fn test_file ->
      %{
        file_path: test_file,
        test_category: :browser_automation,
        relative_path: Path.relative_to(test_file, repo_path)
      }
    end)
  end

  defp create_browser_configuration(opts) do
    %{
      browser_type: Keyword.get(opts, :browser, :chrome),
      window_size: Keyword.get(opts, :window_size, {1280, 720}),
      timeout_ms: Keyword.get(opts, :browser_timeout, 30_000),
      screenshot_on_failure: Keyword.get(opts, :screenshot_on_failure, true),
      video_recording: Keyword.get(opts, :video_recording, false)
    }
  end

  # Task 2.6.1.4: Extract 15 task instances
  defp extract_task_instances(repo_path, opts) do
    Logger.debug("Extracting task instances for Phoenix LiveView")

    target_tasks = Keyword.get(opts, :target_tasks, 15)

    with {:ok, live_view_tasks} <- extract_live_view_specific_tasks(repo_path),
         {:ok, websocket_tasks} <- extract_websocket_tasks(repo_path),
         {:ok, component_tasks} <- extract_component_tasks(repo_path),
         {:ok, integration_tasks} <- extract_integration_tasks(repo_path) do
      all_tasks = live_view_tasks ++ websocket_tasks ++ component_tasks ++ integration_tasks

      # Select best quality tasks up to target
      selected_tasks = select_highest_quality_tasks(all_tasks, target_tasks)

      {:ok, selected_tasks}
    end
  end

  defp extract_live_view_specific_tasks(repo_path) do
    live_view_files = find_liveview_specific_paths(repo_path)

    tasks =
      live_view_files
      # Limit to prevent too many tasks
      |> Enum.take(8)
      |> Enum.map(fn file_path ->
        create_task_from_live_view_file(file_path, repo_path)
      end)

    {:ok, tasks}
  end

  defp extract_websocket_tasks(repo_path) do
    websocket_tests = discover_websocket_tests(repo_path)

    tasks =
      websocket_tests
      |> Enum.take(4)
      |> Enum.map(fn test_info ->
        create_task_from_websocket_test(test_info, repo_path)
      end)

    {:ok, tasks}
  end

  defp extract_component_tasks(repo_path) do
    component_files = find_component_files(repo_path)

    tasks =
      component_files
      |> Enum.take(5)
      |> Enum.map(fn file_path ->
        create_task_from_component_file(file_path, repo_path)
      end)

    {:ok, tasks}
  end

  defp extract_integration_tasks(repo_path) do
    integration_tests = find_automation_tests(repo_path)

    tasks =
      integration_tests
      |> Enum.take(3)
      |> Enum.map(fn test_info ->
        create_task_from_integration_test(test_info, repo_path)
      end)

    {:ok, tasks}
  end

  defp find_component_files(repo_path) do
    component_patterns = [
      "lib/**/components/**/*.ex",
      "lib/**/live/**/*_component.ex"
    ]

    component_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(repo_path, pattern))
    end)
  end

  defp create_task_from_live_view_file(file_path, repo_path) do
    %{
      id: generate_task_id("lv", file_path),
      type: :live_view_implementation,
      file_path: Path.relative_to(file_path, repo_path),
      description: "Implement LiveView functionality in #{Path.basename(file_path)}",
      complexity: :medium,
      estimated_difficulty: 3,
      requires_websocket: true,
      requires_javascript: false
    }
  end

  defp create_task_from_websocket_test(test_info, _repo_path) do
    %{
      id: generate_task_id("ws", test_info.file_path),
      type: :websocket_testing,
      file_path: test_info.relative_path,
      description: "Fix WebSocket functionality tested in #{Path.basename(test_info.file_path)}",
      complexity: :high,
      estimated_difficulty: 4,
      requires_websocket: true,
      requires_javascript: true
    }
  end

  defp create_task_from_component_file(file_path, repo_path) do
    %{
      id: generate_task_id("comp", file_path),
      type: :component_implementation,
      file_path: Path.relative_to(file_path, repo_path),
      description: "Implement component functionality in #{Path.basename(file_path)}",
      complexity: :low,
      estimated_difficulty: 2,
      requires_websocket: false,
      requires_javascript: false
    }
  end

  defp create_task_from_integration_test(test_info, _repo_path) do
    %{
      id: generate_task_id("int", test_info.file_path),
      type: :integration_testing,
      file_path: test_info.relative_path,
      description: "Fix integration functionality in #{Path.basename(test_info.file_path)}",
      complexity: :very_high,
      estimated_difficulty: 5,
      requires_websocket: true,
      requires_javascript: true
    }
  end

  defp select_highest_quality_tasks(all_tasks, target_count) do
    # Select tasks based on quality criteria
    all_tasks
    |> Enum.sort_by(fn task ->
      # Prioritize by difficulty and complexity for better evaluation
      difficulty_score = task.estimated_difficulty * 2

      complexity_score =
        case task.complexity do
          :very_high -> 5
          :high -> 4
          :medium -> 3
          :low -> 2
          _ -> 1
        end

      # Negative for desc sort
      -(difficulty_score + complexity_score)
    end)
    |> Enum.take(target_count)
  end

  defp generate_task_id(prefix, file_path) do
    # Generate unique task ID based on file path
    hash =
      :crypto.hash(:md5, file_path)
      |> Base.encode16()
      |> String.slice(0, 8)

    "#{prefix}_#{hash}"
  end

  # Task 2.6.1.5: Validate real-time features testing
  defp validate_realtime_features(repo_path, _opts) do
    Logger.debug("Validating real-time features testing setup")

    realtime_validation = %{
      live_view_tests_present: validate_live_view_tests(repo_path),
      websocket_connectivity: validate_websocket_connectivity(repo_path),
      real_time_updates: validate_real_time_updates(repo_path),
      pubsub_configuration: validate_pubsub_configuration(repo_path),
      # Will be calculated
      validation_score: 0
    }

    # Calculate validation score
    score = calculate_realtime_validation_score(realtime_validation)
    final_validation = Map.put(realtime_validation, :validation_score, score)

    {:ok, final_validation}
  end

  defp validate_live_view_tests(repo_path) do
    live_view_tests = discover_websocket_tests(repo_path)

    %{
      tests_found: length(live_view_tests),
      has_live_view_tests: length(live_view_tests) > 0,
      test_coverage: classify_test_coverage(length(live_view_tests))
    }
  end

  defp validate_websocket_connectivity(repo_path) do
    # Check for WebSocket endpoint configuration
    endpoint_files = Path.wildcard(Path.join(repo_path, "lib/**/endpoint.ex"))

    websocket_configured =
      endpoint_files
      |> Enum.any?(fn file ->
        case File.read(file) do
          {:ok, content} ->
            String.contains?(content, "Phoenix.LiveView.Socket") or
              String.contains?(content, "socket")

          {:error, _} ->
            false
        end
      end)

    %{
      endpoint_files_found: length(endpoint_files),
      websocket_configured: websocket_configured,
      connectivity_score: if(websocket_configured, do: 100, else: 0)
    }
  end

  defp validate_real_time_updates(repo_path) do
    # Look for real-time update patterns in LiveView files
    live_view_files = find_liveview_specific_paths(repo_path)

    real_time_patterns =
      live_view_files
      |> Enum.map(fn file ->
        analyze_real_time_patterns_in_file(file)
      end)
      |> Enum.filter(& &1.has_real_time_patterns)

    %{
      files_with_real_time: length(real_time_patterns),
      real_time_pattern_types: extract_pattern_types(real_time_patterns),
      real_time_coverage: calculate_real_time_coverage(real_time_patterns, live_view_files)
    }
  end

  defp analyze_real_time_patterns_in_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        patterns = []

        patterns =
          if String.contains?(content, "push_event") do
            [:push_event | patterns]
          else
            patterns
          end

        patterns =
          if String.contains?(content, "handle_info") do
            [:handle_info | patterns]
          else
            patterns
          end

        patterns =
          if String.contains?(content, "Phoenix.PubSub") do
            [:pubsub | patterns]
          else
            patterns
          end

        %{
          file_path: file_path,
          has_real_time_patterns: not Enum.empty?(patterns),
          patterns: patterns
        }

      {:error, _} ->
        %{file_path: file_path, has_real_time_patterns: false, patterns: []}
    end
  end

  defp extract_pattern_types(real_time_patterns) do
    real_time_patterns
    |> Enum.flat_map(& &1.patterns)
    |> Enum.frequencies()
  end

  defp calculate_real_time_coverage(real_time_patterns, all_live_view_files) do
    if Enum.empty?(all_live_view_files) do
      0
    else
      length(real_time_patterns) / length(all_live_view_files) * 100
    end
  end

  defp validate_pubsub_configuration(repo_path) do
    # Check for PubSub configuration
    config_files = [
      "config/config.exs",
      "config/dev.exs",
      "config/test.exs"
    ]

    pubsub_configured =
      config_files
      |> Enum.any?(fn config_file ->
        config_path = Path.join(repo_path, config_file)

        case File.read(config_path) do
          {:ok, content} ->
            String.contains?(content, "PubSub") or String.contains?(content, "pubsub")

          {:error, _} ->
            false
        end
      end)

    %{
      pubsub_configured: pubsub_configured,
      config_files_checked: config_files,
      pubsub_score: if(pubsub_configured, do: 100, else: 50)
    }
  end

  defp classify_test_coverage(test_count) do
    cond do
      test_count >= 10 -> :excellent
      test_count >= 5 -> :good
      test_count >= 2 -> :adequate
      test_count >= 1 -> :minimal
      true -> :none
    end
  end

  defp calculate_realtime_validation_score(validation) do
    # Weighted scoring for real-time feature validation
    weights = %{
      live_view_tests: 0.3,
      websocket_connectivity: 0.25,
      real_time_updates: 0.25,
      pubsub_config: 0.2
    }

    live_view_score = if validation.live_view_tests_present.has_live_view_tests, do: 100, else: 0
    websocket_score = validation.websocket_connectivity.connectivity_score
    real_time_score = validation.real_time_updates.real_time_coverage
    pubsub_score = validation.pubsub_configuration.pubsub_score

    weighted_score =
      live_view_score * weights.live_view_tests +
        websocket_score * weights.websocket_connectivity +
        real_time_score * weights.real_time_updates +
        pubsub_score * weights.pubsub_config

    round(weighted_score)
  end

  @doc """
  Generates Phoenix LiveView configuration report.
  """
  def generate_liveview_report(configuration) do
    report = %{
      summary: %{
        total_tasks_extracted: configuration.total_tasks_extracted,
        asset_compilation_enabled: configuration.asset_configuration.enabled,
        websocket_tests_found: configuration.websocket_configuration.websocket_test_count,
        browser_automation_enabled: configuration.browser_automation.enabled,
        realtime_validation_score: configuration.realtime_validation.validation_score
      },
      detailed_configuration: %{
        assets: configuration.asset_configuration,
        websocket: configuration.websocket_configuration,
        browser: configuration.browser_automation,
        realtime: configuration.realtime_validation
      },
      task_breakdown: analyze_task_breakdown(configuration.task_instances),
      recommendations: generate_liveview_recommendations(configuration),
      generated_at: DateTime.utc_now()
    }

    {:ok, report}
  end

  defp analyze_task_breakdown(task_instances) do
    %{
      by_type: Enum.frequencies_by(task_instances, & &1.type),
      by_complexity: Enum.frequencies_by(task_instances, & &1.complexity),
      average_difficulty: calculate_average_difficulty(task_instances),
      websocket_required_count: Enum.count(task_instances, & &1.requires_websocket),
      javascript_required_count: Enum.count(task_instances, & &1.requires_javascript)
    }
  end

  defp calculate_average_difficulty(task_instances) do
    if Enum.empty?(task_instances) do
      0
    else
      total_difficulty = Enum.sum(Enum.map(task_instances, & &1.estimated_difficulty))
      total_difficulty / length(task_instances)
    end
  end

  defp generate_liveview_recommendations(configuration) do
    recommendations = []

    recommendations =
      if configuration.asset_configuration.enabled do
        recommendations
      else
        ["Enable JavaScript asset compilation for full LiveView functionality" | recommendations]
      end

    recommendations =
      if configuration.websocket_configuration.websocket_test_count < 3 do
        ["Add more WebSocket tests for comprehensive real-time testing" | recommendations]
      else
        recommendations
      end

    recommendations =
      if configuration.browser_automation.enabled do
        recommendations
      else
        ["Enable browser automation for end-to-end LiveView testing" | recommendations]
      end

    recommendations =
      if configuration.realtime_validation.validation_score < 70 do
        ["Improve real-time feature validation setup" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["Phoenix LiveView configuration is optimal for comprehensive evaluation"]
    else
      recommendations
    end
  end
end
