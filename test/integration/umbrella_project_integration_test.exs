defmodule SweBench.Integration.UmbrellaProjectIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :umbrella_project

  alias SweBench.MixProject

  alias SweBench.MixProject.{
    UmbrellaDetector,
    UmbrellaOrchestrator,
    UmbrellaPatchDistributor,
    UmbrellaTestCoordinator
  }

  @test_timeout 45_000

  describe "complete umbrella project evaluation pipeline" do
    @tag timeout: @test_timeout
    test "end-to-end umbrella project detection and analysis" do
      # Create mock umbrella project structure
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        # Test umbrella detection
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        assert detection_result.is_umbrella
        assert length(detection_result.apps) == 3
        assert detection_result.has_root_mix_file

        # Validate app detection
        app_names = Enum.map(detection_result.apps, & &1.name)
        assert "core_app" in app_names
        assert "web_app" in app_names
        assert "worker_app" in app_names

        # Test dependency analysis
        assert Map.has_key?(detection_result, :dependencies)
        assert Map.has_key?(detection_result.dependencies, :shared)
        assert Map.has_key?(detection_result.dependencies, :inter_app)

        # Test compilation orchestration
        {:ok, compilation_plan} = UmbrellaOrchestrator.create_compilation_plan(detection_result)

        assert is_list(compilation_plan.build_order)
        assert length(compilation_plan.build_order) == 3
        assert compilation_plan.has_circular_dependencies == false

        # Verify proper dependency ordering
        build_order_names = Enum.map(compilation_plan.build_order, & &1.name)
        core_index = Enum.find_index(build_order_names, &(&1 == "core_app"))
        web_index = Enum.find_index(build_order_names, &(&1 == "web_app"))

        # Core app should be built before web app (since web depends on core)
        assert core_index < web_index
      after
        cleanup_temp_directory(temp_dir)
      end
    end

    @tag timeout: @test_timeout
    test "multi-application compilation coordination" do
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)
        {:ok, compilation_plan} = UmbrellaOrchestrator.create_compilation_plan(detection_result)

        # Test compilation execution
        {:ok, compilation_result} =
          UmbrellaOrchestrator.execute_compilation(
            temp_dir,
            compilation_plan
          )

        assert compilation_result.success
        assert length(compilation_result.compiled_apps) == 3
        assert compilation_result.total_compilation_time > 0

        # Validate individual app compilation
        Enum.each(compilation_result.compiled_apps, fn app_result ->
          assert app_result.success
          assert app_result.compilation_time > 0
          assert is_list(app_result.warnings)
          assert is_list(app_result.errors)
        end)

        # Test shared dependency handling
        assert Map.has_key?(compilation_result, :shared_dependencies)
        assert compilation_result.shared_dependencies.resolved_successfully
      after
        cleanup_temp_directory(temp_dir)
      end
    end

    @tag timeout: @test_timeout
    test "cross-application test execution and coordination" do
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        # Setup test coordination
        {:ok, test_plan} = UmbrellaTestCoordinator.create_test_plan(detection_result)

        assert is_list(test_plan.app_test_configs)
        assert length(test_plan.app_test_configs) == 3
        assert test_plan.has_shared_test_helpers
        assert is_map(test_plan.test_dependencies)

        # Execute coordinated tests
        {:ok, test_results} = UmbrellaTestCoordinator.execute_tests(temp_dir, test_plan)

        assert is_map(test_results)
        assert Map.has_key?(test_results, :overall_success)
        assert Map.has_key?(test_results, :app_results)
        assert Map.has_key?(test_results, :total_tests)
        assert Map.has_key?(test_results, :total_failures)

        # Validate per-app test results
        Enum.each(test_results.app_results, fn {app_name, app_result} ->
          assert is_binary(app_name)
          assert Map.has_key?(app_result, :tests_run)
          assert Map.has_key?(app_result, :failures)
          assert Map.has_key?(app_result, :test_time)
          assert is_number(app_result.tests_run)
          assert is_number(app_result.failures)
          assert is_number(app_result.test_time)
        end)

        # Test aggregated results
        total_tests =
          Map.values(test_results.app_results)
          |> Enum.map(& &1.tests_run)
          |> Enum.sum()

        assert test_results.total_tests == total_tests
      after
        cleanup_temp_directory(temp_dir)
      end
    end
  end

  describe "cross-application patch distribution and analysis" do
    @tag timeout: @test_timeout
    test "patch distribution across umbrella applications" do
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        # Create mock patches affecting multiple apps
        patches = [
          %{
            file_path: "apps/core_app/lib/core_app/server.ex",
            changes: "+  def new_function, do: :ok\n",
            type: :addition
          },
          %{
            file_path: "apps/web_app/lib/web_app/controller.ex",
            changes:
              "+  alias CoreApp.Server\n+  def use_core_function, do: Server.new_function()\n",
            type: :addition
          },
          %{
            file_path: "mix.exs",
            changes: "+    # Updated dependency version\n",
            type: :modification
          }
        ]

        # Test patch distribution
        {:ok, distribution_result} =
          UmbrellaPatchDistributor.distribute_patches(
            temp_dir,
            patches,
            detection_result
          )

        assert distribution_result.patches_applied
        assert Map.has_key?(distribution_result, :affected_apps)
        assert Map.has_key?(distribution_result, :cross_app_dependencies)

        # Validate affected apps identification
        affected_app_names = Enum.map(distribution_result.affected_apps, & &1.name)
        assert "core_app" in affected_app_names
        assert "web_app" in affected_app_names

        # Test cross-app dependency tracking
        assert length(distribution_result.cross_app_dependencies) > 0

        # Test consistency validation
        {:ok, consistency_result} =
          UmbrellaPatchDistributor.validate_consistency(
            temp_dir,
            distribution_result
          )

        assert consistency_result.consistent
        assert is_list(consistency_result.warnings)
        assert is_list(consistency_result.potential_issues)
      after
        cleanup_temp_directory(temp_dir)
      end
    end

    @tag timeout: @test_timeout
    test "configuration inheritance and management" do
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        # Test configuration analysis
        {:ok, config_analysis} =
          UmbrellaOrchestrator.analyze_configuration(
            temp_dir,
            detection_result
          )

        assert Map.has_key?(config_analysis, :root_config)
        assert Map.has_key?(config_analysis, :app_configs)
        assert Map.has_key?(config_analysis, :shared_config)
        assert Map.has_key?(config_analysis, :config_conflicts)

        # Validate configuration inheritance
        assert is_map(config_analysis.shared_config)
        assert length(config_analysis.app_configs) == 3

        # Test configuration override detection
        Enum.each(config_analysis.app_configs, fn {app_name, app_config} ->
          assert is_binary(app_name)
          assert Map.has_key?(app_config, :config_file_path)
          assert Map.has_key?(app_config, :overrides_root)
          assert Map.has_key?(app_config, :app_specific_config)
        end)

        # Check for configuration conflicts
        if length(config_analysis.config_conflicts) > 0 do
          Enum.each(config_analysis.config_conflicts, fn conflict ->
            assert Map.has_key?(conflict, :config_key)
            assert Map.has_key?(conflict, :conflicting_apps)
            assert Map.has_key?(conflict, :severity)
          end)
        end
      after
        cleanup_temp_directory(temp_dir)
      end
    end
  end

  describe "release building and deployment coordination" do
    @tag timeout: @test_timeout
    test "umbrella release configuration analysis" do
      umbrella_structure = create_mock_umbrella_structure_with_releases()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        # Test release configuration detection
        {:ok, release_analysis} =
          UmbrellaOrchestrator.analyze_release_config(
            temp_dir,
            detection_result
          )

        assert Map.has_key?(release_analysis, :has_releases)
        assert Map.has_key?(release_analysis, :release_configs)
        assert Map.has_key?(release_analysis, :included_apps)

        if release_analysis.has_releases do
          assert length(release_analysis.release_configs) > 0

          # Validate release configuration details
          Enum.each(release_analysis.release_configs, fn release_config ->
            assert Map.has_key?(release_config, :name)
            assert Map.has_key?(release_config, :included_applications)
            assert Map.has_key?(release_config, :version)
            assert is_list(release_config.included_applications)
          end)
        end
      after
        cleanup_temp_directory(temp_dir)
      end
    end
  end

  describe "performance and resource management" do
    @tag timeout: @test_timeout
    test "umbrella project analysis performance within targets" do
      # Create larger umbrella structure for performance testing
      large_umbrella_structure = create_large_umbrella_structure(10)
      temp_dir = setup_temp_umbrella_project(large_umbrella_structure)

      try do
        # Time the complete umbrella analysis
        {time_microseconds, {:ok, results}} =
          :timer.tc(fn ->
            with {:ok, detection_result} <- UmbrellaDetector.detect_structure(temp_dir),
                 {:ok, compilation_plan} <-
                   UmbrellaOrchestrator.create_compilation_plan(detection_result),
                 {:ok, test_plan} <- UmbrellaTestCoordinator.create_test_plan(detection_result) do
              {:ok,
               %{
                 detection: detection_result,
                 compilation: compilation_plan,
                 testing: test_plan
               }}
            end
          end)

        # Should complete umbrella analysis within reasonable time (10 apps)
        # 15 seconds
        assert time_microseconds < 15_000_000
        assert Map.has_key?(results, :detection)
        assert Map.has_key?(results, :compilation)
        assert Map.has_key?(results, :testing)

        # Validate that all apps were processed
        assert length(results.detection.apps) == 10
        assert length(results.compilation.build_order) == 10
        assert length(results.testing.app_test_configs) == 10
      after
        cleanup_temp_directory(temp_dir)
      end
    end

    @tag timeout: @test_timeout
    test "memory usage during umbrella project analysis" do
      umbrella_structure = create_mock_umbrella_structure()
      temp_dir = setup_temp_umbrella_project(umbrella_structure)

      try do
        # Monitor memory usage during analysis
        initial_memory = :erlang.memory(:total)

        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)
        {:ok, compilation_plan} = UmbrellaOrchestrator.create_compilation_plan(detection_result)
        {:ok, test_plan} = UmbrellaTestCoordinator.create_test_plan(detection_result)

        final_memory = :erlang.memory(:total)
        memory_used = final_memory - initial_memory

        # Memory usage should be reasonable (less than 100MB for 3 apps)
        assert memory_used < 100 * 1024 * 1024

        # Validate analysis quality wasn't compromised
        assert detection_result.is_umbrella
        assert length(compilation_plan.build_order) == 3
        assert length(test_plan.app_test_configs) == 3
      after
        cleanup_temp_directory(temp_dir)
      end
    end
  end

  describe "error handling and edge cases" do
    @tag timeout: @test_timeout
    test "handles malformed umbrella projects gracefully" do
      # Create umbrella with missing mix files
      malformed_structure = %{
        root_mix_exs: """
        defmodule MyUmbrella.MixProject do
          use Mix.Project
          def project do
            [app: :my_umbrella, version: "0.1.0"]
          end
        end
        """,
        apps: [
          %{name: "missing_mix_app", path: "apps/missing_mix_app", has_mix_file: false}
        ]
      }

      temp_dir = setup_temp_umbrella_project(malformed_structure)

      try do
        case UmbrellaDetector.detect_structure(temp_dir) do
          {:ok, detection_result} ->
            # Should detect issues
            refute detection_result.is_umbrella
            assert length(detection_result.errors) > 0

          {:error, reason} ->
            # Also acceptable - detection failure
            assert is_atom(reason)
        end
      after
        cleanup_temp_directory(temp_dir)
      end
    end

    @tag timeout: @test_timeout
    test "handles circular dependencies in umbrella projects" do
      # Create umbrella with circular dependencies
      circular_structure = create_circular_dependency_umbrella()
      temp_dir = setup_temp_umbrella_project(circular_structure)

      try do
        {:ok, detection_result} = UmbrellaDetector.detect_structure(temp_dir)

        case UmbrellaOrchestrator.create_compilation_plan(detection_result) do
          {:ok, compilation_plan} ->
            # Should detect circular dependencies
            assert compilation_plan.has_circular_dependencies
            assert length(compilation_plan.circular_dependency_cycles) > 0

          {:error, :circular_dependencies} ->
            # Also acceptable - explicit error for circular deps
            assert true
        end
      after
        cleanup_temp_directory(temp_dir)
      end
    end
  end

  # Helper functions for test setup

  defp create_mock_umbrella_structure do
    %{
      root_mix_exs: """
      defmodule MyUmbrella.MixProject do
        use Mix.Project
        
        def project do
          [
            apps_path: "apps",
            version: "0.1.0",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end
        
        defp deps do
          [{:jason, "~> 1.0"}]
        end
      end
      """,
      apps: [
        %{
          name: "core_app",
          path: "apps/core_app",
          mix_exs: """
          defmodule CoreApp.MixProject do
            use Mix.Project
            
            def project do
              [app: :core_app, version: "0.1.0", deps: deps()]
            end
            
            defp deps do
              [{:ecto, "~> 3.0"}]
            end
          end
          """,
          lib_files: [
            {"lib/core_app.ex", "defmodule CoreApp do\n  def hello, do: :world\nend"},
            {"lib/core_app/server.ex", "defmodule CoreApp.Server do\n  def start, do: :ok\nend"}
          ]
        },
        %{
          name: "web_app",
          path: "apps/web_app",
          mix_exs: """
          defmodule WebApp.MixProject do
            use Mix.Project
            
            def project do
              [app: :web_app, version: "0.1.0", deps: deps()]
            end
            
            defp deps do
              [{:core_app, in_umbrella: true}, {:plug, "~> 1.0"}]
            end
          end
          """,
          lib_files: [
            {"lib/web_app.ex", "defmodule WebApp do\n  def start, do: :ok\nend"},
            {"lib/web_app/controller.ex",
             "defmodule WebApp.Controller do\n  def index, do: :ok\nend"}
          ]
        },
        %{
          name: "worker_app",
          path: "apps/worker_app",
          mix_exs: """
          defmodule WorkerApp.MixProject do
            use Mix.Project
            
            def project do
              [app: :worker_app, version: "0.1.0", deps: deps()]
            end
            
            defp deps do
              [{:core_app, in_umbrella: true}]
            end
          end
          """,
          lib_files: [
            {"lib/worker_app.ex", "defmodule WorkerApp do\n  def work, do: :done\nend"}
          ]
        }
      ]
    }
  end

  defp create_mock_umbrella_structure_with_releases do
    structure = create_mock_umbrella_structure()

    updated_root_mix =
      structure.root_mix_exs <>
        """

        def releases do
          [
            my_umbrella: [
              applications: [core_app: :permanent, web_app: :permanent, worker_app: :permanent]
            ]
          ]
        end
        """

    %{structure | root_mix_exs: updated_root_mix}
  end

  defp create_large_umbrella_structure(app_count) do
    apps =
      Enum.map(1..app_count, fn i ->
        deps = if i > 1, do: "[{:app_#{i - 1}, in_umbrella: true}]", else: "[]"

        %{
          name: "app_#{i}",
          path: "apps/app_#{i}",
          mix_exs: """
          defmodule App#{i}.MixProject do
            use Mix.Project
            
            def project do
              [app: :app_#{i}, version: "0.1.0", deps: deps()]
            end
            
            defp deps do
              #{deps}
            end
          end
          """,
          lib_files: [
            {"lib/app_#{i}.ex", "defmodule App#{i} do\n  def function_#{i}, do: :ok\nend"}
          ]
        }
      end)

    %{
      root_mix_exs: """
      defmodule LargeUmbrella.MixProject do
        use Mix.Project
        
        def project do
          [
            apps_path: "apps",
            version: "0.1.0",
            start_permanent: Mix.env() == :prod
          ]
        end
      end
      """,
      apps: apps
    }
  end

  defp create_circular_dependency_umbrella do
    %{
      root_mix_exs: """
      defmodule CircularUmbrella.MixProject do
        use Mix.Project
        
        def project do
          [
            apps_path: "apps", 
            version: "0.1.0"
          ]
        end
      end
      """,
      apps: [
        %{
          name: "app_a",
          path: "apps/app_a",
          mix_exs: """
          defmodule AppA.MixProject do
            use Mix.Project
            def project do
              [app: :app_a, version: "0.1.0", deps: [{:app_b, in_umbrella: true}]]
            end
          end
          """,
          lib_files: [{"lib/app_a.ex", "defmodule AppA, do: def hello, do: :a"}]
        },
        %{
          name: "app_b",
          path: "apps/app_b",
          mix_exs: """
          defmodule AppB.MixProject do
            use Mix.Project
            def project do
              [app: :app_b, version: "0.1.0", deps: [{:app_a, in_umbrella: true}]]
            end
          end
          """,
          lib_files: [{"lib/app_b.ex", "defmodule AppB, do: def hello, do: :b"}]
        }
      ]
    }
  end

  defp setup_temp_umbrella_project(structure) do
    temp_dir = System.tmp_dir!() |> Path.join("umbrella_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(temp_dir)

    # Create root mix.exs
    File.write!(Path.join(temp_dir, "mix.exs"), structure.root_mix_exs)

    # Create apps directory
    apps_dir = Path.join(temp_dir, "apps")
    File.mkdir_p!(apps_dir)

    # Create each app
    Enum.each(structure.apps, fn app ->
      app_dir = Path.join(temp_dir, app.path)
      File.mkdir_p!(app_dir)

      # Create app's mix.exs (if specified)
      if Map.get(app, :has_mix_file, true) do
        File.write!(Path.join(app_dir, "mix.exs"), app.mix_exs)
      end

      # Create lib directory and files
      if Map.has_key?(app, :lib_files) do
        create_app_lib_files(app_dir, app.lib_files)
      end

      # Create test directory
      test_dir = Path.join(app_dir, "test")
      File.mkdir_p!(test_dir)
      File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")
    end)

    temp_dir
  end

  defp create_app_lib_files(app_dir, lib_files) do
    lib_dir = Path.join(app_dir, "lib")
    File.mkdir_p!(lib_dir)

    Enum.each(lib_files, fn {file_path, content} ->
      full_path = Path.join(app_dir, file_path)
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(full_path, content)
    end)
  end

  defp cleanup_temp_directory(temp_dir) do
    File.rm_rf!(temp_dir)
  end
end
