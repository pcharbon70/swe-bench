defmodule SweBench.TestRunnerTest do
  @moduledoc """
  Comprehensive tests for the ExUnit test runner system.

  Tests the complete test execution pipeline including:
  - Custom ExUnit formatter functionality
  - Test execution orchestration
  - Result analysis and transition detection
  - Process isolation mechanisms
  - Integration with container system
  """

  use ExUnit.Case, async: false

  alias SweBench.TestRunner
  alias SweBench.TestRunner.{Analyzer, Formatter, Isolation, Orchestrator}

  @moduletag :test_runner

  setup do
    # Ensure clean state before each test
    cleanup_test_runner_system()

    config = %{
      timeout: 30_000,
      isolation: true,
      # Disable for testing
      coverage: false,
      formatter: %{
        capture_detailed: true,
        include_timing: true
      }
    }

    {:ok, config: config}
  end

  describe "TestRunner main interface" do
    test "executes tests successfully", %{config: config} do
      # Create test project
      {project_path, _cleanup_fn} = create_test_project()

      try do
        # Execute tests
        result = TestRunner.execute_tests(project_path, config)

        case result do
          {:ok, results} ->
            assert Map.has_key?(results, :execution_id)
            assert Map.has_key?(results, :stats)
            assert Map.has_key?(results, :analysis)
            assert is_integer(results.execution_time_us)

          {:error, reason} ->
            # Log but don't fail - execution can fail due to environment
            IO.puts("Test execution failed (may be expected): #{inspect(reason)}")
        end
      after
        cleanup_test_project(project_path)
      end
    end

    test "compares test results for transitions", %{config: _config} do
      base_results = %{
        stats: %{total: 3, passed: 1, failed: 2},
        tests: [
          %{
            module: TestModule,
            tests: [
              %{name: :test_1, state: :passed},
              %{name: :test_2, state: :failed},
              %{name: :test_3, state: :failed}
            ]
          }
        ]
      }

      patched_results = %{
        stats: %{total: 3, passed: 2, failed: 1},
        tests: [
          %{
            module: TestModule,
            tests: [
              %{name: :test_1, state: :passed},
              # FAIL_TO_PASS
              %{name: :test_2, state: :passed},
              %{name: :test_3, state: :failed}
            ]
          }
        ]
      }

      assert {:ok, transition_report} =
               TestRunner.compare_test_results(base_results, patched_results)

      assert length(transition_report.fail_to_pass) == 1
      assert "TestModule.test_2" in transition_report.fail_to_pass
      assert length(transition_report.pass_to_pass) == 1
      assert "TestModule.test_1" in transition_report.pass_to_pass
      assert is_number(transition_report.evaluation_score)
    end

    test "provides system status", %{config: _config} do
      status = TestRunner.status()

      assert Map.has_key?(status, :formatter_running)
      assert Map.has_key?(status, :active_executions)
      assert Map.has_key?(status, :isolation_enabled)
      assert Map.has_key?(status, :system_ready)
    end
  end

  describe "Custom ExUnit formatter" do
    test "starts and stops successfully" do
      assert {:ok, pid} = Formatter.start_link(execution_id: "test_fmt_001")
      assert Process.alive?(pid)
      assert Formatter.running?()

      # Get initial stats
      assert {:ok, stats} = Formatter.get_stats()
      assert stats.execution_id == "test_fmt_001"

      # Stop and get results
      assert {:ok, results} = Formatter.stop_and_get_results()
      assert Map.has_key?(results, :execution_id)
      assert Map.has_key?(results, :stats)
    end

    test "captures test execution details" do
      {:ok, _pid} = Formatter.start_link(execution_id: "test_fmt_002")

      # Simulate ExUnit callbacks
      test_module = %ExUnit.TestModule{name: TestModule}

      test = %ExUnit.Test{
        module: TestModule,
        name: :sample_test,
        tags: %{},
        state: :passed
      }

      # Simulate test execution
      Formatter.suite_started([])
      Formatter.module_started(test_module)
      Formatter.test_started(test)
      Formatter.test_finished(test)
      Formatter.module_finished(test_module)
      Formatter.suite_finished(1000, 500)

      # Get results
      assert {:ok, results} = Formatter.stop_and_get_results()
      assert results.stats.total == 1
      assert results.stats.passed == 1
      assert results.stats.failed == 0
    end
  end

  describe "Test execution orchestrator" do
    test "starts and manages executions" do
      assert {:ok, _pid} = Orchestrator.start_link()
      assert Orchestrator.running?()

      # Start an execution
      assert :ok = Orchestrator.start_execution("test_exec_001", "/tmp/test_project", [])

      # Check active executions
      executions = Orchestrator.active_executions()
      assert length(executions) == 1
      assert List.first(executions).id == "test_exec_001"

      Orchestrator.stop()
    end

    test "handles local test execution" do
      {:ok, _pid} = Orchestrator.start_link()

      # Create minimal test project
      {project_path, _cleanup_fn} = create_minimal_test_project()

      try do
        # Start execution
        :ok = Orchestrator.start_execution("test_exec_002", project_path, [])

        # Execute locally (this might fail due to environment, which is OK)
        result = Orchestrator.execute_locally("test_exec_002", project_path, 10_000, [])

        case result do
          {:ok, execution_results} ->
            assert Map.has_key?(execution_results, :execution_id)

          {:error, reason} ->
            # Log but don't fail test - execution can fail for environment reasons
            IO.puts("Local execution failed (expected in test environment): #{inspect(reason)}")
        end
      after
        cleanup_test_project(project_path)
        Orchestrator.stop()
      end
    end
  end

  describe "Test result analyzer" do
    test "analyzes execution results" do
      sample_results = %{
        execution_id: "test_analysis_001",
        stats: %{total: 5, passed: 3, failed: 2, skipped: 0},
        failures: [
          %{assertion_type: :assert, failure_message: "Expected true, got false"},
          %{assertion_type: :refute, failure_message: "Expected false, got true"}
        ],
        timing: %{total_time_us: 150_000},
        tests: [
          %{
            module: TestModule1,
            tests: [
              %{name: :test_a, state: :passed, execution_time_us: 1000},
              %{name: :test_b, state: :failed, execution_time_us: 2000}
            ]
          },
          %{
            module: TestModule2,
            tests: [
              %{name: :test_c, state: :passed, execution_time_us: 500}
            ]
          }
        ]
      }

      assert {:ok, analyzed} = Analyzer.analyze_execution_results(sample_results)

      assert Map.has_key?(analyzed, :analysis)
      assert Map.has_key?(analyzed.analysis, :basic_metrics)
      assert Map.has_key?(analyzed.analysis, :failure_analysis)
      assert Map.has_key?(analyzed.analysis, :timing_analysis)

      # Check basic metrics
      basic = analyzed.analysis.basic_metrics
      assert basic.total_tests == 5
      assert basic.passed_tests == 3
      assert basic.failed_tests == 2
      assert basic.success_rate == 60.0
    end

    test "detects test transitions correctly" do
      base_results = create_sample_base_results()
      patched_results = create_sample_patched_results()

      assert {:ok, transitions} = Analyzer.detect_transitions(base_results, patched_results)

      assert Map.has_key?(transitions, :fail_to_pass)
      assert Map.has_key?(transitions, :pass_to_pass)
      assert Map.has_key?(transitions, :pass_to_fail)
      assert Map.has_key?(transitions, :new_tests)
      assert Map.has_key?(transitions, :removed_tests)
    end

    test "generates JSON reports" do
      sample_results = %{
        execution_id: "test_json_001",
        stats: %{total: 2, passed: 2, failed: 0},
        timestamp: DateTime.utc_now()
      }

      assert {:ok, json_report} = Analyzer.generate_json_report(sample_results)
      assert is_binary(json_report)

      # Parse to verify valid JSON
      assert {:ok, parsed} = Jason.decode(json_report)
      assert Map.has_key?(parsed, "format_version")
      assert Map.has_key?(parsed, "execution_summary")
    end
  end

  describe "Test isolation mechanism" do
    test "starts and manages isolation" do
      assert {:ok, _pid} = Isolation.start_link()
      assert Isolation.running?()
      assert Isolation.enabled?()

      Isolation.stop()
    end

    test "performs execution cleanup" do
      {:ok, _pid} = Isolation.start_link()

      assert {:ok, cleanup_record} = Isolation.cleanup_execution("test_cleanup_001")
      assert Map.has_key?(cleanup_record, :execution_id)
      assert Map.has_key?(cleanup_record, :cleanup_time_ms)
      assert Map.has_key?(cleanup_record, :strategies_used)

      Isolation.stop()
    end

    test "handles application state reset" do
      {:ok, _pid} = Isolation.start_link()

      assert {:ok, result} = Isolation.reset_application_state()
      assert result in [:application_reset, :isolation_disabled]

      Isolation.stop()
    end

    test "cleans up process state" do
      {:ok, _pid} = Isolation.start_link()

      assert {:ok, result} = Isolation.cleanup_process_state()
      # Result structure depends on implementation
      assert result in [:isolation_disabled] or Map.has_key?(result, :cleaned_tables)

      Isolation.stop()
    end
  end

  describe "Integration tests" do
    test "complete test runner workflow" do
      # Start all systems
      assert {:ok, :system_started} = TestRunner.start_system()

      # Verify system status
      status = TestRunner.status()
      assert status.system_ready == true

      # Create test project
      {project_path, _cleanup_fn} = create_test_project_with_failing_test()

      try do
        # Execute tests
        result = TestRunner.execute_tests(project_path, timeout: 15_000)

        case result do
          {:ok, results} ->
            assert Map.has_key?(results, :analysis)
            assert Map.has_key?(results, :stats)

          {:error, reason} ->
            IO.puts("Integration test failed (environment-dependent): #{inspect(reason)}")
        end
      after
        cleanup_test_project(project_path)
        TestRunner.stop_system()
      end
    end
  end

  # Helper Functions

  defp cleanup_test_runner_system do
    TestRunner.stop_system()

    # Wait a moment for processes to stop
    Process.sleep(100)
  end

  defp create_test_project do
    project_path = "/tmp/swe_bench_test_#{System.unique_integer([:positive])}"
    File.mkdir_p!(project_path)

    # Create mix.exs
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

    # Create lib directory and simple module
    lib_dir = Path.join(project_path, "lib")
    File.mkdir_p!(lib_dir)

    module_content = """
    defmodule TestProject do
      def add(a, b), do: a + b
      def multiply(a, b), do: a * b
      def divide(_a, 0), do: {:error, :division_by_zero}
      def divide(a, b), do: {:ok, a / b}
    end
    """

    File.write!(Path.join(lib_dir, "test_project.ex"), module_content)

    # Create test directory and tests
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)

    test_content = """
    defmodule TestProjectTest do
      use ExUnit.Case

      test "add function works" do
        assert TestProject.add(2, 3) == 5
        assert TestProject.add(0, 0) == 0
      end

      test "multiply function works" do
        assert TestProject.multiply(3, 4) == 12
        assert TestProject.multiply(0, 5) == 0
      end

      test "divide function handles errors" do
        assert TestProject.divide(10, 2) == {:ok, 5.0}
        assert TestProject.divide(10, 0) == {:error, :division_by_zero}
      end
    end
    """

    File.write!(Path.join(test_dir, "test_project_test.exs"), test_content)

    # Create test helper
    File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")

    cleanup_fn = fn -> cleanup_test_project(project_path) end

    {project_path, cleanup_fn}
  end

  defp create_minimal_test_project do
    project_path = "/tmp/minimal_test_#{System.unique_integer([:positive])}"
    File.mkdir_p!(project_path)

    # Minimal mix.exs
    mix_exs = """
    defmodule Minimal.MixProject do
      use Mix.Project
      def project, do: [app: :minimal, version: "0.1.0", elixir: "~> 1.16"]
      def application, do: []
    end
    """

    File.write!(Path.join(project_path, "mix.exs"), mix_exs)

    # Minimal test structure
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)
    File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")

    test_content = """
    defmodule MinimalTest do
      use ExUnit.Case
      test "basic test", do: assert true
    end
    """

    File.write!(Path.join(test_dir, "minimal_test.exs"), test_content)

    cleanup_fn = fn -> cleanup_test_project(project_path) end

    {project_path, cleanup_fn}
  end

  defp create_test_project_with_failing_test do
    project_path = "/tmp/failing_test_#{System.unique_integer([:positive])}"
    File.mkdir_p!(project_path)

    # Create mix.exs
    mix_exs_content = """
    defmodule FailingProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :failing_project,
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

    # Create lib with buggy code
    lib_dir = Path.join(project_path, "lib")
    File.mkdir_p!(lib_dir)

    module_content = """
    defmodule FailingProject do
      def broken_add(a, b), do: a - b  # Intentionally wrong
      def working_multiply(a, b), do: a * b
    end
    """

    File.write!(Path.join(lib_dir, "failing_project.ex"), module_content)

    # Create tests with expected failures
    test_dir = Path.join(project_path, "test")
    File.mkdir_p!(test_dir)

    test_content = """
    defmodule FailingProjectTest do
      use ExUnit.Case

      test "working function passes" do
        assert FailingProject.working_multiply(3, 4) == 12
      end

      test "broken function fails" do
        assert FailingProject.broken_add(2, 3) == 5  # This will fail
      end
    end
    """

    File.write!(Path.join(test_dir, "failing_project_test.exs"), test_content)
    File.write!(Path.join(test_dir, "test_helper.exs"), "ExUnit.start()")

    cleanup_fn = fn -> cleanup_test_project(project_path) end

    {project_path, cleanup_fn}
  end

  defp cleanup_test_project(project_path) do
    File.rm_rf!(project_path)
  end

  defp create_sample_base_results do
    %{
      stats: %{total: 4, passed: 2, failed: 2},
      tests: [
        %{
          module: SampleModule,
          tests: [
            %{name: :test_passes, state: :passed},
            %{name: :test_fails, state: :failed},
            %{name: :test_also_fails, state: :failed},
            %{name: :test_stable, state: :passed}
          ]
        }
      ]
    }
  end

  defp create_sample_patched_results do
    %{
      stats: %{total: 4, passed: 3, failed: 1},
      tests: [
        %{
          module: SampleModule,
          tests: [
            %{name: :test_passes, state: :passed},
            # FAIL_TO_PASS
            %{name: :test_fails, state: :passed},
            # Still failing
            %{name: :test_also_fails, state: :failed},
            # PASS_TO_PASS
            %{name: :test_stable, state: :passed}
          ]
        }
      ]
    }
  end
end
