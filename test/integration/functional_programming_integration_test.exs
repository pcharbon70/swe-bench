defmodule SweBench.Integration.FunctionalProgrammingIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :functional_programming

  alias SweBench.FunctionalAnalysis

  alias SweBench.FunctionalAnalysis.{
    FunctionPurityChecker,
    ImmutabilityAnalyzer,
    PipelineDetector,
    RecursionAnalyzer
  }

  @test_timeout 30_000

  describe "complete functional programming adherence pipeline" do
    @tag timeout: @test_timeout
    test "end-to-end functional programming analysis with multi-dimensional scoring" do
      functional_code = """
      defmodule FunctionalProgrammingExample do
        @moduledoc "Example module demonstrating functional programming principles"
        
        # Pure function with immutability
        def calculate_total(items) when is_list(items) do
          items
          |> Enum.filter(&is_valid_item?/1)
          |> Enum.map(&extract_value/1)
          |> Enum.reduce(0, &+/2)
        end
        
        # Pipeline usage with transformation
        def process_data(raw_data) do
          raw_data
          |> sanitize_input()
          |> validate_structure()
          |> transform_fields()
          |> format_output()
        end
        
        # Recursive implementation with proper termination
        def fibonacci(0), do: 0
        def fibonacci(1), do: 1
        def fibonacci(n) when n > 1 do
          fibonacci(n - 1) + fibonacci(n - 2)
        end
        
        # Tail-recursive version for performance
        def fibonacci_tail(n), do: fibonacci_tail(n, 0, 1)
        defp fibonacci_tail(0, acc, _), do: acc
        defp fibonacci_tail(n, acc, next), do: fibonacci_tail(n - 1, next, acc + next)
        
        # Pure helper functions
        defp is_valid_item?(%{value: value}) when is_number(value) and value > 0, do: true
        defp is_valid_item?(_), do: false
        
        defp extract_value(%{value: value}), do: value
        
        defp sanitize_input(data) when is_binary(data), do: String.trim(data)
        defp sanitize_input(data), do: data
        
        defp validate_structure(%{} = data), do: {:ok, data}
        defp validate_structure(_), do: {:error, :invalid_structure}
        
        defp transform_fields({:ok, data}), do: {:ok, Map.put(data, :processed, true)}
        defp transform_fields(error), do: error
        
        defp format_output({:ok, data}), do: {:success, data}
        defp format_output({:error, reason}), do: {:failure, reason}
      end
      """

      # Run complete functional analysis
      {:ok, analysis_result} = FunctionalAnalysis.analyze_code(functional_code)

      # Validate overall analysis structure
      assert is_map(analysis_result)
      assert Map.has_key?(analysis_result, :immutability_score)
      assert Map.has_key?(analysis_result, :pipeline_score)
      assert Map.has_key?(analysis_result, :recursion_score)
      assert Map.has_key?(analysis_result, :purity_score)
      assert Map.has_key?(analysis_result, :overall_score)

      # All scores should be between 0.0 and 1.0
      scores = [
        :immutability_score,
        :pipeline_score,
        :recursion_score,
        :purity_score,
        :overall_score
      ]

      Enum.each(scores, fn score_key ->
        score = analysis_result[score_key]
        assert is_number(score), "#{score_key} should be a number"
        assert score >= 0.0, "#{score_key} should be >= 0.0"
        assert score <= 1.0, "#{score_key} should be <= 1.0"
      end)

      # This code should score well on functional programming principles
      assert analysis_result.immutability_score > 0.8
      assert analysis_result.pipeline_score > 0.8
      assert analysis_result.recursion_score > 0.7
      assert analysis_result.purity_score > 0.8
      assert analysis_result.overall_score > 0.8
    end

    @tag timeout: @test_timeout
    test "immutability analysis detects violations and best practices" do
      immutability_test_code = """
      defmodule ImmutabilityTest do
        # Good immutability - data transformation without mutation
        def add_field(data, key, value) do
          Map.put(data, key, value)
        end
        
        # Good immutability - list operations without mutation
        def process_list(list) do
          list
          |> Enum.map(&transform_item/1)
          |> Enum.filter(&valid_item?/1)
        end
        
        # Proper state management with GenServer
        def update_state(pid, updates) do
          GenServer.call(pid, {:update, updates})
        end
        
        # Helper functions that maintain immutability
        defp transform_item(%{value: val} = item), do: %{item | value: val * 2}
        defp valid_item?(%{value: val}), do: val > 0
      end
      """

      # Analyze immutability specifically
      {:ok, immutability_result} =
        ImmutabilityAnalyzer.analyze_immutability(immutability_test_code)

      assert is_map(immutability_result)
      assert Map.has_key?(immutability_result, :immutability_score)
      assert Map.has_key?(immutability_result, :violations)
      assert Map.has_key?(immutability_result, :good_practices)

      # Should detect good immutability practices
      assert immutability_result.immutability_score > 0.85
      assert Enum.empty?(immutability_result.violations)
      assert not Enum.empty?(immutability_result.good_practices)

      # Test code with immutability violations
      violating_code = """
      defmodule ImmutabilityViolations do
        # This would be flagged as problematic (though technically valid Elixir)
        def problematic_pattern do
          agent = Agent.start_link(fn -> %{} end)
          Agent.update(agent, fn state -> 
            # Direct state mutation simulation
            state = Map.put(state, :direct_update, true)
            state
          end)
        end
      end
      """

      {:ok, violation_result} = ImmutabilityAnalyzer.analyze_immutability(violating_code)
      # Should have lower immutability score due to less clear immutability patterns
      assert violation_result.immutability_score < 0.9
    end

    @tag timeout: @test_timeout
    test "pipeline usage detection and quality assessment" do
      pipeline_test_code = """
      defmodule PipelineTest do
        # Excellent pipeline usage
        def excellent_pipeline(data) do
          data
          |> validate_input()
          |> transform_data()
          |> enrich_information()
          |> format_response()
          |> handle_result()
        end
        
        # Good pipeline with some complexity
        def good_pipeline(items) do
          items
          |> Enum.filter(&valid?/1)
          |> Enum.map(fn item -> 
            item
            |> process_item()
            |> add_metadata()
          end)
          |> aggregate_results()
        end
        
        # Anti-pattern - nested function calls instead of pipeline
        def anti_pattern(data) do
          handle_result(format_response(enrich_information(transform_data(validate_input(data)))))
        end
        
        # Mixed approach - some pipeline, some nesting
        def mixed_approach(data) do
          validated = validate_input(data)
          validated
          |> transform_data()
          |> enrich_information()
          |> format_response()
        end
        
        # Pipeline helpers
        defp validate_input(data), do: data
        defp transform_data(data), do: data
        defp enrich_information(data), do: data
        defp format_response(data), do: data
        defp handle_result(data), do: data
        defp valid?(_), do: true
        defp process_item(item), do: item
        defp add_metadata(item), do: item
        defp aggregate_results(items), do: items
      end
      """

      # Analyze pipeline usage
      {:ok, pipeline_result} = PipelineDetector.analyze_pipeline_usage(pipeline_test_code)

      assert is_map(pipeline_result)
      assert Map.has_key?(pipeline_result, :pipeline_score)
      assert Map.has_key?(pipeline_result, :pipeline_functions)
      assert Map.has_key?(pipeline_result, :anti_patterns)
      assert Map.has_key?(pipeline_result, :improvement_opportunities)

      # Should identify good pipeline usage
      assert pipeline_result.pipeline_score > 0.7
      assert length(pipeline_result.pipeline_functions) > 0

      # Should identify anti-patterns
      assert length(pipeline_result.anti_patterns) > 0

      # Verify specific function analysis
      function_analysis = pipeline_result.pipeline_functions

      excellent_analysis =
        Enum.find(function_analysis, fn f -> f.function_name == :excellent_pipeline end)

      assert excellent_analysis != nil
      assert excellent_analysis.pipeline_quality == :excellent
    end

    @tag timeout: @test_timeout
    test "recursion pattern analysis and tail-call optimization detection" do
      recursion_test_code = """
      defmodule RecursionTest do
        # Classic recursion - not tail-optimized
        def factorial(0), do: 1
        def factorial(n) when n > 0 do
          n * factorial(n - 1)
        end
        
        # Tail-recursive version
        def factorial_tail(n), do: factorial_tail(n, 1)
        defp factorial_tail(0, acc), do: acc
        defp factorial_tail(n, acc) when n > 0 do
          factorial_tail(n - 1, n * acc)
        end
        
        # List processing with recursion
        def sum_list([]), do: 0
        def sum_list([head | tail]), do: head + sum_list(tail)
        
        # Tail-recursive list processing  
        def sum_list_tail(list), do: sum_list_tail(list, 0)
        defp sum_list_tail([], acc), do: acc
        defp sum_list_tail([head | tail], acc) do
          sum_list_tail(tail, acc + head)
        end
        
        # Tree traversal recursion
        def traverse_tree(nil), do: []
        def traverse_tree(%{value: value, left: left, right: right}) do
          [value | traverse_tree(left) ++ traverse_tree(right)]
        end
        
        # Mutual recursion
        def is_even(0), do: true
        def is_even(n) when n > 0, do: is_odd(n - 1)
        
        def is_odd(0), do: false  
        def is_odd(n) when n > 0, do: is_even(n - 1)
      end
      """

      # Analyze recursion patterns
      {:ok, recursion_result} = RecursionAnalyzer.analyze_recursion_patterns(recursion_test_code)

      assert is_map(recursion_result)
      assert Map.has_key?(recursion_result, :recursion_score)
      assert Map.has_key?(recursion_result, :recursive_functions)
      assert Map.has_key?(recursion_result, :tail_optimized)
      assert Map.has_key?(recursion_result, :optimization_suggestions)

      # Should identify recursive functions
      assert length(recursion_result.recursive_functions) > 0

      # Should identify tail-optimized functions
      assert length(recursion_result.tail_optimized) > 0

      # Should have reasonable recursion score
      assert recursion_result.recursion_score > 0.6

      # Check for specific pattern detection
      tail_optimized_names = Enum.map(recursion_result.tail_optimized, & &1.function_name)
      assert :factorial_tail in tail_optimized_names
      assert :sum_list_tail in tail_optimized_names
    end

    @tag timeout: @test_timeout
    test "function purity classification and side effect detection" do
      purity_test_code = """
      defmodule PurityTest do
        # Pure functions - no side effects, deterministic
        def add(a, b), do: a + b
        
        def calculate_area(radius) do
          :math.pi() * radius * radius
        end
        
        def transform_list(list, func) do
          Enum.map(list, func)
        end
        
        # Impure functions - side effects or non-deterministic
        def log_message(message) do
          IO.puts(message)
          message
        end
        
        def get_current_time do
          :os.system_time(:millisecond)
        end
        
        def update_database(id, data) do
          # Simulated database update
          GenServer.call(DatabaseServer, {:update, id, data})
        end
        
        # Mixed purity - some pure, some impure aspects
        def process_with_logging(data) do
          IO.puts("Processing: #{inspect(data)}")  # Side effect
          data
          |> validate_data()  # Pure
          |> transform_data()  # Pure
        end
        
        # Pure helper functions
        defp validate_data(data) when is_map(data), do: {:ok, data}
        defp validate_data(_), do: {:error, :invalid}
        
        defp transform_data({:ok, data}), do: {:ok, Map.put(data, :processed, true)}
        defp transform_data(error), do: error
      end
      """

      # Analyze function purity
      {:ok, purity_result} = FunctionPurityChecker.analyze_function_purity(purity_test_code)

      assert is_map(purity_result)
      assert Map.has_key?(purity_result, :purity_score)
      assert Map.has_key?(purity_result, :pure_functions)
      assert Map.has_key?(purity_result, :impure_functions)
      assert Map.has_key?(purity_result, :side_effects_detected)

      # Should classify functions correctly
      assert length(purity_result.pure_functions) > 0
      assert length(purity_result.impure_functions) > 0

      # Check specific function classifications
      pure_function_names = Enum.map(purity_result.pure_functions, & &1.function_name)
      impure_function_names = Enum.map(purity_result.impure_functions, & &1.function_name)

      assert :add in pure_function_names
      assert :calculate_area in pure_function_names
      assert :transform_list in pure_function_names

      assert :log_message in impure_function_names
      assert :get_current_time in impure_function_names
      assert :update_database in impure_function_names

      # Should have reasonable purity score
      # Some pure, some impure functions
      assert purity_result.purity_score >= 0.4
      assert purity_result.purity_score <= 0.8
    end
  end

  describe "integration with pattern analysis" do
    @tag timeout: @test_timeout
    test "functional and pattern analysis complement each other" do
      integrated_code = """
      defmodule IntegratedAnalysisExample do
        # Combines good pattern matching with functional principles
        def process_request(request) do
          request
          |> validate_request()
          |> route_request()
          |> execute_action()
          |> format_response()
        end
        
        # Pattern matching with functional approach
        defp validate_request(%{type: :api, token: token} = request) when is_binary(token) do
          case authenticate_token(token) do
            {:ok, user} -> {:ok, Map.put(request, :user, user)}
            {:error, reason} -> {:error, reason}
          end
        end
        defp validate_request(%{type: :webhook, signature: sig} = request) when is_binary(sig) do
          case verify_signature(sig, request) do
            true -> {:ok, request}
            false -> {:error, :invalid_signature}
          end
        end
        defp validate_request(_), do: {:error, :invalid_request}
        
        # Functional routing with pattern matching
        defp route_request({:ok, %{type: :api, action: action} = request}) do
          case action do
            :create -> {:create, request}
            :update -> {:update, request}
            :delete -> {:delete, request}
            :read -> {:read, request}
            _ -> {:error, :unsupported_action}
          end
        end
        defp route_request({:ok, %{type: :webhook, event: event} = request}) do
          {:webhook, event, request}
        end
        defp route_request(error), do: error
        
        # Pattern matching in action execution
        defp execute_action({:create, request}), do: create_resource(request)
        defp execute_action({:update, request}), do: update_resource(request)
        defp execute_action({:delete, request}), do: delete_resource(request)
        defp execute_action({:read, request}), do: read_resource(request)
        defp execute_action({:webhook, event, request}), do: handle_webhook(event, request)
        defp execute_action(error), do: error
        
        # Pure helper functions
        defp authenticate_token(_token), do: {:ok, %{id: 1, name: "test"}}
        defp verify_signature(_sig, _request), do: true
        defp create_resource(_request), do: {:ok, :created}
        defp update_resource(_request), do: {:ok, :updated}
        defp delete_resource(_request), do: {:ok, :deleted}
        defp read_resource(_request), do: {:ok, :data}
        defp handle_webhook(_event, _request), do: {:ok, :processed}
        defp format_response(result), do: result
      end
      """

      # Run both functional and pattern analysis
      {:ok, functional_result} = FunctionalAnalysis.analyze_code(integrated_code)

      # This should score well on both dimensions
      assert functional_result.pipeline_score > 0.8
      assert functional_result.purity_score > 0.7
      assert functional_result.immutability_score > 0.8
      assert functional_result.overall_score > 0.75

      # The integration should show that good functional programming
      # and good pattern matching reinforce each other
      assert functional_result.overall_score > 0.75
    end
  end

  describe "graduated scoring accuracy" do
    @tag timeout: @test_timeout
    test "functional programming scoring differentiates quality levels correctly" do
      quality_examples = [
        %{
          name: "excellent_functional",
          code: """
          defmodule ExcellentFunctional do
            def process_data(data) do
              data
              |> validate_structure()
              |> sanitize_fields()
              |> transform_values()
              |> aggregate_results()
            end
            
            defp validate_structure(%{} = data), do: {:ok, data}
            defp validate_structure(_), do: {:error, :invalid}
            
            defp sanitize_fields({:ok, data}) do
              sanitized = data
                          |> Map.update(:name, "", &String.trim/1)
                          |> Map.update(:email, "", &String.downcase/1)
              {:ok, sanitized}
            end
            defp sanitize_fields(error), do: error
            
            defp transform_values({:ok, data}) do
              transformed = Map.update(data, :score, 0, &(&1 * 1.1))
              {:ok, transformed}
            end
            defp transform_values(error), do: error
            
            defp aggregate_results({:ok, data}), do: {:success, data}
            defp aggregate_results({:error, reason}), do: {:failure, reason}
          end
          """,
          # 100% - excellent functional programming
          expected_tier: 4
        },
        %{
          name: "poor_functional",
          code: """
          defmodule PoorFunctional do
            def process_data(data) do
              if is_map(data) do
                if Map.has_key?(data, :name) do
                  name = String.trim(data.name)
                  if Map.has_key?(data, :email) do
                    email = String.downcase(data.email)
                    if Map.has_key?(data, :score) do
                      score = data.score * 1.1
                      %{name: name, email: email, score: score}
                    else
                      nil
                    end
                  else
                    nil
                  end
                else
                  nil
                end
              else
                nil
              end
            end
          end
          """,
          # 25% - poor functional programming
          expected_tier: 1
        }
      ]

      # Test each quality level
      results =
        Enum.map(quality_examples, fn %{name: name, code: code, expected_tier: expected_tier} ->
          {:ok, analysis} = FunctionalAnalysis.analyze_code(code)

          # Map score to tier
          tier =
            case analysis.overall_score do
              score when score >= 0.9 -> 4
              score when score >= 0.75 -> 3
              score when score >= 0.5 -> 2
              score when score >= 0.25 -> 1
              _ -> 0
            end

          {name, expected_tier, tier, analysis.overall_score}
        end)

      # Validate tier assignments
      Enum.each(results, fn {name, expected_tier, calculated_tier, score} ->
        # Allow some flexibility but expect reasonable differentiation
        assert abs(calculated_tier - expected_tier) <= 1,
               "#{name}: expected tier #{expected_tier}, got #{calculated_tier} (score: #{score})"
      end)

      # Ensure excellent code scores higher than poor code
      [{_, _, _, excellent_score}, {_, _, _, poor_score}] = results
      # Significant difference expected
      assert excellent_score > poor_score + 0.2
    end
  end

  describe "performance validation" do
    @tag timeout: @test_timeout
    test "functional analysis completes within performance targets" do
      large_functional_module = generate_large_functional_module(50)

      {time_microseconds, {:ok, result}} =
        :timer.tc(fn ->
          FunctionalAnalysis.analyze_code(large_functional_module)
        end)

      # Should complete analysis within 4 seconds for 50 functions
      assert time_microseconds < 4_000_000
      assert is_map(result)
      assert Map.has_key?(result, :overall_score)
    end
  end

  # Helper function to generate large functional modules for testing
  defp generate_large_functional_module(function_count) do
    functions =
      Enum.map_join(1..function_count, "\n", fn i ->
        """
          def process_item_#{i}(item) do
            item
            |> validate_item_#{i}()
            |> transform_item_#{i}()
            |> finalize_item_#{i}()
          end
          
          defp validate_item_#{i}(%{type: :type_#{i}} = item), do: {:ok, item}
          defp validate_item_#{i}(_), do: {:error, :invalid_type_#{i}}
          
          defp transform_item_#{i}({:ok, item}), do: {:ok, Map.put(item, :processed_#{i}, true)}
          defp transform_item_#{i}(error), do: error
          
          defp finalize_item_#{i}({:ok, item}), do: {:success, item}
          defp finalize_item_#{i}({:error, reason}), do: {:failure, reason}
        """
      end)

    """
    defmodule LargeFunctionalModule do
    #{functions}
    end
    """
  end
end
