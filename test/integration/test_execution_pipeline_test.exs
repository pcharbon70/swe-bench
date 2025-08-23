defmodule SweBench.Integration.TestExecutionPipelineTest do
  @moduledoc """
  Complete test execution pipeline integration tests.

  Tests patch application, compilation, test execution, and result
  analysis with FAIL_TO_PASS transition detection.
  """

  use ExUnit.Case, async: false

  alias SweBench.Container.Executor
  alias SweBench.TestRunner
  alias SweBench.TestRunner.{Analyzer, Formatter, Orchestrator}

  @moduletag :integration
  @moduletag timeout: 600_000

  describe "test execution pipeline" do
    test "patch application and compilation" do
      # Create a test patch
      patch_content = """
      diff --git a/lib/example.ex b/lib/example.ex
      index 1234567..abcdefg 100644
      --- a/lib/example.ex
      +++ b/lib/example.ex
      @@ -1,3 +1,6 @@
       defmodule Example do
      +  def new_function do
      +    :fixed
      +  end
      end
      """

      patch_file = create_temporary_patch_file(patch_content)
      project_path = create_test_project()

      # Test patch application
      assert {:ok, container_id} = setup_test_container()
      assert {:ok, _result} = Executor.apply_patch(container_id, patch_file, "main", project_path)

      # Test compilation after patch
      assert {:ok, compilation_result} = Executor.compile_project(container_id, project_path)
      assert compilation_result.status == :success

      # Cleanup
      cleanup_test_resources(container_id, patch_file, project_path)
    end

    test "test result capture and analysis" do
      project_path = create_test_project_with_tests()

      # Execute tests and capture results
      assert {:ok, container_id} = setup_test_container()
      assert {:ok, test_results} = TestRunner.execute_tests(container_id, project_path)

      # Verify result structure
      assert Map.has_key?(test_results, :summary)
      assert Map.has_key?(test_results, :individual_tests)
      assert Map.has_key?(test_results, :execution_time)

      # Test result analysis
      assert {:ok, analysis} = Analyzer.analyze_test_results(test_results)
      assert Map.has_key?(analysis, :transition_type)
      assert Map.has_key?(analysis, :quality_score)

      cleanup_test_resources(container_id, nil, project_path)
    end

    test "FAIL_TO_PASS transition detection" do
      # Create project with failing test
      project_path = create_test_project_with_failing_test()

      # Run tests before patch (should fail)
      assert {:ok, container_id} = setup_test_container()
      assert {:ok, before_results} = TestRunner.execute_tests(container_id, project_path)
      assert before_results.summary.failed > 0

      # Apply fix patch
      fix_patch = create_fix_patch()
      assert {:ok, _result} = Executor.apply_patch(container_id, fix_patch, "main", project_path)

      # Run tests after patch (should pass)
      assert {:ok, after_results} = TestRunner.execute_tests(container_id, project_path)
      assert after_results.summary.failed == 0

      # Analyze transition
      assert {:ok, transition} = Analyzer.analyze_transition(before_results, after_results)
      assert transition.type == :fail_to_pass
      assert transition.affected_tests > 0

      cleanup_test_resources(container_id, fix_patch, project_path)
    end

    test "test isolation and state management" do
      project_path = create_test_project_with_state()

      # Run first test execution
      assert {:ok, container_id1} = setup_test_container()
      assert {:ok, results1} = TestRunner.execute_tests(container_id1, project_path)

      # Run second test execution in different container
      assert {:ok, container_id2} = setup_test_container()
      assert {:ok, results2} = TestRunner.execute_tests(container_id2, project_path)

      # Verify results are identical (deterministic)
      assert results1.summary.total == results2.summary.total
      assert results1.summary.passed == results2.summary.passed
      assert results1.summary.failed == results2.summary.failed

      # Verify no state contamination between executions
      assert results_are_deterministic?(results1, results2)

      cleanup_test_resources(container_id1, nil, project_path)
      cleanup_test_resources(container_id2, nil, project_path)
    end
  end

  describe "test formatter integration" do
    test "custom formatter output capture" do
      project_path = create_test_project_with_varied_tests()

      assert {:ok, container_id} = setup_test_container()

      # Configure custom formatter
      formatter_config = %{
        capture_details: true,
        include_timing: true,
        include_stacktraces: true
      }

      assert {:ok, results} =
               TestRunner.execute_tests(container_id, project_path, formatter: formatter_config)

      # Verify formatter captured detailed information
      assert Map.has_key?(results, :individual_tests)
      assert length(results.individual_tests) > 0

      # Check that each test has required details
      Enum.each(results.individual_tests, fn test ->
        assert Map.has_key?(test, :module)
        assert Map.has_key?(test, :test_name)
        assert Map.has_key?(test, :status)
        assert Map.has_key?(test, :execution_time)
      end)

      cleanup_test_resources(container_id, nil, project_path)
    end
  end

  # Helper functions

  defp create_temporary_patch_file(content) do
    patch_file = Path.join(System.tmp_dir!(), "test_patch_#{System.unique_integer()}.patch")
    File.write!(patch_file, content)
    patch_file
  end

  defp create_test_project do
    project_dir = Path.join(System.tmp_dir!(), "test_project_#{System.unique_integer()}")
    File.mkdir_p!(project_dir)

    # Create basic mix.exs
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
      
      defp deps do
        []
      end
    end
    """

    File.write!(Path.join(project_dir, "mix.exs"), mix_exs_content)

    # Create lib directory and basic module
    lib_dir = Path.join(project_dir, "lib")
    File.mkdir_p!(lib_dir)

    example_module = """
    defmodule Example do
      def hello do
        :world
      end
    end
    """

    File.write!(Path.join(lib_dir, "example.ex"), example_module)

    project_dir
  end

  defp create_test_project_with_tests do
    project_dir = create_test_project()

    # Create test directory and test file
    test_dir = Path.join(project_dir, "test")
    File.mkdir_p!(test_dir)

    test_content = """
    defmodule ExampleTest do
      use ExUnit.Case
      
      test "hello returns world" do
        assert Example.hello() == :world
      end
      
      test "basic arithmetic" do
        assert 1 + 1 == 2
      end
    end
    """

    File.write!(Path.join(test_dir, "example_test.exs"), test_content)

    project_dir
  end

  defp create_test_project_with_failing_test do
    project_dir = create_test_project()

    # Create test with intentional failure
    test_dir = Path.join(project_dir, "test")
    File.mkdir_p!(test_dir)

    failing_test = """
    defmodule FailingTest do
      use ExUnit.Case
      
      test "this will fail initially" do
        assert Example.broken_function() == :fixed
      end
    end
    """

    File.write!(Path.join(test_dir, "failing_test.exs"), failing_test)

    project_dir
  end

  defp create_test_project_with_state do
    project_dir = create_test_project_with_tests()

    # Add test that could be affected by state
    test_dir = Path.join(project_dir, "test")

    state_test = """
    defmodule StateTest do
      use ExUnit.Case
      
      test "state isolation test" do
        # This test should always pass the same way
        Process.put(:test_state, :isolated)
        assert Process.get(:test_state) == :isolated
      end
    end
    """

    File.write!(Path.join(test_dir, "state_test.exs"), state_test)

    project_dir
  end

  defp create_test_project_with_varied_tests do
    project_dir = create_test_project_with_tests()

    # Add more varied test types
    test_dir = Path.join(project_dir, "test")

    varied_tests = """
    defmodule VariedTest do
      use ExUnit.Case
      
      test "passing test" do
        assert true
      end
      
      test "test with longer execution" do
        :timer.sleep(100)
        assert 2 + 2 == 4
      end
      
      @tag :slow
      test "slow test" do
        :timer.sleep(500)
        assert String.length("hello") == 5
      end
    end
    """

    File.write!(Path.join(test_dir, "varied_test.exs"), varied_tests)

    project_dir
  end

  defp create_fix_patch do
    fix_content = """
    diff --git a/lib/example.ex b/lib/example.ex
    index 1234567..abcdefg 100644
    --- a/lib/example.ex
    +++ b/lib/example.ex
    @@ -3,4 +3,8 @@ defmodule Example do
       def hello do
         :world
       end
    +  
    +  def broken_function do
    +    :fixed
    +  end
     end
    """

    create_temporary_patch_file(fix_content)
  end

  defp setup_test_container do
    # Placeholder for container setup
    {:ok, "test_container_#{System.unique_integer()}"}
  end

  defp cleanup_test_resources(container_id, patch_file, project_path) do
    # Cleanup container
    if container_id, do: Builder.remove_container(container_id)

    # Cleanup patch file
    if patch_file && File.exists?(patch_file), do: File.rm!(patch_file)

    # Cleanup project
    if project_path && File.exists?(project_path), do: File.rm_rf!(project_path)
  end

  defp results_are_deterministic?(results1, results2) do
    # Compare test results for determinism
    results1.summary == results2.summary &&
      length(results1.individual_tests) == length(results2.individual_tests)
  end
end
