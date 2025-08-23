defmodule SweBench.MixProject.UmbrellaDetector do
  @moduledoc """
  Enhanced umbrella project structure detection and analysis.

  Provides comprehensive analysis of umbrella project structures, including
  inter-application dependencies, shared configurations, release setups,
  and compilation ordering requirements.
  """

  require Logger

  alias SweBench.MixProject.ProjectAnalyzer

  @apps_directory "apps"
  @default_umbrella_config_files [
    "config/config.exs",
    "config/runtime.exs",
    "config/dev.exs",
    "config/test.exs",
    "config/prod.exs"
  ]

  @doc """
  Performs comprehensive umbrella project detection and analysis.

  Returns detailed umbrella structure information including applications,
  dependencies, configurations, and compilation requirements.
  """
  def detect_umbrella_structure(project_path, opts \\ []) do
    Logger.info("Detecting umbrella project structure at #{project_path}")

    with {:ok, is_umbrella} <- umbrella_project?(project_path),
         {:ok, structure_info} <- analyze_umbrella_structure(project_path, is_umbrella, opts) do
      Logger.info(
        "Umbrella detection complete: #{if is_umbrella, do: "umbrella", else: "standard"} project"
      )

      {:ok, structure_info}
    else
      {:error, reason} ->
        Logger.warning("Umbrella detection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Task 2.3.1.1: Identify apps directory and structure
  @doc """
  Determines if a project is an umbrella project.
  """
  def umbrella_project?(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")
    apps_path = Path.join(project_path, @apps_directory)

    with {:ok, mix_content} <- File.read(mix_exs_path),
         {:ok, has_umbrella_config} <- check_umbrella_configuration(mix_content),
         {:ok, has_apps_directory} <- check_apps_directory(apps_path) do
      is_umbrella = has_umbrella_config or has_apps_directory
      {:ok, is_umbrella}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_umbrella_configuration(mix_content) do
    # Check for umbrella: true in mix.exs
    has_umbrella_flag = String.contains?(mix_content, "umbrella: true")

    # Check for apps_path configuration
    has_apps_path = String.contains?(mix_content, "apps_path:")

    {:ok, has_umbrella_flag or has_apps_path}
  end

  defp check_apps_directory(apps_path) do
    case File.dir?(apps_path) do
      true -> verify_apps_contain_mix_files(apps_path)
      false -> {:ok, false}
    end
  end

  defp verify_apps_contain_mix_files(apps_path) do
    case File.ls(apps_path) do
      {:ok, entries} ->
        has_valid_apps = Enum.any?(entries, &valid_mix_app?(&1, apps_path))
        {:ok, has_valid_apps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_mix_app?(entry, apps_path) do
    app_path = Path.join(apps_path, entry)
    mix_file = Path.join(app_path, "mix.exs")
    File.exists?(mix_file)
  end

  defp analyze_umbrella_structure(project_path, is_umbrella, opts) do
    if is_umbrella do
      analyze_umbrella_details(project_path, opts)
    else
      analyze_standard_project(project_path, opts)
    end
  end

  defp analyze_umbrella_details(project_path, opts) do
    with {:ok, apps_info} <- discover_applications(project_path),
         {:ok, root_config} <- parse_root_configuration(project_path),
         {:ok, dependencies} <- map_inter_app_dependencies(apps_info),
         {:ok, shared_config} <- detect_shared_configurations(project_path, apps_info),
         {:ok, release_configs} <- identify_release_configurations(project_path) do
      umbrella_structure = %{
        project_type: :umbrella,
        project_path: project_path,
        apps_directory: Path.join(project_path, @apps_directory),
        applications: apps_info,
        root_configuration: root_config,
        inter_app_dependencies: dependencies,
        shared_configurations: shared_config,
        release_configurations: release_configs,
        compilation_order: calculate_compilation_order(dependencies),
        total_apps: length(apps_info),
        analysis_options: opts,
        analyzed_at: DateTime.utc_now()
      }

      {:ok, umbrella_structure}
    end
  end

  defp analyze_standard_project(project_path, opts) do
    # Use existing ProjectAnalyzer for standard projects with umbrella-compatible format
    case ProjectAnalyzer.analyze_project(project_path, opts) do
      {:ok, analysis} ->
        standard_structure = %{
          project_type: :standard,
          project_path: project_path,
          apps_directory: nil,
          applications: [convert_to_app_info(analysis)],
          root_configuration: analysis.configuration,
          inter_app_dependencies: %{},
          shared_configurations: %{},
          release_configurations: [],
          compilation_order: [get_app_name(project_path)],
          total_apps: 1,
          analysis_options: opts,
          analyzed_at: DateTime.utc_now()
        }

        {:ok, standard_structure}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Task 2.3.1.2: Parse root and app-level mix.exs files
  defp discover_applications(project_path) do
    apps_path = Path.join(project_path, @apps_directory)

    case File.ls(apps_path) do
      {:ok, app_dirs} ->
        apps_info =
          app_dirs
          |> Enum.map(fn app_dir ->
            app_path = Path.join(apps_path, app_dir)
            analyze_application(app_path, app_dir)
          end)
          |> Enum.filter(fn
            {:ok, _} -> true
            {:error, _} -> false
          end)
          |> Enum.map(fn {:ok, app_info} -> app_info end)

        {:ok, apps_info}

      {:error, reason} ->
        {:error, {:apps_discovery_failed, reason}}
    end
  end

  defp analyze_application(app_path, app_name) do
    mix_exs_path = Path.join(app_path, "mix.exs")

    with {:ok, mix_content} <- File.read(mix_exs_path),
         {:ok, app_config} <- parse_app_mix_exs(mix_content, app_name),
         {:ok, test_files} <- find_app_test_files(app_path),
         {:ok, lib_files} <- find_app_lib_files(app_path) do
      app_info = %{
        name: app_name,
        path: app_path,
        mix_exs_path: mix_exs_path,
        configuration: app_config,
        test_files: test_files,
        lib_files: lib_files,
        dependencies: extract_app_dependencies(app_config),
        test_config: extract_test_configuration(app_path)
      }

      {:ok, app_info}
    else
      {:error, reason} -> {:error, {:app_analysis_failed, app_name, reason}}
    end
  end

  defp parse_app_mix_exs(mix_content, app_name) do
    # Basic mix.exs parsing - in production would use more sophisticated AST parsing
    config = %{
      app_name: app_name,
      version: extract_version_from_mix(mix_content),
      elixir_version: extract_elixir_version(mix_content),
      dependencies: extract_dependencies_from_mix(mix_content),
      applications: extract_applications_from_mix(mix_content),
      aliases: extract_aliases_from_mix(mix_content)
    }

    {:ok, config}
  end

  defp parse_root_configuration(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")

    with {:ok, mix_content} <- File.read(mix_exs_path) do
      root_config = %{
        umbrella: true,
        apps_path: extract_apps_path(mix_content),
        shared_deps: extract_shared_dependencies(mix_content),
        elixir_version: extract_elixir_version(mix_content),
        preferred_cli_env: extract_preferred_cli_env(mix_content),
        aliases: extract_aliases_from_mix(mix_content)
      }

      {:ok, root_config}
    end
  end

  # Task 2.3.1.3: Map inter-application dependencies
  defp map_inter_app_dependencies(apps_info) do
    dependency_map =
      apps_info
      |> Enum.into(%{}, fn app ->
        internal_deps =
          app.dependencies
          |> Enum.filter(fn dep ->
            internal_dependency?(dep, apps_info)
          end)

        {app.name, internal_deps}
      end)

    {:ok, dependency_map}
  end

  defp internal_dependency?(dep_name, apps_info) when is_binary(dep_name) do
    Enum.any?(apps_info, fn app -> app.name == dep_name end)
  end

  defp internal_dependency?(dep_name, apps_info) when is_atom(dep_name) do
    dep_string = Atom.to_string(dep_name)
    internal_dependency?(dep_string, apps_info)
  end

  defp internal_dependency?(_, _), do: false

  # Task 2.3.1.4: Detect shared configuration patterns
  defp detect_shared_configurations(project_path, apps_info) do
    with {:ok, umbrella_configs} <- parse_umbrella_config_files(project_path),
         {:ok, app_configs} <- aggregate_app_configurations(apps_info),
         {:ok, shared_patterns} <- identify_configuration_patterns(umbrella_configs, app_configs) do
      shared_config = %{
        umbrella_configs: umbrella_configs,
        app_specific_configs: app_configs,
        shared_patterns: shared_patterns,
        inheritance_hierarchy: build_config_inheritance_map(umbrella_configs, app_configs)
      }

      {:ok, shared_config}
    end
  end

  defp parse_umbrella_config_files(project_path) do
    configs =
      @default_umbrella_config_files
      |> Enum.map(fn config_file ->
        config_path = Path.join(project_path, config_file)

        case File.read(config_path) do
          {:ok, content} -> {config_file, content}
          {:error, _} -> {config_file, nil}
        end
      end)
      |> Enum.into(%{})

    {:ok, configs}
  end

  defp aggregate_app_configurations(apps_info) do
    app_configs =
      apps_info
      |> Enum.map(fn app ->
        {app.name, app.test_config}
      end)
      |> Enum.into(%{})

    {:ok, app_configs}
  end

  defp identify_configuration_patterns(umbrella_configs, app_configs) do
    # Identify common configuration patterns across applications
    patterns = %{
      database_configs: detect_database_pattern(umbrella_configs, app_configs),
      logging_configs: detect_logging_pattern(umbrella_configs, app_configs),
      environment_configs: detect_environment_pattern(umbrella_configs, app_configs),
      test_configs: detect_test_pattern(app_configs)
    }

    {:ok, patterns}
  end

  defp build_config_inheritance_map(umbrella_configs, app_configs) do
    # Build hierarchy showing how configurations flow from umbrella to apps
    %{
      umbrella_level: Map.keys(umbrella_configs),
      app_level: Map.keys(app_configs),
      inheritance_rules: [
        "umbrella configs override app configs",
        "test configs are app-specific"
      ]
    }
  end

  # Task 2.3.1.5: Identify release configurations
  defp identify_release_configurations(project_path) do
    release_files = [
      "rel/config.exs",
      "config/releases.exs",
      # Contains release configuration
      "mix.exs"
    ]

    release_configs =
      release_files
      |> Enum.map(fn rel_file ->
        rel_path = Path.join(project_path, rel_file)

        case File.read(rel_path) do
          {:ok, content} ->
            {rel_file, parse_release_config(content)}

          {:error, _} ->
            {rel_file, nil}
        end
      end)
      |> Enum.reject(fn {_file, config} -> is_nil(config) end)
      |> Enum.into(%{})

    {:ok, release_configs}
  end

  defp parse_release_config(content) do
    # Basic release configuration parsing
    %{
      has_releases:
        String.contains?(content, "releases:") or String.contains?(content, "release "),
      has_distillery: String.contains?(content, "distillery"),
      has_mix_release: String.contains?(content, "mix release"),
      content_length: String.length(content)
    }
  end

  # Compilation order calculation
  defp calculate_compilation_order(dependency_map) do
    # Topological sort of applications based on dependencies
    all_apps = Map.keys(dependency_map)

    try do
      sorted_apps = topological_sort(all_apps, dependency_map)
      sorted_apps
    rescue
      _error ->
        # Fallback to alphabetical order if topological sort fails
        Logger.warning("Circular dependencies detected, using alphabetical order")
        Enum.sort(all_apps)
    end
  end

  defp topological_sort(apps, dependency_map) do
    # Simple topological sort implementation
    # Start with apps that have no internal dependencies
    no_deps =
      apps
      |> Enum.filter(fn app ->
        deps = Map.get(dependency_map, app, [])
        Enum.empty?(deps)
      end)

    sorted = []
    remaining = apps -- no_deps

    build_sorted_order(no_deps ++ sorted, remaining, dependency_map, apps)
  end

  defp build_sorted_order(sorted, [], _dependency_map, _all_apps), do: sorted

  defp build_sorted_order(sorted, remaining, dependency_map, all_apps) do
    # Find next apps whose dependencies are all satisfied
    next_ready =
      remaining
      |> Enum.filter(fn app ->
        deps = Map.get(dependency_map, app, [])
        Enum.all?(deps, fn dep -> dep in sorted end)
      end)

    if Enum.empty?(next_ready) do
      # Circular dependency - add remaining in alphabetical order
      sorted ++ Enum.sort(remaining)
    else
      new_sorted = sorted ++ next_ready
      new_remaining = remaining -- next_ready
      build_sorted_order(new_sorted, new_remaining, dependency_map, all_apps)
    end
  end

  # Helper functions for parsing

  defp find_app_test_files(app_path) do
    test_path = Path.join(app_path, "test")

    case File.dir?(test_path) do
      true ->
        case File.ls(test_path) do
          {:ok, files} ->
            test_files =
              files
              |> Enum.filter(&String.ends_with?(&1, ".exs"))
              |> Enum.map(&Path.join(test_path, &1))

            {:ok, test_files}

          {:error, reason} ->
            {:error, reason}
        end

      false ->
        {:ok, []}
    end
  end

  defp find_app_lib_files(app_path) do
    lib_path = Path.join(app_path, "lib")

    case File.dir?(lib_path) do
      true ->
        case Path.wildcard(Path.join(lib_path, "**/*.ex")) do
          [] -> {:ok, []}
          lib_files -> {:ok, lib_files}
        end

      false ->
        {:ok, []}
    end
  end

  defp extract_app_dependencies(app_config) do
    # Extract dependency names from parsed configuration
    app_config.dependencies || []
  end

  defp extract_test_configuration(app_path) do
    config_path = Path.join(app_path, "config")

    case File.dir?(config_path) do
      true ->
        test_config_path = Path.join(config_path, "test.exs")

        case File.read(test_config_path) do
          {:ok, content} -> %{has_test_config: true, content: content}
          {:error, _} -> %{has_test_config: false, content: nil}
        end

      false ->
        %{has_test_config: false, content: nil}
    end
  end

  # Mix.exs parsing helpers

  defp extract_version_from_mix(content) do
    case Regex.run(~r/version:\s*"([^"]+)"/, content) do
      [_, version] -> version
      _ -> "0.1.0"
    end
  end

  defp extract_elixir_version(content) do
    case Regex.run(~r/elixir:\s*"([^"]+)"/, content) do
      [_, version] -> version
      _ -> "~> 1.14"
    end
  end

  defp extract_dependencies_from_mix(content) do
    # Simple dependency extraction - would be more sophisticated in production
    matches = Regex.scan(~r/{:(\w+),/, content)
    Enum.map(matches, fn [_, dep] -> dep end)
  end

  defp extract_applications_from_mix(content) do
    case Regex.run(~r/applications:\s*\[([^\]]+)\]/, content) do
      [_, apps_string] ->
        apps_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.replace(&1, ":", ""))

      _ ->
        []
    end
  end

  defp extract_aliases_from_mix(content) do
    case Regex.run(~r/aliases:\s*\[([^\]]+)\]/, content) do
      [_, aliases_string] ->
        # Basic alias extraction
        %{content: aliases_string}

      _ ->
        %{}
    end
  end

  defp extract_apps_path(content) do
    case Regex.run(~r/apps_path:\s*"([^"]+)"/, content) do
      [_, path] -> path
      _ -> "apps"
    end
  end

  defp extract_shared_dependencies(content) do
    # Extract dependencies from root mix.exs
    extract_dependencies_from_mix(content)
  end

  defp extract_preferred_cli_env(content) do
    case Regex.run(~r/preferred_cli_env:\s*\[([^\]]+)\]/, content) do
      [_, env_string] -> %{content: env_string}
      _ -> %{}
    end
  end

  # Configuration pattern detection

  defp detect_database_pattern(_umbrella_configs, app_configs) do
    database_apps =
      app_configs
      |> Enum.filter(fn {_app, config} ->
        config && config.content && String.contains?(config.content, "database")
      end)
      |> Enum.map(fn {app, _config} -> app end)

    %{
      apps_with_database: database_apps,
      pattern: if(length(database_apps) > 1, do: "shared_database", else: "single_database")
    }
  end

  defp detect_logging_pattern(umbrella_configs, app_configs) do
    has_umbrella_logging =
      umbrella_configs
      |> Enum.any?(fn {_file, content} ->
        content && String.contains?(content, "logger")
      end)

    app_logging_count =
      app_configs
      |> Enum.count(fn {_app, config} ->
        config && config.content && String.contains?(config.content, "logger")
      end)

    %{
      umbrella_logging: has_umbrella_logging,
      app_logging_count: app_logging_count,
      pattern: determine_logging_pattern(has_umbrella_logging, app_logging_count)
    }
  end

  defp detect_environment_pattern(umbrella_configs, _app_configs) do
    env_files =
      umbrella_configs
      |> Enum.filter(fn {file, content} ->
        content &&
          (String.contains?(file, "dev.exs") or
             String.contains?(file, "prod.exs") or
             String.contains?(file, "test.exs"))
      end)
      |> Enum.map(fn {file, _content} -> file end)

    %{
      environment_files: env_files,
      has_env_specific_config: not Enum.empty?(env_files)
    }
  end

  defp detect_test_pattern(app_configs) do
    test_config_count =
      app_configs
      |> Enum.count(fn {_app, config} ->
        config && config.has_test_config
      end)

    %{
      apps_with_test_config: test_config_count,
      pattern:
        if(test_config_count > 0, do: "distributed_test_config", else: "centralized_test_config")
    }
  end

  defp determine_logging_pattern(true, 0), do: "centralized_umbrella_logging"

  defp determine_logging_pattern(false, app_count) when app_count > 0,
    do: "distributed_app_logging"

  defp determine_logging_pattern(true, app_count) when app_count > 0, do: "hybrid_logging"
  defp determine_logging_pattern(false, 0), do: "no_explicit_logging"

  # Utility functions

  defp convert_to_app_info(analysis) do
    %{
      name: get_app_name(analysis.project_path),
      path: analysis.project_path,
      mix_exs_path: Path.join(analysis.project_path, "mix.exs"),
      configuration: analysis.configuration,
      test_files: analysis.test_structure.test_files || [],
      lib_files: analysis.test_structure.source_files || [],
      dependencies: analysis.build_requirements.dependencies || [],
      test_config: %{has_test_config: true, content: nil}
    }
  end

  defp get_app_name(project_path) do
    project_path
    |> Path.basename()
    |> String.replace("-", "_")
  end

  @doc """
  Validates umbrella project structure for evaluation compatibility.
  """
  def validate_umbrella_structure(umbrella_structure) do
    validations = %{
      has_valid_apps: validate_apps_present(umbrella_structure),
      compilation_order_valid: validate_compilation_order(umbrella_structure),
      dependencies_resolvable: validate_dependencies(umbrella_structure),
      configs_consistent: validate_configuration_consistency(umbrella_structure)
    }

    overall_valid = Enum.all?(Map.values(validations))

    %{
      valid: overall_valid,
      validations: validations,
      issues: collect_validation_issues(validations)
    }
  end

  defp validate_apps_present(umbrella_structure) do
    umbrella_structure.total_apps > 0 and
      not Enum.empty?(umbrella_structure.applications)
  end

  defp validate_compilation_order(umbrella_structure) do
    not Enum.empty?(umbrella_structure.compilation_order) and
      length(umbrella_structure.compilation_order) == umbrella_structure.total_apps
  end

  defp validate_dependencies(umbrella_structure) do
    # Check that all internal dependencies can be resolved
    all_app_names = Enum.map(umbrella_structure.applications, & &1.name)

    umbrella_structure.inter_app_dependencies
    |> Enum.all?(fn {_app, deps} ->
      Enum.all?(deps, fn dep -> dep in all_app_names end)
    end)
  end

  defp validate_configuration_consistency(_umbrella_structure) do
    # Basic validation - would be more comprehensive in production
    true
  end

  defp collect_validation_issues(validations) do
    issues = []

    issues =
      if validations.has_valid_apps do
        issues
      else
        ["No valid applications found in umbrella structure" | issues]
      end

    issues =
      if validations.compilation_order_valid do
        issues
      else
        ["Invalid compilation order calculation" | issues]
      end

    issues =
      if validations.dependencies_resolvable do
        issues
      else
        ["Unresolvable inter-application dependencies detected" | issues]
      end

    issues
  end
end
