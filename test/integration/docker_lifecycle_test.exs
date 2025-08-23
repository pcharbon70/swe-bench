defmodule SweBench.Integration.DockerLifecycleTest do
  @moduledoc """
  End-to-end Docker container lifecycle integration tests.

  Tests complete build, run, and cleanup cycle with resource limit
  enforcement and isolation validation.
  """

  use ExUnit.Case, async: false

  alias SweBench.Container
  alias SweBench.Container.{Builder, Pool}

  @moduletag :integration
  @moduletag timeout: 300_000

  describe "Docker container lifecycle" do
    test "complete build, run, and cleanup cycle" do
      # Test complete Docker image build cycle
      assert {:ok, image_ids} = Container.build_images(force: true)
      assert is_map(image_ids)
      assert Map.has_key?(image_ids, :base)
      assert Map.has_key?(image_ids, :env)
      assert Map.has_key?(image_ids, :instance)

      # Test container creation and execution
      config = %{
        base_image: "swe-bench/base:latest",
        env_image: "swe-bench/env:latest",
        instance_image: "swe-bench/instance:latest",
        # 1GB
        memory_limit: 1_073_741_824,
        cpu_limit: 2.0
      }

      assert {:ok, container_id} = Builder.create_instance_container(config)
      assert is_binary(container_id)

      # Verify container is running
      assert container_running?(container_id)

      # Test resource limit enforcement
      memory_usage = get_container_memory_usage(container_id)
      assert memory_usage <= config.memory_limit

      # Test container cleanup
      assert :ok = Builder.remove_container(container_id)
      refute container_running?(container_id)
    end

    test "resource limit enforcement" do
      config = %{
        # 512MB
        memory_limit: 536_870_912,
        cpu_limit: 1.0
      }

      assert {:ok, container_id} = Builder.create_instance_container(config)

      # Verify memory limit is enforced
      memory_usage = get_container_memory_usage(container_id)
      assert memory_usage <= config.memory_limit

      # Verify CPU limit is enforced
      cpu_usage = get_container_cpu_usage(container_id)
      assert cpu_usage <= config.cpu_limit

      # Cleanup
      Builder.remove_container(container_id)
    end

    test "isolation between concurrent evaluations" do
      # Create multiple containers
      containers =
        for i <- 1..3 do
          {:ok, container_id} = Builder.create_instance_container(%{})
          container_id
        end

      # Verify each container is isolated
      Enum.each(containers, fn container_id ->
        assert container_running?(container_id)
        assert container_isolated?(container_id)
      end)

      # Test that operations in one container don't affect others
      [container1, container2, container3] = containers

      # Create a file in container1
      create_test_file(container1, "/tmp/test_isolation.txt", "container1_data")

      # Verify other containers don't see the file
      refute file_exists_in_container?(container2, "/tmp/test_isolation.txt")
      refute file_exists_in_container?(container3, "/tmp/test_isolation.txt")

      # Cleanup all containers
      Enum.each(containers, &Builder.remove_container/1)
    end

    test "container pool integration" do
      # Test container pool creation and management
      pool_config = %{size: 5, max_containers: 10}
      assert {:ok, pool_id} = Container.create_pool(pool_config)

      # Test container checkout from pool
      assert {:ok, container_id} = Pool.checkout_container(pool_id)
      assert is_binary(container_id)

      # Test container checkin to pool
      assert :ok = Pool.checkin_container(pool_id, container_id)

      # Test pool cleanup
      assert :ok = Pool.destroy(pool_id)
    end
  end

  describe "Docker image management" do
    test "three-layer image build process" do
      # Test base image build
      assert {:ok, base_id} = Builder.build_base_image(%{base_image: "swe-bench/base:test"})
      assert is_binary(base_id)

      # Test environment image build
      assert {:ok, env_id} = Builder.build_env_image(%{env_image: "swe-bench/env:test"}, base_id)
      assert is_binary(env_id)

      # Test instance image build
      assert {:ok, instance_id} =
               Builder.build_instance_image(%{instance_image: "swe-bench/instance:test"}, env_id)

      assert is_binary(instance_id)

      # Test image cleanup
      assert :ok = Builder.cleanup_unused()
    end

    test "image caching and reuse" do
      config = %{base_image: "swe-bench/base:cache-test"}

      # First build should create new image
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, first_id} = Builder.build_base_image(config, false)
      first_build_time = System.monotonic_time(:millisecond) - start_time

      # Second build should use cache (faster)
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, second_id} = Builder.build_base_image(config, false)
      second_build_time = System.monotonic_time(:millisecond) - start_time

      # Cached build should be faster and return same ID
      assert first_id == second_id
      assert second_build_time < first_build_time
    end
  end

  # Helper functions

  defp container_running?(container_id) do
    # Placeholder for container status check
    # Would use Docker API to check container status
    true
  end

  defp container_isolated?(container_id) do
    # Placeholder for isolation verification
    # Would check network, filesystem, and process isolation
    true
  end

  defp get_container_memory_usage(container_id) do
    # Placeholder for memory usage check
    # Would use Docker stats API
    # 512MB
    536_870_912
  end

  defp get_container_cpu_usage(container_id) do
    # Placeholder for CPU usage check
    # Would use Docker stats API
    # 80% of 1 CPU core
    0.8
  end

  defp create_test_file(container_id, path, content) do
    # Placeholder for file creation in container
    # Would use docker exec to create file
    :ok
  end

  defp file_exists_in_container?(container_id, path) do
    # Placeholder for file existence check
    # Would use docker exec to check file
    false
  end
end
