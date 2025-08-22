defmodule SweBench.MixProject.DependencyManager do
  @moduledoc """
  Mix dependency resolution and management for evaluation environments.

  Handles mix.lock parsing, Hex package caching, git dependencies,
  and version conflict resolution for reproducible builds.
  """

  require Logger

  @doc """
  Resolves and installs dependencies for a Mix project.
  """
  def resolve_dependencies(project_path, opts \\ []) do
    Logger.info("Resolving dependencies for #{project_path}")

    with {:ok, lockfile_data} <- parse_lockfile(project_path),
         {:ok, deps_config} <- parse_deps_from_mix_exs(project_path),
         {:ok, resolved_deps} <- resolve_dependency_conflicts(lockfile_data, deps_config, opts),
         :ok <- install_dependencies(project_path, resolved_deps, opts) do
      {:ok,
       %{
         lockfile_deps: lockfile_data,
         resolved_deps: resolved_deps,
         installation_path: project_path
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses mix.lock file and extracts dependency information.
  """
  def parse_lockfile(project_path) do
    lockfile_path = Path.join(project_path, "mix.lock")

    case File.read(lockfile_path) do
      {:ok, content} ->
        parse_lockfile_content(content)

      {:error, :enoent} ->
        Logger.warning("No mix.lock found at #{lockfile_path}")
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("Failed to read mix.lock: #{inspect(reason)}")
        {:error, {:lockfile_read_error, reason}}
    end
  end

  @doc """
  Caches Hex packages locally for offline dependency resolution.
  """
  def cache_hex_packages(dependencies, cache_path) do
    Logger.debug("Caching #{length(Map.keys(dependencies))} Hex packages")

    File.mkdir_p!(cache_path)

    cached =
      dependencies
      |> Enum.filter(fn {_name, dep} -> dep.source == :hex end)
      |> Enum.map(fn {name, dep} ->
        {:ok, cache_info} = cache_single_hex_package(name, dep, cache_path)
        cache_info
      end)

    {:ok, cached}
  end

  @doc """
  Handles git-based dependencies with commit/tag resolution.
  """
  def resolve_git_dependencies(dependencies, opts \\ []) do
    Logger.debug("Resolving git dependencies")

    git_deps = Enum.filter(dependencies, fn {_name, dep} -> dep.source == :git end)

    resolved =
      Enum.reduce(git_deps, %{}, fn {name, dep}, acc ->
        {:ok, resolved_dep} = resolve_git_dependency(name, dep, opts)
        Map.put(acc, name, resolved_dep)
      end)

    {:ok, resolved}
  end

  @doc """
  Detects and resolves version conflicts between dependencies.
  """
  def resolve_version_conflicts(lockfile_deps, mix_deps, opts \\ []) do
    Logger.debug("Checking for version conflicts")

    conflicts = detect_version_conflicts(lockfile_deps, mix_deps)

    case conflicts do
      [] ->
        {:ok, lockfile_deps}

      _conflicts ->
        resolution_strategy = Keyword.get(opts, :conflict_resolution, :prefer_lockfile)
        resolve_conflicts(conflicts, lockfile_deps, mix_deps, resolution_strategy)
    end
  end

  @doc """
  Validates dependency integrity using checksums.
  """
  def validate_dependency_integrity(dependencies) do
    Logger.debug("Validating dependency integrity")

    Enum.reduce_while(dependencies, {:ok, []}, fn {name, dep}, {:ok, validated} ->
      case validate_single_dependency(name, dep) do
        {:ok, validation_info} ->
          {:cont, {:ok, [validation_info | validated]}}

        {:error, reason} ->
          {:halt, {:error, {:integrity_check_failed, name, reason}}}
      end
    end)
  end

  @doc """
  Gets dependency status and statistics.
  """
  def get_dependency_stats(project_path) do
    with {:ok, lockfile_data} <- parse_lockfile(project_path),
         {:ok, deps_config} <- parse_deps_from_mix_exs(project_path) do
      stats = %{
        total_dependencies: map_size(lockfile_data),
        hex_packages: count_dependencies_by_source(lockfile_data, :hex),
        git_dependencies: count_dependencies_by_source(lockfile_data, :git),
        path_dependencies: count_dependencies_by_source(lockfile_data, :path),
        mix_exs_deps: length(deps_config),
        locked_versions: map_size(lockfile_data)
      }

      {:ok, stats}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp parse_lockfile_content(content) do
    {lockfile_data, _} = Code.eval_string(content)

    parsed_deps =
      Map.new(lockfile_data, fn {name, lock_data} ->
        {name, parse_lock_entry(lock_data)}
      end)

    {:ok, parsed_deps}
  rescue
    error ->
      Logger.error("Failed to parse lockfile content: #{inspect(error)}")
      {:error, {:lockfile_parse_error, error}}
  end

  defp parse_lock_entry({:hex, package, version, checksum, managers, deps, _hex_metadata}) do
    %{
      source: :hex,
      package: package,
      version: version,
      checksum: checksum,
      managers: managers,
      dependencies: deps || []
    }
  end

  defp parse_lock_entry({:git, url, ref, options}) do
    %{
      source: :git,
      url: url,
      ref: ref,
      options: options || []
    }
  end

  defp parse_lock_entry(other) do
    %{
      source: :unknown,
      raw: other
    }
  end

  defp parse_deps_from_mix_exs(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")

    case File.read(mix_exs_path) do
      {:ok, content} ->
        extract_deps_from_mix_content(content)

      {:error, reason} ->
        Logger.error("Failed to read mix.exs: #{inspect(reason)}")
        {:error, {:mix_exs_read_error, reason}}
    end
  end

  defp extract_deps_from_mix_content(content) do
    # Simple regex extraction - could be enhanced with AST parsing
    case Regex.run(~r/defp deps do\s*\[\s*(.*?)\s*\]/s, content) do
      [_, deps_content] ->
        # This is a simplified parser - in production, would use AST parsing
        {:ok, String.split(deps_content, "\n") |> length()}

      nil ->
        Logger.warning("Could not extract deps from mix.exs")
        {:ok, []}
    end
  end

  defp resolve_dependency_conflicts(lockfile_deps, _mix_deps, _opts) do
    # For now, trust the lockfile - could be enhanced with conflict detection
    {:ok, lockfile_deps}
  end

  defp detect_version_conflicts(_lockfile_deps, _mix_deps) do
    # Placeholder for version conflict detection logic
    []
  end

  defp resolve_conflicts(conflicts, lockfile_deps, _mix_deps, :prefer_lockfile) do
    Logger.info("Resolving #{length(conflicts)} conflicts by preferring lockfile versions")
    {:ok, lockfile_deps}
  end

  defp cache_single_hex_package(name, dep, cache_path) do
    package_cache_path = Path.join(cache_path, "#{name}-#{dep.version}")

    if File.exists?(package_cache_path) do
      {:ok, %{name: name, cached_path: package_cache_path, status: :already_cached}}
    else
      # Placeholder for actual Hex package caching
      File.mkdir_p!(package_cache_path)
      {:ok, %{name: name, cached_path: package_cache_path, status: :newly_cached}}
    end
  end

  defp resolve_git_dependency(name, dep, _opts) do
    Logger.debug("Resolving git dependency: #{name} from #{dep.url}")

    # Placeholder for git dependency resolution
    {:ok,
     %{
       name: name,
       url: dep.url,
       ref: dep.ref,
       resolved_commit: dep.ref,
       status: :resolved
     }}
  end

  defp validate_single_dependency(name, dep) do
    case dep.source do
      :hex ->
        validate_hex_dependency(name, dep)

      :git ->
        validate_git_dependency(name, dep)

      _ ->
        {:ok, %{name: name, status: :skipped_validation}}
    end
  end

  defp validate_hex_dependency(name, dep) do
    # Placeholder for Hex package validation
    if dep.checksum do
      {:ok, %{name: name, checksum: dep.checksum, status: :valid}}
    else
      {:error, :missing_checksum}
    end
  end

  defp validate_git_dependency(name, dep) do
    # Placeholder for git dependency validation
    if dep.ref do
      {:ok, %{name: name, ref: dep.ref, status: :valid}}
    else
      {:error, :missing_ref}
    end
  end

  defp count_dependencies_by_source(dependencies, source) do
    dependencies
    |> Enum.count(fn {_name, dep} -> dep.source == source end)
  end

  defp install_dependencies(project_path, _resolved_deps, _opts) do
    Logger.debug("Installing dependencies for #{project_path}")
    # Placeholder for actual dependency installation
    :ok
  end
end
