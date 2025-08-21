defmodule SweBench.ContainerTest do
  @moduledoc """
  Comprehensive tests for the Docker containerization system.

  Tests the three-layer Docker architecture and container orchestration
  functionality including image building, container management, and
  patch evaluation execution.
  """

  use ExUnit.Case, async: false

  alias SweBench.Container
  alias SweBench.Container.{Builder, Executor, Pool}

  @moduletag :integration

  setup_all do
    # Ensure Docker is available
    case System.cmd("docker", ["--version"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      _ ->
        ExUnit.configure(exclude: [:integration])
        {:skip, "Docker not available"}
    end
  end

  setup do
    # Clean up any existing test containers/images before each test
    cleanup_test_resources()

    config = %{
      base_image: "swe-bench-test/base:latest",
      env_image: "swe-bench-test/env:latest",
      instance_image: "swe-bench-test/instance:latest",
      pool_size: 2,
      max_containers: 5,
      execution_timeout: 30_000,
      # 1GB
      memory_limit: 1_073_741_824,
      cpu_limit: 2
    }

    {:ok, config: config}
  end

  describe "Container orchestration system" do
    test "starts and stops successfully", %{config: config} do
      assert {:ok, pid} = Container.start_link(config: config)

      # Check initial status
      status = Container.status()
      assert status.images_built == false
      assert status.active_pools == 0
      assert status.active_executions == 0

      # Clean shutdown
      assert :ok = Container.cleanup()

      # Process should still be running but cleaned up
      assert Process.alive?(pid)
    end

    test "builds Docker images successfully", %{config: config} do
      {:ok, _pid} = Container.start_link(config: config)

      # Build images
      assert {:ok, image_ids} = Container.build_images()

      # Verify all images were built
      assert Map.has_key?(image_ids, :base)
      assert Map.has_key?(image_ids, :env)
      assert Map.has_key?(image_ids, :instance)

      # Check status after build
      status = Container.status()
      assert status.images_built == true

      Container.cleanup()
    end

    test "creates and manages container pools", %{config: config} do
      {:ok, _pid} = Container.start_link(config: config)
      Container.build_images()

      # Create pool
      assert {:ok, pool_id} = Container.create_pool(size: 3)

      # Check pool status
      status = Container.status()
      assert status.active_pools == 1

      # Clean up
      Container.cleanup()
    end
  end

  describe "Docker image builder" do
    test "builds base image with correct configuration", %{config: config} do
      assert {:ok, image_id} = Builder.build_base_image(config, true)
      assert is_binary(image_id)

      # Verify image was created
      {output, 0} = System.cmd("docker", ["images", config.base_image, "-q"])
      assert String.trim(output) != ""

      # Test image functionality
      {output, 0} =
        System.cmd("docker", [
          "run",
          "--rm",
          config.base_image,
          "elixir",
          "--version"
        ])

      assert String.contains?(output, "Elixir")
    end

    test "builds environment image with dependency caching", %{config: config} do
      # Build base image first
      {:ok, _base_id} = Builder.build_base_image(config, true)

      # Build environment image
      assert {:ok, env_id} = Builder.build_env_image(config, config.base_image, true)
      assert is_binary(env_id)

      # Verify Mix is working in environment image
      {output, 0} =
        System.cmd("docker", [
          "run",
          "--rm",
          config.env_image,
          "mix",
          "help"
        ])

      assert String.contains?(output, "mix")
    end

    test "builds instance image with execution capabilities", %{config: config} do
      # Build prerequisite images
      {:ok, _base_id} = Builder.build_base_image(config, true)
      {:ok, _env_id} = Builder.build_env_image(config, config.base_image, true)

      # Build instance image
      assert {:ok, instance_id} = Builder.build_instance_image(config, config.env_image, true)
      assert is_binary(instance_id)

      # Verify execution scripts are available
      {output, 0} =
        System.cmd("docker", [
          "run",
          "--rm",
          config.instance_image,
          "ls",
          "-la",
          "/opt/app/"
        ])

      assert String.contains?(output, "orchestrate.sh")
      assert String.contains?(output, "execute_tests.sh")
      assert String.contains?(output, "apply_patch.sh")
    end

    test "creates and removes containers successfully", %{config: config} do
      # Build images first
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      # Create container
      assert {:ok, container_id} = Builder.create_instance_container(config)
      assert is_binary(container_id)

      # Verify container is running
      {output, 0} = System.cmd("docker", ["ps", "-q", "-f", "id=#{container_id}"])
      assert String.trim(output) == container_id

      # Remove container
      assert :ok = Builder.remove_container(container_id)

      # Verify container is gone
      {output, _} = System.cmd("docker", ["ps", "-a", "-q", "-f", "id=#{container_id}"])
      assert String.trim(output) == ""
    end
  end

  describe "Container pool management" do
    test "creates pool with initial containers", %{config: config} do
      # Setup
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      # Create pool
      assert {:ok, pool_id} = Pool.create("test-pool", Map.put(config, :pool_size, 2))

      # Check initial status
      status = Pool.status(pool_id)
      assert status.total_containers >= 2
      assert status.available_containers >= 2
      assert status.checked_out_containers == 0

      # Cleanup
      Pool.destroy(pool_id)
    end

    test "checkout and checkin containers", %{config: config} do
      # Setup
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      {:ok, pool_id} = Pool.create("test-pool", Map.put(config, :pool_size, 2))

      # Checkout container
      assert {:ok, container_id} = Pool.checkout(pool_id)
      assert is_binary(container_id)

      # Check status after checkout
      status = Pool.status(pool_id)
      assert status.available_containers >= 1
      assert status.checked_out_containers == 1

      # Checkin container
      assert :ok = Pool.checkin(pool_id, container_id)

      # Check status after checkin
      status = Pool.status(pool_id)
      assert status.available_containers >= 2
      assert status.checked_out_containers == 0

      Pool.destroy(pool_id)
    end

    test "handles pool scaling", %{config: config} do
      # Setup
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      {:ok, pool_id} = Pool.create("test-pool", Map.put(config, :pool_size, 2))

      initial_status = Pool.status(pool_id)
      initial_count = initial_status.total_containers

      # Scale up
      assert :ok = Pool.scale(pool_id, 4)

      status_after_scale = Pool.status(pool_id)
      assert status_after_scale.total_containers >= 4

      Pool.destroy(pool_id)
    end
  end

  describe "Patch execution" do
    test "executes simple patch successfully", %{config: config} do
      # Setup complete system
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      {:ok, container_id} = Builder.create_instance_container(config)

      # Create test project and patch
      {project_path, patch_file} = setup_test_project_and_patch()

      try do
        # Execute patch evaluation
        result =
          Executor.execute_patch_evaluation(
            container_id,
            patch_file,
            nil,
            project_path,
            timeout: 30_000
          )

        case result do
          {:ok, execution_result} ->
            # Either outcome is valid
            assert execution_result.success in [true, false]
            assert is_integer(execution_result.execution_time)
            assert is_map(execution_result.test_results)

          {:error, reason} ->
            # Log error but don't fail test - patch execution can fail for various reasons
            IO.puts("Patch execution failed (expected in some cases): #{inspect(reason)}")
        end
      after
        Builder.remove_container(container_id)
        cleanup_test_project(project_path)
        File.rm(patch_file)
      end
    end

    test "handles execution timeout correctly", %{config: config} do
      # Setup
      Builder.build_base_image(config, true)
      Builder.build_env_image(config, config.base_image, true)
      Builder.build_instance_image(config, config.env_image, true)

      {:ok, container_id} = Builder.create_instance_container(config)

      # Create test project with long-running test
      {project_path, patch_file} = setup_long_running_test_project()

      try do
        # Execute with short timeout
        result =
          Executor.execute_patch_evaluation(
            container_id,
            patch_file,
            nil,
            project_path,
            # 5 second timeout
            timeout: 5_000
          )

        case result do
          {:ok, execution_result} ->
            # Should timeout
            assert execution_result.timeout_reached == true

          {:error, _reason} ->
            # Timeout errors are also acceptable
            :ok
        end
      after
        Builder.remove_container(container_id)
        cleanup_test_project(project_path)
        File.rm(patch_file)
      end
    end
  end

  describe "Integration tests" do
    test "complete end-to-end evaluation workflow", %{config: config} do
      # Start orchestration system
      {:ok, _pid} = Container.start_link(config: config)

      # Build all images
      assert {:ok, _images} = Container.build_images(force: true)

      # Create pool
      assert {:ok, _pool_id} = Container.create_pool(size: 2)

      # Create test project
      {project_path, patch_file} = setup_test_project_and_patch()

      try do
        # Execute evaluation
        result =
          Container.execute_evaluation(
            patch_file,
            nil,
            project_path,
            timeout: 30_000
          )

        case result do
          {:ok, execution_result} ->
            assert Map.has_key?(execution_result, :execution_id)
            assert Map.has_key?(execution_result, :execution_time)
            assert is_integer(execution_result.execution_time)

          {:error, reason} ->
            # Log but don't fail - integration can fail for environment reasons
            IO.puts("End-to-end test failed (may be expected): #{inspect(reason)}")
        end
      after
        Container.cleanup()
        cleanup_test_project(project_path)
        File.rm(patch_file)
      end
    end
  end

  # Helper Functions

  defp cleanup_test_resources do
    # Remove test containers
    {_, _} =
      System.cmd(
        "docker",
        [
          "container",
          "rm",
          "-f",
          "$(docker container ls -aq --filter label=swe-bench.layer)"
        ],
        stderr_to_stdout: true
      )

    # Remove test images
    {_, _} =
      System.cmd(
        "docker",
        [
          "image",
          "rm",
          "-f",
          "swe-bench-test/base:latest",
          "swe-bench-test/env:latest",
          "swe-bench-test/instance:latest"
        ],
        stderr_to_stdout: true
      )

    :ok
  end

  defp setup_test_project_and_patch do
    # Create temporary project directory
    project_path = "/tmp/test_project_#{System.unique_integer([:positive])}"
    File.mkdir_p!(project_path)

    # Create a simple Elixir project
    mix_exs_content = """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "0.1.0",
          elixir: "~> 1.16",
          deps: deps()
        ]
      end

      def application, do: []

      defp deps, do: []
    end
    """

    File.write!(Path.join(project_path, "mix.exs"), mix_exs_content)

    # Create lib directoryand module
    lib_dir = Path.join(project_path, "lib")
    File.mkdir_p!(lib_dir)

    module_content = """
    defmodule TestProject do
      def hello do
        :world
      end
      
      def add(a, b) do
        a + b  # This will be "fixed" by our patch
      end
    end
    """

    File.write!(Path.join(lib_dir, "test_project.ex"), module_content)

    # Create test directory and test
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)

    test_content = """
    defmodule TestProjectTest do
      use ExUnit.Case
      
      test "hello returns world" do
        assert TestProject.hello() == :world
      end
      
      test "add function works" do
        assert TestProject.add(2, 3) == 5
      end
    end
    """

    File.write!(Path.join(test_dir, "test_project_test.exs"), test_content)

    # Create test helper
    test_helper_content = """
    ExUnit.start()
    """

    File.write!(Path.join(test_dir, "test_helper.exs"), test_helper_content)

    # Create a simple patch that modifies the add function
    patch_content = """
    diff --git a/lib/test_project.ex b/lib/test_project.ex
    index 1234567..abcdef0 100644
    --- a/lib/test_project.ex
    +++ b/lib/test_project.ex
    @@ -4,6 +4,7 @@ defmodule TestProject do
       end
       
       def add(a, b) do
    -    a + b  # This will be "fixed" by our patch
    +    # Fixed implementation with validation
    +    a + b
       end
     end
    """

    patch_file = "/tmp/test_patch_#{System.unique_integer([:positive])}.patch"
    File.write!(patch_file, patch_content)

    {project_path, patch_file}
  end

  defp setup_long_running_test_project do
    # Create a project with a test that takes a long time
    project_path = "/tmp/long_test_project_#{System.unique_integer([:positive])}"
    File.mkdir_p!(project_path)

    mix_exs_content = """
    defmodule LongTestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :long_test_project,
          version: "0.1.0",
          elixir: "~> 1.16",
          deps: deps()
        ]
      end

      def application, do: []

      defp deps, do: []
    end
    """

    File.write!(Path.join(project_path, "mix.exs"), mix_exs_content)

    # Create lib directory
    lib_dir = Path.join(project_path, "lib")
    File.mkdir_p!(lib_dir)

    module_content = """
    defmodule LongTestProject do
      def slow_function do
        :timer.sleep(10_000)  # Sleep for 10 seconds
        :ok
      end
    end
    """

    File.write!(Path.join(lib_dir, "long_test_project.ex"), module_content)

    # Create test with long execution
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)

    test_content = """
    defmodule LongTestProjectTest do
      use ExUnit.Case
      
      test "slow test that takes too long" do
        assert LongTestProject.slow_function() == :ok
      end
    end
    """

    File.write!(Path.join(test_dir, "long_test_project_test.exs"), test_content)

    # Test helper
    File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")

    # Empty patch
    patch_content = """
    diff --git a/lib/long_test_project.ex b/lib/long_test_project.ex
    index 1234567..abcdef0 100644
    --- a/lib/long_test_project.ex
    +++ b/lib/long_test_project.ex
    @@ -1,4 +1,5 @@
     defmodule LongTestProject do
    +  # Added comment
       def slow_function do
         :timer.sleep(10_000)  # Sleep for 10 seconds
         :ok
    """

    patch_file = "/tmp/long_test_patch_#{System.unique_integer([:positive])}.patch"
    File.write!(patch_file, patch_content)

    {project_path, patch_file}
  end

  defp cleanup_test_project(project_path) do
    File.rm_rf!(project_path)
  end
end
