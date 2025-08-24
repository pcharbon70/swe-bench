defmodule SweBench.Integration.OTPBehaviorIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :otp_behavior

  alias SweBench.PatternAnalysis.OTPValidator

  alias SweBench.PatternAnalysis.OTP.{
    BehaviorChecker,
    GenserverValidator,
    ProcessMetrics,
    SupervisorAnalyzer
  }

  @test_timeout 30_000

  describe "complete OTP behavior compliance pipeline" do
    @tag timeout: @test_timeout
    test "end-to-end GenServer validation workflow" do
      genserver_code = """
      defmodule TestGenServer do
        use GenServer
        
        def start_link(initial_state) do
          GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
        end
        
        def init(initial_state) do
          {:ok, initial_state}
        end
        
        def handle_call({:get, key}, _from, state) do
          {:reply, Map.get(state, key), state}
        end
        
        def handle_call({:put, key, value}, _from, state) do
          new_state = Map.put(state, key, value)
          {:reply, :ok, new_state}
        end
        
        def handle_cast({:reset}, _state) do
          {:noreply, %{}}
        end
        
        def handle_info(:timeout, state) do
          {:noreply, Map.put(state, :timed_out, true)}
        end
        
        def terminate(reason, _state) do
          IO.puts("GenServer terminating: #{inspect(reason)}")
          :ok
        end
      end
      """

      # Validate GenServer implementation
      {:ok, validation_result} = GenserverValidator.validate_implementation(genserver_code)

      assert validation_result.has_required_callbacks
      assert validation_result.proper_return_values
      assert validation_result.state_management_correct
      assert validation_result.compliance_score > 0.8

      # Check specific callback validations
      assert Map.has_key?(validation_result.callbacks, :init)
      assert Map.has_key?(validation_result.callbacks, :handle_call)
      assert Map.has_key?(validation_result.callbacks, :handle_cast)
      assert Map.has_key?(validation_result.callbacks, :handle_info)
      assert Map.has_key?(validation_result.callbacks, :terminate)
    end

    @tag timeout: @test_timeout
    test "supervisor tree analysis and validation" do
      supervisor_code = """
      defmodule TestSupervisor do
        use Supervisor
        
        def start_link(init_arg) do
          Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end
        
        def init(_init_arg) do
          children = [
            {TestGenServer, %{initial: :state}},
            {TestWorker, []},
            {DynamicSupervisor, strategy: :one_for_one, name: TestDynamicSupervisor}
          ]
          
          Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
        end
      end

      defmodule TestWorker do
        use GenServer
        
        def start_link(args) do
          GenServer.start_link(__MODULE__, args)
        end
        
        def init(args) do
          {:ok, args}
        end
      end
      """

      # Analyze supervisor structure
      {:ok, supervisor_analysis} = SupervisorAnalyzer.analyze_structure(supervisor_code)

      assert supervisor_analysis.valid_structure
      assert supervisor_analysis.appropriate_restart_strategy
      assert supervisor_analysis.correct_child_specs
      assert supervisor_analysis.compliance_score > 0.7

      # Validate restart strategy configuration
      assert supervisor_analysis.restart_strategy == :one_for_one
      assert supervisor_analysis.max_restarts == 3
      assert supervisor_analysis.max_seconds == 5
    end

    @tag timeout: @test_timeout
    test "custom behavior compliance checking" do
      custom_behavior_code = """
      defmodule CustomBehavior do
        @callback handle_request(request :: term(), state :: term()) :: {:ok, response :: term(), new_state :: term()} | {:error, reason :: term()}
        @callback init_state() :: term()
        @optional_callback cleanup(state :: term()) :: :ok
      end

      defmodule CustomImplementation do
        @behaviour CustomBehavior
        
        def handle_request(request, state) do
          case request do
            {:get, key} -> {:ok, Map.get(state, key), state}
            {:put, key, value} -> {:ok, :stored, Map.put(state, key, value)}
            _ -> {:error, :invalid_request}
          end
        end
        
        def init_state do
          %{}
        end
        
        def cleanup(_state) do
          :ok
        end
      end
      """

      # Check behavior compliance
      {:ok, behavior_result} = BehaviorChecker.validate_compliance(custom_behavior_code)

      assert behavior_result.behavior_declared
      assert behavior_result.required_callbacks_implemented
      assert behavior_result.callback_signatures_correct
      assert behavior_result.compliance_score > 0.9
    end
  end

  describe "process metrics and monitoring integration" do
    @tag timeout: @test_timeout
    test "process metrics collection during OTP analysis" do
      # This test would normally spawn actual processes, but for integration testing
      # we'll test the metrics collection framework

      mock_process_data = %{
        pid: self(),
        initial_call: {TestGenServer, :init, 1},
        current_function: {GenServer, :loop, 3},
        message_queue_len: 0,
        memory: 2048,
        reductions: 100
      }

      # Test metrics collection
      {:ok, metrics} = ProcessMetrics.collect_metrics([mock_process_data])

      assert is_map(metrics)
      assert Map.has_key?(metrics, :total_processes)
      assert Map.has_key?(metrics, :memory_usage)
      assert Map.has_key?(metrics, :message_queue_depths)

      # Validate metric calculations
      assert metrics.total_processes == 1
      assert metrics.memory_usage.total == 2048
      assert metrics.message_queue_depths.average == 0
    end
  end

  describe "umbrella project OTP analysis coordination" do
    @tag timeout: @test_timeout
    test "OTP validation across umbrella applications" do
      umbrella_structure = %{
        apps: [
          %{name: "core_app", path: "apps/core_app"},
          %{name: "web_app", path: "apps/web_app"},
          %{name: "worker_app", path: "apps/worker_app"}
        ]
      }

      app_otp_codes = %{
        "core_app" => """
        defmodule CoreApp.Supervisor do
          use Supervisor
          
          def start_link(init_arg) do
            Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
          end
          
          def init(_init_arg) do
            children = [
              {CoreApp.Server, []}
            ]
            
            Supervisor.init(children, strategy: :one_for_one)
          end
        end
        """,
        "web_app" => """
        defmodule WebApp.Endpoint do
          use GenServer
          
          def start_link(_) do
            GenServer.start_link(__MODULE__, [], name: __MODULE__)
          end
          
          def init([]) do
            {:ok, %{connections: 0}}
          end
        end
        """,
        "worker_app" => """
        defmodule WorkerApp.JobProcessor do
          use GenServer
          
          def start_link(opts) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end
          
          def init(opts) do
            {:ok, Map.new(opts)}
          end
        end
        """
      }

      # Validate OTP compliance across all apps
      app_results =
        Enum.map(umbrella_structure.apps, fn app ->
          code = app_otp_codes[app.name]
          {:ok, result} = OTPValidator.validate_app_otp_compliance(code, app)
          {app.name, result}
        end)
        |> Map.new()

      # All apps should have valid OTP implementations
      Enum.each(app_results, fn {_app_name, result} ->
        assert result.compliance_score > 0.7
        assert result.valid_otp_structure
      end)

      # Validate cross-app consistency
      overall_compliance =
        app_results
        |> Map.values()
        |> Enum.map(& &1.compliance_score)
        |> Enum.sum()
        |> Kernel./(length(umbrella_structure.apps))

      assert overall_compliance > 0.75
    end
  end

  describe "error handling and edge cases" do
    @tag timeout: @test_timeout
    test "handles malformed OTP code gracefully" do
      malformed_genserver = """
      defmodule BadGenServer do
        use GenServer
        
        # Missing required callbacks
        def start_link(_) do
          GenServer.start_link(__MODULE__, [], name: __MODULE__)
        end
        
        # Malformed init - wrong return format
        def init(_) do
          :invalid_return
        end
      end
      """

      case GenserverValidator.validate_implementation(malformed_genserver) do
        {:ok, result} ->
          # Should identify the issues
          refute result.has_required_callbacks
          refute result.proper_return_values
          assert result.compliance_score < 0.5

        {:error, _reason} ->
          # Also acceptable - parse error
          assert true
      end
    end

    @tag timeout: @test_timeout
    test "performance validation for large OTP codebases" do
      large_otp_code = generate_large_otp_system(50)

      {time_microseconds, {:ok, result}} =
        :timer.tc(fn ->
          OTPValidator.validate_comprehensive(large_otp_code)
        end)

      # Should complete OTP validation within 3 seconds for 50 processes
      assert time_microseconds < 3_000_000
      assert is_map(result)
      assert result.total_processes == 50
    end
  end

  # Helper function to generate large OTP systems for testing
  defp generate_large_otp_system(process_count) do
    processes =
      Enum.map_join(1..process_count, "\n", fn i ->
        """
        defmodule TestProcess#{i} do
          use GenServer
          
          def start_link(init_arg) do
            GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
          end
          
          def init(init_arg) do
            {:ok, %{id: #{i}, data: init_arg}}
          end
          
          def handle_call(:get_state, _from, state) do
            {:reply, state, state}
          end
          
          def handle_cast({:update, data}, state) do
            {:noreply, Map.put(state, :data, data)}
          end
        end
        """
      end)

    supervisor = """
    defmodule TestSupervisor do
      use Supervisor
      
      def start_link(init_arg) do
        Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
      end
      
      def init(_init_arg) do
        children = [
    #{Enum.map_join(1..process_count, ",\n      ", fn i -> "{TestProcess#{i}, []}" end)}
        ]
        
        Supervisor.init(children, strategy: :one_for_one)
      end
    end
    """

    processes <> "\n" <> supervisor
  end
end
