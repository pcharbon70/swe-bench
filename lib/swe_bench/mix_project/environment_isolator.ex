defmodule SweBench.MixProject.EnvironmentIsolator do
  @moduledoc """
  Mix environment isolation for deterministic evaluation builds.

  Provides isolated Mix environments with proper MIX_ENV, MIX_HOME,
  and HEX_HOME path management for reproducible compilation results.
  """

  require Logger

  @doc """
  Creates an isolated Mix environment for evaluation.
  """
  def create_isolated_environment(project_path, opts \\ []) do
    evaluation_id = Keyword.get(opts, :evaluation_id, generate_evaluation_id())
    mix_env = Keyword.get(opts, :mix_env, "test")

    isolated_paths = setup_isolated_paths(evaluation_id)
    environment_vars = build_environment_variables(isolated_paths, mix_env, project_path)

    Logger.debug("Created isolated environment for #{evaluation_id}")

    {:ok,
     %{
       evaluation_id: evaluation_id,
       mix_home: isolated_paths.mix_home,
       hex_home: isolated_paths.hex_home,
       build_path: isolated_paths.build_path,
       environment_vars: environment_vars,
       project_path: project_path
     }}
  end

  @doc """
  Configures Mix environment variables for deterministic compilation.
  """
  def setup_deterministic_compilation_flags do
    %{
      "ERL_COMPILER_OPTIONS" => "deterministic",
      "MIX_QUIET" => "1",
      "MIX_DEBUG" => "0",
      "ELIXIR_MAKE_CACHE_DIR" => "/tmp/elixir_make_cache"
    }
  end

  @doc """
  Restores Mix environment after evaluation cleanup.
  """
  def cleanup_isolated_environment(environment) do
    Logger.debug("Cleaning up isolated environment #{environment.evaluation_id}")

    cleanup_paths = [
      environment.mix_home,
      environment.hex_home,
      environment.build_path
    ]

    Enum.each(cleanup_paths, fn path ->
      case File.rm_rf(path) do
        {:ok, _files} ->
          Logger.debug("Cleaned up: #{path}")

        {:error, reason, _file} ->
          Logger.warning("Failed to cleanup #{path}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Validates that environment isolation is working correctly.
  """
  def validate_environment_isolation(environment) do
    checks = [
      check_mix_home_isolation(environment),
      check_hex_home_isolation(environment),
      check_build_path_isolation(environment),
      check_environment_variables(environment)
    ]

    case Enum.all?(checks, &(&1 == :ok)) do
      true -> {:ok, :validated}
      false -> {:error, :isolation_validation_failed}
    end
  end

  @doc """
  Gets current Mix environment configuration.
  """
  def get_current_environment do
    %{
      mix_env: System.get_env("MIX_ENV", "dev"),
      mix_home: System.get_env("MIX_HOME", Path.expand("~/.mix")),
      hex_home: System.get_env("HEX_HOME", Path.expand("~/.hex")),
      build_path: System.get_env("MIX_BUILD_PATH", "_build")
    }
  end

  @doc """
  Applies environment configuration to system.
  """
  def apply_environment(environment) do
    Enum.each(environment.environment_vars, fn {key, value} ->
      System.put_env(key, value)
    end)

    Logger.debug("Applied environment variables for #{environment.evaluation_id}")
    :ok
  end

  @doc """
  Creates a Mix execution context with isolated environment.
  """
  def create_execution_context(project_path, opts \\ []) do
    with {:ok, environment} <- create_isolated_environment(project_path, opts),
         :ok <- apply_environment(environment),
         {:ok, :validated} <- validate_environment_isolation(environment) do
      {:ok, environment}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp generate_evaluation_id do
    timestamp = System.system_time(:second)
    random = :rand.uniform(999_999)
    "eval_#{timestamp}_#{random}"
  end

  defp setup_isolated_paths(evaluation_id) do
    base_path = Path.join([System.tmp_dir!(), "swe_bench_mix", evaluation_id])

    paths = %{
      mix_home: Path.join(base_path, "mix"),
      hex_home: Path.join(base_path, "hex"),
      build_path: Path.join(base_path, "_build"),
      deps_path: Path.join(base_path, "deps")
    }

    # Create directories
    Enum.each(Map.values(paths), fn path ->
      File.mkdir_p!(path)
    end)

    paths
  end

  defp build_environment_variables(paths, mix_env, project_path) do
    base_vars = %{
      "MIX_ENV" => mix_env,
      "MIX_HOME" => paths.mix_home,
      "HEX_HOME" => paths.hex_home,
      "MIX_BUILD_PATH" => paths.build_path,
      "MIX_DEPS_PATH" => paths.deps_path,
      "MIX_PROJECT_PATH" => project_path
    }

    deterministic_flags = setup_deterministic_compilation_flags()

    Map.merge(base_vars, deterministic_flags)
  end

  defp check_mix_home_isolation(environment) do
    if File.exists?(environment.mix_home) do
      :ok
    else
      Logger.error("MIX_HOME isolation failed: #{environment.mix_home} not found")
      :error
    end
  end

  defp check_hex_home_isolation(environment) do
    if File.exists?(environment.hex_home) do
      :ok
    else
      Logger.error("HEX_HOME isolation failed: #{environment.hex_home} not found")
      :error
    end
  end

  defp check_build_path_isolation(environment) do
    if File.exists?(environment.build_path) do
      :ok
    else
      Logger.error("Build path isolation failed: #{environment.build_path} not found")
      :error
    end
  end

  defp check_environment_variables(environment) do
    required_vars = ["MIX_ENV", "MIX_HOME", "HEX_HOME", "MIX_BUILD_PATH"]

    missing_vars =
      Enum.filter(required_vars, fn var ->
        System.get_env(var) != environment.environment_vars[var]
      end)

    case missing_vars do
      [] ->
        :ok

      vars ->
        Logger.error("Environment variable isolation failed for: #{inspect(vars)}")
        :error
    end
  end
end
