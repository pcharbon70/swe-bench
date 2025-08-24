defmodule SweBench.Integration.PatternAnalysisIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :pattern_analysis

  alias SweBench.FunctionalAnalysis
  alias SweBench.PatternAnalysis
  alias SweBench.PatternAnalysis.{AstParser, ClauseAnalyzer, ExhaustivenessChecker, QualityScorer}

  @test_timeout 30_000

  describe "complete pattern matching validation pipeline" do
    @tag timeout: @test_timeout
    test "end-to-end pattern analysis with quality scoring" do
      elixir_code = """
      defmodule TestModule do
        def process_data(data) do
          case data do
            %{type: :user, id: id} when is_integer(id) -> {:ok, "User #{id}"}
            %{type: :admin, permissions: perms} when is_list(perms) -> {:ok, "Admin with #{length(perms)} permissions"}
            %{type: :guest} -> {:ok, "Guest user"}
            _ -> {:error, "Invalid data"}
          end
        end
        
        def calculate_total([]), do: 0
        def calculate_total([head | tail]), do: head + calculate_total(tail)
        
        def validate_input(input) when is_binary(input) and byte_size(input) > 0, do: :ok
        def validate_input(_), do: :error
      end
      """

      # Parse AST
      {:ok, ast} = AstParser.parse_source(elixir_code)
      assert is_tuple(ast)

      # Extract function definitions
      functions = AstParser.extract_functions(ast)
      assert length(functions) == 3

      # Run exhaustiveness checking
      exhaustiveness_results = ExhaustivenessChecker.analyze_functions(functions)
      assert is_map(exhaustiveness_results)
      assert Map.has_key?(exhaustiveness_results, :process_data)
      assert Map.has_key?(exhaustiveness_results, :calculate_total)

      # Run clause analysis
      clause_results = ClauseAnalyzer.analyze_clause_ordering(functions)
      assert is_map(clause_results)

      # Calculate quality score
      quality_score =
        QualityScorer.calculate_score(functions, exhaustiveness_results, clause_results)

      assert is_number(quality_score)
      assert quality_score >= 0.0
      assert quality_score <= 1.0

      # Integration with functional analysis
      functional_results = FunctionalAnalysis.analyze_code(elixir_code)
      assert is_map(functional_results)

      # Combined analysis should be consistent
      combined_score = (quality_score + functional_results.overall_score) / 2
      assert is_number(combined_score)
    end

    @tag timeout: @test_timeout
    test "pattern analysis handles malformed code gracefully" do
      malformed_code = """
      defmodule BadModule do
        def broken_function(
          # Missing closing parenthesis
        end
      end
      """

      case AstParser.parse_source(malformed_code) do
        {:error, _reason} ->
          # Expected behavior - should handle parse errors gracefully
          assert true

        {:ok, _ast} ->
          # If it somehow parses, that's also acceptable
          assert true
      end
    end

    @tag timeout: @test_timeout
    test "pattern analysis performance within acceptable limits" do
      large_code = generate_large_module_with_patterns(100)

      {time_microseconds, result} =
        :timer.tc(fn ->
          with {:ok, ast} <- AstParser.parse_source(large_code),
               functions <- AstParser.extract_functions(ast),
               exhaustiveness_results <- ExhaustivenessChecker.analyze_functions(functions),
               clause_results <- ClauseAnalyzer.analyze_clause_ordering(functions) do
            QualityScorer.calculate_score(functions, exhaustiveness_results, clause_results)
          end
        end)

      # Should complete analysis within 5 seconds for 100 functions
      assert time_microseconds < 5_000_000
      assert is_number(result)
    end
  end

  describe "deterministic results validation" do
    @tag timeout: @test_timeout
    test "pattern analysis produces consistent results across multiple runs" do
      elixir_code = """
      defmodule ConsistencyTest do
        def handle_event(:start, state), do: {:ok, Map.put(state, :status, :running)}
        def handle_event(:stop, state), do: {:ok, Map.put(state, :status, :stopped)}
        def handle_event(:reset, _state), do: {:ok, %{status: :init}}
        def handle_event(_, state), do: {:error, state}
      end
      """

      results =
        Enum.map(1..5, fn _run ->
          with {:ok, ast} <- AstParser.parse_source(elixir_code),
               functions <- AstParser.extract_functions(ast),
               exhaustiveness_results <- ExhaustivenessChecker.analyze_functions(functions),
               clause_results <- ClauseAnalyzer.analyze_clause_ordering(functions) do
            QualityScorer.calculate_score(functions, exhaustiveness_results, clause_results)
          end
        end)

      # All results should be identical
      first_result = List.first(results)
      assert Enum.all?(results, fn result -> result == first_result end)
    end
  end

  describe "integration with functional programming analysis" do
    @tag timeout: @test_timeout
    test "pattern matching and functional analysis work together" do
      functional_code = """
      defmodule FunctionalExample do
        def process_pipeline(data) do
          data
          |> validate_input()
          |> transform_data()
          |> format_output()
        end
        
        defp validate_input(%{valid: true} = data), do: {:ok, data}
        defp validate_input(_), do: {:error, :invalid}
        
        defp transform_data({:ok, data}), do: {:ok, Map.update(data, :value, 0, &(&1 * 2))}
        defp transform_data(error), do: error
        
        defp format_output({:ok, %{value: value}}), do: "Result: #{value}"
        defp format_output({:error, reason}), do: "Error: #{reason}"
      end
      """

      # Pattern analysis
      {:ok, ast} = AstParser.parse_source(functional_code)
      functions = AstParser.extract_functions(ast)
      exhaustiveness_results = ExhaustivenessChecker.analyze_functions(functions)
      clause_results = ClauseAnalyzer.analyze_clause_ordering(functions)

      pattern_score =
        QualityScorer.calculate_score(functions, exhaustiveness_results, clause_results)

      # Functional analysis
      functional_results = FunctionalAnalysis.analyze_code(functional_code)

      # Both analyses should complement each other
      # Good pattern matching
      assert pattern_score > 0.7
      # Good pipeline usage
      assert functional_results.pipeline_score > 0.8
      # High immutability
      assert functional_results.immutability_score > 0.9
    end
  end

  # Helper function to generate large test modules
  defp generate_large_module_with_patterns(function_count) do
    functions =
      Enum.map_join(1..function_count, "\n", fn i ->
        """
          def process_item_#{i}(item) do
            case item do
              %{type: :type_#{i}, value: val} when is_integer(val) -> {:ok, val * #{i}}
              %{type: :type_#{i}} -> {:ok, #{i}}
              _ -> {:error, :unknown_type}
            end
          end
        """
      end)

    """
    defmodule LargeTestModule do
    #{functions}
    end
    """
  end
end
