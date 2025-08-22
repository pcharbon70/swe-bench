defmodule SweBench.MixProject.ProjectAnalyzer do
  @moduledoc """
  Mix project structure analysis and configuration parsing.

  Detects project type, maps application dependencies, identifies test
  file locations, and parses configuration files for evaluation setup.
  """

  require Logger

  @doc """
  Analyzes a Mix project and returns comprehensive structure information.
  """
  def analyze_project(project_path, _opts \\ []) do
    Logger.info("Analyzing project structure at #{project_path}")

    with {:ok, project_type} <- detect_project_type(project_path),
         {:ok, app_dependencies} <- map_application_dependencies(project_path, project_type),
         {:ok, test_locations} <- identify_test_file_locations(project_path, project_type),
         {:ok, config_data} <- parse_configuration_files(project_path),
         {:ok, build_requirements} <- extract_build_tool_requirements(project_path) do
      analysis = %{
        project_type: project_type,
        project_path: project_path,
        applications: app_dependencies,
        test_structure: test_locations,
        configuration: config_data,
        build_requirements: build_requirements,
        analysis_timestamp: DateTime.utc_now()
      }

      Logger.info(
        "Project analysis complete: #{project_type} project with #{length(app_dependencies)} apps"
      )

      {:ok, analysis}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Detects project type: standard, umbrella, or poncho.
  """
  def detect_project_type(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")

    case File.read(mix_exs_path) do
      {:ok, content} ->
        analyze_mix_exs_for_type(content, project_path)

      {:error, reason} ->
        Logger.error("Failed to read mix.exs at #{mix_exs_path}: #{inspect(reason)}")
        {:error, {:mix_exs_read_error, reason}}
    end
  end

  @doc """
  Maps application dependencies within the project.
  """
  def map_application_dependencies(project_path, project_type) do
    case project_type do
      :umbrella ->
        map_umbrella_app_dependencies(project_path)

      :poncho ->
        map_poncho_app_dependencies(project_path)

      :standard ->
        map_standard_app_dependencies(project_path)
    end
  end

  @doc """
  Identifies test file locations and patterns.
  """
  def identify_test_file_locations(project_path, project_type) do
    Logger.debug("Identifying test file locations for #{project_type} project")

    case project_type do
      :umbrella ->
        find_umbrella_test_files(project_path)

      :poncho ->
        find_poncho_test_files(project_path)

      :standard ->
        find_standard_test_files(project_path)
    end
  end

  @doc """
  Parses configuration files (config.exs, runtime.exs, etc.).
  """
  def parse_configuration_files(project_path) do
    config_dir = Path.join(project_path, "config")

    config_files = [
      "config.exs",
      "dev.exs",
      "test.exs",
      "prod.exs",
      "runtime.exs"
    ]

    parsed_configs =
      Enum.reduce(config_files, %{}, fn file, acc ->
        file_path = Path.join(config_dir, file)

        case File.read(file_path) do
          {:ok, content} ->
            Map.put(acc, file, parse_config_content(content))

          {:error, :enoent} ->
            acc

          {:error, reason} ->
            Logger.warning("Failed to read #{file}: #{inspect(reason)}")
            acc
        end
      end)

    {:ok, parsed_configs}
  end

  @doc """
  Extracts build tool requirements and constraints.
  """
  def extract_build_tool_requirements(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")

    case File.read(mix_exs_path) do
      {:ok, content} ->
        requirements = %{
          elixir_version: extract_elixir_version(content),
          erlang_version: extract_erlang_version(content),
          build_tools: extract_build_tools(content),
          compilers: extract_compilers(content)
        }

        {:ok, requirements}

      {:error, reason} ->
        {:error, {:build_requirements_extraction_failed, reason}}
    end
  end

  # Private helper functions

  defp analyze_mix_exs_for_type(content, project_path) do
    cond do
      String.contains?(content, "umbrella: true") ->
        {:ok, :umbrella}

      String.contains?(content, "apps_path:") ->
        {:ok, :umbrella}

      File.exists?(Path.join(project_path, "apps")) &&
          not String.contains?(content, "umbrella: true") ->
        {:ok, :poncho}

      true ->
        {:ok, :standard}
    end
  end

  defp map_umbrella_app_dependencies(umbrella_path) do
    apps_path = Path.join(umbrella_path, "apps")

    case File.ls(apps_path) do
      {:ok, app_dirs} ->
        apps =
          Enum.map(app_dirs, fn app_dir ->
            app_path = Path.join(apps_path, app_dir)
            analyze_single_app(app_dir, app_path)
          end)

        {:ok, apps}

      {:error, reason} ->
        {:error, {:umbrella_mapping_failed, reason}}
    end
  end

  defp map_poncho_app_dependencies(project_path) do
    apps_path = Path.join(project_path, "apps")

    case File.ls(apps_path) do
      {:ok, app_dirs} ->
        apps =
          Enum.map(app_dirs, fn app_dir ->
            app_path = Path.join(apps_path, app_dir)
            analyze_single_app(app_dir, app_path)
          end)

        {:ok, apps}

      {:error, reason} ->
        {:error, {:poncho_mapping_failed, reason}}
    end
  end

  defp map_standard_app_dependencies(project_path) do
    app_name = Path.basename(project_path)
    app_info = analyze_single_app(app_name, project_path)

    {:ok, [app_info]}
  end

  defp analyze_single_app(app_name, app_path) do
    mix_exs_path = Path.join(app_path, "mix.exs")

    deps =
      case File.read(mix_exs_path) do
        {:ok, content} -> extract_app_dependencies(content)
        {:error, _} -> []
      end

    %{
      name: app_name,
      path: app_path,
      dependencies: deps,
      has_tests: File.exists?(Path.join(app_path, "test"))
    }
  end

  defp find_umbrella_test_files(umbrella_path) do
    apps_path = Path.join(umbrella_path, "apps")

    case File.ls(apps_path) do
      {:ok, app_dirs} ->
        test_files =
          Enum.flat_map(app_dirs, fn app_dir ->
            app_test_path = Path.join([apps_path, app_dir, "test"])
            find_test_files_in_directory(app_test_path, app_dir)
          end)

        {:ok, test_files}

      {:error, reason} ->
        {:error, {:umbrella_test_discovery_failed, reason}}
    end
  end

  defp find_poncho_test_files(project_path) do
    find_umbrella_test_files(project_path)
  end

  defp find_standard_test_files(project_path) do
    test_path = Path.join(project_path, "test")
    app_name = Path.basename(project_path)

    test_files = find_test_files_in_directory(test_path, app_name)
    {:ok, test_files}
  end

  defp find_test_files_in_directory(test_path, app_name) do
    case File.ls(test_path) do
      {:ok, files} ->
        test_files =
          files
          |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
          |> Enum.map(fn file ->
            %{
              app: app_name,
              file: file,
              path: Path.join(test_path, file)
            }
          end)

        test_files

      {:error, _} ->
        []
    end
  end

  defp parse_config_content(content) do
    # Simplified config parsing - would use AST parsing in production
    %{
      content_length: String.length(content),
      has_runtime_config: String.contains?(content, "runtime.exs"),
      has_environment_configs: String.contains?(content, "import_config")
    }
  end

  defp extract_elixir_version(content) do
    case Regex.run(~r/elixir:\s*"([^"]+)"/, content) do
      [_, version] -> version
      nil -> "unknown"
    end
  end

  defp extract_erlang_version(content) do
    case Regex.run(~r/erlang:\s*"([^"]+)"/, content) do
      [_, version] -> version
      nil -> "unknown"
    end
  end

  defp extract_build_tools(content) do
    tools = []

    tools = if String.contains?(content, "make_clean"), do: ["make" | tools], else: tools
    tools = if String.contains?(content, "npm"), do: ["npm" | tools], else: tools
    tools = if String.contains?(content, "esbuild"), do: ["esbuild" | tools], else: tools

    tools
  end

  defp extract_compilers(content) do
    case Regex.run(~r/compilers:\s*\[([^\]]+)\]/, content) do
      [_, compilers_str] ->
        compilers_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.replace(&1, ":", ""))

      nil ->
        ["elixir", "app"]
    end
  end

  defp extract_app_dependencies(content) do
    # Simplified dependency extraction - would use AST parsing in production
    case Regex.scan(~r/{:(\w+),/, content) do
      matches -> Enum.map(matches, fn [_, dep] -> dep end)
      [] -> []
    end
  end
end
