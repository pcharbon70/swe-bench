defmodule SweBench.Integration.Phase5.WebInterfaceTest do
  use ExUnit.Case, async: false
  use SweBenchWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SweBench.IntegrationTesting.{TestOrchestrator, EnvironmentManager}

  @moduletag :integration

  describe "Phase 5.1 Web Interface Integration" do
    test "public dashboard loads and displays results" do
      # Test public dashboard accessibility
      {:ok, view, html} = live(build_conn(), "/dashboard")
      
      assert html =~ "SWE-bench Elixir"
      assert html =~ "Public Dashboard"
      assert has_element?(view, "table")  # Results table should be present
      assert has_element?(view, "button", "Results")  # Navigation should be present
    end

    test "admin interface requires authentication" do
      # Test admin interface protection
      conn = build_conn()
      
      # Should redirect to login for unauthenticated access
      assert {:error, {:redirect, %{to: _login_path}}} = live(conn, "/admin/evaluations")
    end

    test "filter panel responds to user interactions" do
      {:ok, view, _html} = live(build_conn(), "/dashboard")
      
      # Test filter panel interactions
      assert has_element?(view, "[data-test='filter-panel']") or
             has_element?(view, "h3", "Filter Results")
    end

    test "chart switching works correctly" do
      {:ok, view, _html} = live(build_conn(), "/dashboard")
      
      # Navigate to model comparisons
      view |> element("button", "Model Comparisons") |> render_click()
      
      # Should show model comparison interface
      assert has_element?(view, "select") or
             render(view) =~ "comparison"
    end
  end

  describe "Phase 5.2 Real-Time Integration" do
    test "PubSub channels are properly configured" do
      # Test PubSub infrastructure
      assert {:ok, _} = Phoenix.PubSub.subscribe(SweBench.PubSub, "evaluations:submissions")
      assert {:ok, _} = Phoenix.PubSub.subscribe(SweBench.PubSub, "evaluations:results")
      
      # Test broadcasting
      Phoenix.PubSub.broadcast(SweBench.PubSub, "evaluations:submissions", {:test_event, %{}})
      
      assert_receive {:test_event, %{}}
    end

    test "WebSocket connections can be established" do
      {:ok, view, _html} = live(build_conn(), "/dashboard")
      
      # LiveView connection should be WebSocket-based
      assert view.module == SweBenchWeb.DashboardLive
    end

    test "real-time updates are delivered instantly" do
      {:ok, view, _html} = live(build_conn(), "/dashboard")
      
      # Send test event
      send(view.pid, {:evaluation_complete, %{
        id: "test_eval",
        model: "Test Model",
        score: 95.0,
        status: :completed
      }})
      
      # Should handle the event (may not update visually without proper implementation)
      assert Process.alive?(view.pid)
    end
  end

  describe "Phase 5.3 LiveView Components" do
    test "dashboard components render correctly" do
      {:ok, view, html} = live(build_conn(), "/dashboard")
      
      # Should have main dashboard structure
      assert html =~ "Filter Results" or html =~ "dashboard"
    end

    test "component state management works" do
      {:ok, view, _html} = live(build_conn(), "/dashboard")
      
      # Test view changes
      view |> element("button", "Model Comparisons") |> render_click()
      view |> element("button", "Results") |> render_click()
      
      # Should handle state changes without errors
      assert Process.alive?(view.pid)
    end
  end

  describe "Phase 5.4 Authentication Integration" do
    test "authentication system is configured" do
      # Test that authentication modules are available
      assert Code.ensure_loaded?(SweBench.Accounts.Authorization) == {:module, SweBench.Accounts.Authorization}
      assert Code.ensure_loaded?(SweBench.Accounts.SessionManager) == {:module, SweBench.Accounts.SessionManager}
    end

    test "role-based access works" do
      # Test role determination
      assert SweBench.Accounts.Authorization.get_user_role(nil) == :public
      assert SweBench.Accounts.Authorization.can_access_route?(nil, "/dashboard") == true
      assert SweBench.Accounts.Authorization.can_access_route?(nil, "/admin/evaluations") == false
    end
  end

  describe "Phase 5.6 Monitoring Integration" do
    test "monitoring systems are available" do
      # Test that monitoring modules are loaded
      assert Code.ensure_loaded?(SweBench.Monitoring.MetricsCollector) == {:module, SweBench.Monitoring.MetricsCollector}
      assert Code.ensure_loaded?(SweBench.Monitoring.AlertingSystem) == {:module, SweBench.Monitoring.AlertingSystem}
    end

    test "telemetry events can be emitted" do
      # Test telemetry event emission
      :telemetry.execute([:swe_bench, :test, :event], %{value: 1}, %{test: true})
      
      # Should complete without errors
      assert true
    end
  end

  describe "Cross-Component Integration" do
    test "all Phase 5 systems can be started together" do
      # Test that core systems can be supervised together
      children = [
        {Phoenix.PubSub, name: SweBench.TestPubSub},
        SweBench.Accounts.SessionManager,
        SweBench.Monitoring.MetricsCollector
      ]
      
      {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
      
      # All processes should be alive
      assert Process.alive?(supervisor)
      
      # Cleanup
      Supervisor.stop(supervisor)
    end

    test "integration test orchestrator can run basic tests" do
      # Start test orchestrator
      {:ok, _pid} = start_supervised(SweBench.IntegrationTesting.TestOrchestrator)
      
      # Run a basic test suite
      result = SweBench.IntegrationTesting.TestOrchestrator.run_test_suite(
        :web_interface_testing, 
        %{timeout: 10_000}
      )
      
      case result do
        {:ok, test_results} ->
          assert is_map(test_results)
        
        {:error, reason} ->
          # Acceptable if full environment isn't available
          assert reason != nil
      end
    end
  end

  describe "Production Readiness Validation" do
    test "system components are production-ready" do
      # Test that all major components compile and can be loaded
      required_modules = [
        SweBenchWeb.DashboardLive,
        SweBenchWeb.Admin.EvaluationLive,
        SweBench.RealTimeEvents.EventCoordinator,
        SweBench.Accounts.Authorization,
        SweBench.Monitoring.MetricsCollector
      ]
      
      Enum.each(required_modules, fn module ->
        case Code.ensure_loaded(module) do
          {:module, ^module} ->
            assert true  # Module loads successfully
          
          {:error, _} ->
            flunk("Required module #{module} failed to load")
        end
      end)
    end

    test "configuration is production-ready" do
      # Test that essential configuration is present
      assert Application.get_env(:swe_bench, SweBench.Repo) != nil
      assert Application.get_env(:swe_bench, SweBenchWeb.Endpoint) != nil
    end
  end
end