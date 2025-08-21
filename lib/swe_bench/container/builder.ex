defmodule SweBench.Container.Builder do
  @moduledoc """
  Docker image builder for the three-layer architecture.

  Handles building and managing Docker images optimized for BEAM VM:
  - Base layer: Elixir/OTP runtime
  - Environment layer: Dependencies and caching
  - Instance layer: Execution and patching
  """

  require Logger

  @doc """
  Builds all three layers of the Docker architecture.
  """
  def build_all_images(config, opts \\ []) do
    force_rebuild = Keyword.get(opts, :force, false)

    with {:ok, base_id} <- build_base_image(config, force_rebuild),
         {:ok, env_id} <- build_env_image(config, base_id, force_rebuild),
         {:ok, instance_id} <- build_instance_image(config, env_id, force_rebuild) do
      {:ok,
       %{
         base: base_id,
         env: env_id,
         instance: instance_id
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds the base Docker image with Elixir/OTP runtime.
  """
  def build_base_image(config, force_rebuild \\ false) do
    image_name = config.base_image
    dockerfile_path = Path.join([File.cwd!(), "docker", "base", "Dockerfile"])

    Logger.info("Building base image: #{image_name}")

    if should_rebuild?(image_name, force_rebuild) do
      build_args = [
        "build",
        "-t",
        image_name,
        "-f",
        dockerfile_path,
        Path.join([File.cwd!(), "docker", "base"])
      ]

      case run_docker_command(build_args) do
        {output, 0} ->
          image_id = extract_image_id(output)
          Logger.info("Successfully built base image: #{image_id}")
          {:ok, image_id}

        {error_output, exit_code} ->
          Logger.error("Failed to build base image: #{error_output}")
          {:error, {:build_failed, exit_code, error_output}}
      end
    else
      Logger.info("Base image #{image_name} already exists, skipping build")
      {:ok, get_image_id(image_name)}
    end
  end

  @doc """
  Builds the environment Docker image with dependency caching.
  """
  def build_env_image(config, _base_image_id, force_rebuild \\ false) do
    image_name = config.env_image
    dockerfile_path = Path.join([File.cwd!(), "docker", "env", "Dockerfile"])

    Logger.info("Building environment image: #{image_name}")

    if should_rebuild?(image_name, force_rebuild) do
      build_args = [
        "build",
        "-t",
        image_name,
        "-f",
        dockerfile_path,
        "--build-arg",
        "BASE_IMAGE=#{config.base_image}",
        Path.join([File.cwd!(), "docker", "env"])
      ]

      case run_docker_command(build_args) do
        {output, 0} ->
          image_id = extract_image_id(output)
          Logger.info("Successfully built environment image: #{image_id}")
          {:ok, image_id}

        {error_output, exit_code} ->
          Logger.error("Failed to build environment image: #{error_output}")
          {:error, {:build_failed, exit_code, error_output}}
      end
    else
      Logger.info("Environment image #{image_name} already exists, skipping build")
      {:ok, get_image_id(image_name)}
    end
  end

  @doc """
  Builds the instance Docker image for execution.
  """
  def build_instance_image(config, _env_image_id, force_rebuild \\ false) do
    image_name = config.instance_image
    dockerfile_path = Path.join([File.cwd!(), "docker", "instance", "Dockerfile"])

    Logger.info("Building instance image: #{image_name}")

    if should_rebuild?(image_name, force_rebuild) do
      build_args = [
        "build",
        "-t",
        image_name,
        "-f",
        dockerfile_path,
        "--build-arg",
        "ENV_IMAGE=#{config.env_image}",
        Path.join([File.cwd!(), "docker", "instance"])
      ]

      case run_docker_command(build_args) do
        {output, 0} ->
          image_id = extract_image_id(output)
          Logger.info("Successfully built instance image: #{image_id}")
          {:ok, image_id}

        {error_output, exit_code} ->
          Logger.error("Failed to build instance image: #{error_output}")
          {:error, {:build_failed, exit_code, error_output}}
      end
    else
      Logger.info("Instance image #{image_name} already exists, skipping build")
      {:ok, get_image_id(image_name)}
    end
  end

  @doc """
  Creates a new container from the instance image.
  """
  def create_instance_container(config) do
    container_name = "swe-bench-instance-#{System.unique_integer([:positive])}"
    image_name = config.instance_image

    Logger.debug("Creating container: #{container_name}")

    run_args = [
      "run",
      "-d",
      "--name",
      container_name,
      "--memory",
      "#{div(config.memory_limit, 1_048_576)}m",
      "--cpus",
      "#{config.cpu_limit}",
      "--network",
      "none",
      # Security settings
      "--user",
      "elixir",
      "--read-only",
      "--tmpfs",
      "/tmp:exec,size=100m",
      "--tmpfs",
      "/opt/app/tmp:exec,size=500m",
      # Resource limits
      "--ulimit",
      "nproc=1024",
      "--ulimit",
      "nofile=1024",
      image_name,
      "sleep",
      "infinity"
    ]

    case run_docker_command(run_args) do
      {container_id, 0} ->
        container_id = String.trim(container_id)
        Logger.debug("Created container: #{container_id}")
        {:ok, container_id}

      {error_output, exit_code} ->
        Logger.error("Failed to create container: #{error_output}")
        {:error, {:container_creation_failed, exit_code, error_output}}
    end
  end

  @doc """
  Removes a Docker container.
  """
  def remove_container(container_id) do
    Logger.debug("Removing container: #{container_id}")

    # Stop container first
    stop_args = ["stop", container_id]
    run_docker_command(stop_args)

    # Remove container
    remove_args = ["rm", "-f", container_id]

    case run_docker_command(remove_args) do
      {_output, 0} ->
        Logger.debug("Successfully removed container: #{container_id}")
        :ok

      {error_output, exit_code} ->
        Logger.warning("Failed to remove container #{container_id}: #{error_output}")
        {:error, {:removal_failed, exit_code, error_output}}
    end
  end

  @doc """
  Lists all Docker images with swe-bench labels.
  """
  def list_images do
    list_args = [
      "images",
      "--filter",
      "label=swe-bench.layer",
      "--format",
      "table {{.Repository}}:{{.Tag}}\\t{{.ID}}\\t{{.CreatedAt}}"
    ]

    case run_docker_command(list_args) do
      {output, 0} ->
        images = parse_image_list(output)
        {:ok, images}

      {error_output, exit_code} ->
        {:error, {:list_failed, exit_code, error_output}}
    end
  end

  @doc """
  Removes unused Docker images and containers.
  """
  def cleanup_unused do
    Logger.info("Cleaning up unused Docker resources")

    # Remove stopped containers
    cleanup_args = ["container", "prune", "-f", "--filter", "label=swe-bench.layer"]
    run_docker_command(cleanup_args)

    # Remove unused images
    image_cleanup_args = ["image", "prune", "-f", "--filter", "label=swe-bench.layer"]
    run_docker_command(image_cleanup_args)

    :ok
  end

  # Private Functions

  defp should_rebuild?(image_name, force_rebuild) do
    force_rebuild or not image_exists?(image_name)
  end

  defp image_exists?(image_name) do
    inspect_args = ["inspect", image_name]

    case run_docker_command(inspect_args) do
      {_output, 0} -> true
      {_error, _code} -> false
    end
  end

  defp get_image_id(image_name) do
    inspect_args = ["inspect", "--format={{.Id}}", image_name]

    case run_docker_command(inspect_args) do
      {output, 0} -> String.trim(output)
      {_error, _code} -> "unknown"
    end
  end

  defp extract_image_id(docker_output) do
    # Extract image ID from Docker build output
    docker_output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      if String.contains?(line, "Successfully built") do
        line |> String.split() |> List.last()
      end
    end) || "unknown"
  end

  defp parse_image_list(output) do
    output
    |> String.split("\n")
    # Skip header
    |> Enum.drop(1)
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.filter(fn parts -> length(parts) >= 3 end)
    |> Enum.map(fn [name, id, created] ->
      %{name: name, id: id, created: created}
    end)
  end

  defp run_docker_command(args) do
    Logger.debug("Running docker command: docker #{Enum.join(args, " ")}")

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {output, exit_code} ->
        Logger.debug("Docker command result: exit_code=#{exit_code}")

        if exit_code != 0 do
          Logger.debug("Docker error output: #{output}")
        end

        {output, exit_code}

      error ->
        Logger.error("Failed to run docker command: #{inspect(error)}")
        {"Command execution failed", 1}
    end
  end
end
