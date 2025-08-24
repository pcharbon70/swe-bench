defmodule SweBench.Integration.StaticAnalysisIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :static_analysis

  alias SweBench.StaticAnalysis.{
    CredoAnalyzer,
    DialyzerIntegration,
    QualityCalculator,
    WarningAggregator
  }

  @test_timeout 45_000

  describe "complete Credo and Dialyzer integration workflow" do
    @tag timeout: @test_timeout
    test "end-to-end static analysis pipeline with quality metrics" do
      elixir_code = """
      defmodule StaticAnalysisTest do
        @moduledoc "Test module for static analysis validation"

        @spec process_data(map()) :: {:ok, term()} | {:error, atom()}
        def process_data(%{} = data) do
          case validate_data(data) do
            true ->
              result = transform_data(data)
              {:ok, result}
            false ->
              {:error, :invalid_data}
          end
        end

        @spec validate_data(map()) :: boolean()
        defp validate_data(data) when is_map(data) do
          required_keys = [:name, :type, :value]
          Enum.all?(required_keys, &Map.has_key?(data, &1))
        end

        @spec transform_data(map()) :: map()
        defp transform_data(%{value: value} = data) when is_number(value) do
          %{data | value: value * 2, processed: true}
        end
        defp transform_data(data), do: Map.put(data, :processed, false)

        # Intentional code quality issues for testing
        def poorly_written_function(x,y,z) do
          if x == 1 do
            if y == 2 do
              if z == 3 do
                "success"
              else
                "fail"
              end
            else
              "fail"
            end
          else
            "fail"
          end
        end
      end
      """

      # Create temporary file for analysis
      temp_file = create_temp_file(elixir_code)

      try do
        # Run Credo analysis
        {:ok, credo_result} = CredoAnalyzer.analyze_file(temp_file)

        assert is_map(credo_result)
        assert Map.has_key?(credo_result, :issues)
        assert Map.has_key?(credo_result, :score)
        assert is_list(credo_result.issues)
        assert is_number(credo_result.score)

        # Should detect the poorly written function
        poor_function_issues =
          Enum.filter(credo_result.issues, fn issue ->
            String.contains?(issue.message, "poorly_written_function") or
              issue.category == :readability or
              issue.category == :refactor
          end)

        assert length(poor_function_issues) > 0

        # Run Dialyzer analysis (simplified for integration test)
        {:ok, dialyzer_result} = DialyzerIntegration.analyze_file(temp_file)

        assert is_map(dialyzer_result)
        assert Map.has_key?(dialyzer_result, :warnings)
        assert Map.has_key?(dialyzer_result, :type_safety_score)

        # Aggregate warnings from both tools
        {:ok, aggregated_warnings} =
          WarningAggregator.aggregate_warnings([
            {:credo, credo_result.issues},
            {:dialyzer, dialyzer_result.warnings}
          ])

        assert is_list(aggregated_warnings)
        assert length(aggregated_warnings) > 0

        # Calculate overall quality metrics
        {:ok, quality_metrics} =
          QualityCalculator.calculate_metrics(
            elixir_code,
            credo_result,
            dialyzer_result,
            aggregated_warnings
          )

        assert is_map(quality_metrics)
        assert Map.has_key?(quality_metrics, :overall_score)
        assert Map.has_key?(quality_metrics, :readability_score)
        assert Map.has_key?(quality_metrics, :maintainability_score)
        assert Map.has_key?(quality_metrics, :type_safety_score)

        # Scores should be normalized between 0.0 and 1.0
        Enum.each(
          [:overall_score, :readability_score, :maintainability_score, :type_safety_score],
          fn key ->
            score = quality_metrics[key]
            assert is_number(score)
            assert score >= 0.0
            assert score <= 1.0
          end
        )
      after
        File.rm(temp_file)
      end
    end

    @tag timeout: @test_timeout
    test "PLT building and type safety analysis" do
      module_with_specs = """
      defmodule TypeSafetyTest do
        @spec add_numbers(integer(), integer()) :: integer()
        def add_numbers(a, b) when is_integer(a) and is_integer(b) do
          a + b
        end

        @spec process_list([term()]) :: [term()]
        def process_list(list) when is_list(list) do
          Enum.map(list, &transform_item/1)
        end

        @spec transform_item(term()) :: term()
        defp transform_item(item) when is_binary(item), do: String.upcase(item)
        defp transform_item(item) when is_number(item), do: item * 2
        defp transform_item(item), do: item

        # Type error: spec says integer, but returns float
        @spec divide_numbers(integer(), integer()) :: integer()
        def divide_numbers(a, b) do
          a / b  # This returns float, not integer
        end
      end
      """

      temp_file = create_temp_file(module_with_specs)

      try do
        # Test PLT building
        {:ok, plt_info} = DialyzerIntegration.ensure_plt_built([temp_file])
        assert Map.has_key?(plt_info, :plt_path)
        assert Map.has_key?(plt_info, :modules_analyzed)
        assert plt_info.modules_analyzed > 0

        # Run type analysis
        {:ok, type_analysis} = DialyzerIntegration.analyze_types(temp_file, plt_info.plt_path)

        # Should detect the type error in divide_numbers
        type_warnings = type_analysis.warnings

        divide_warnings =
          Enum.filter(type_warnings, fn warning ->
            String.contains?(warning.message, "divide_numbers") or
              String.contains?(warning.message, "integer") or
              String.contains?(warning.message, "float")
          end)

        assert length(divide_warnings) > 0
      after
        File.rm(temp_file)
      end
    end
  end

  describe "warning aggregation and prioritization" do
    @tag timeout: @test_timeout
    test "warning deduplication and prioritization" do
      # Simulate warnings from multiple tools
      credo_warnings = [
        %{
          tool: :credo,
          category: :readability,
          severity: :medium,
          message: "Long function",
          line: 10
        },
        %{
          tool: :credo,
          category: :complexity,
          severity: :high,
          message: "High cyclomatic complexity",
          line: 15
        },
        %{tool: :credo, category: :naming, severity: :low, message: "Variable name", line: 20}
      ]

      dialyzer_warnings = [
        %{
          tool: :dialyzer,
          category: :type_error,
          severity: :high,
          message: "Type mismatch",
          line: 15
        },
        %{
          tool: :dialyzer,
          category: :spec_error,
          severity: :medium,
          message: "Invalid spec",
          line: 25
        }
      ]

      # Test aggregation
      {:ok, aggregated} =
        WarningAggregator.aggregate_warnings([
          {:credo, credo_warnings},
          {:dialyzer, dialyzer_warnings}
        ])

      # Should have all warnings
      assert length(aggregated) == 5

      # Test deduplication (simulate duplicate warnings)
      duplicate_credo = credo_warnings ++ [List.first(credo_warnings)]

      {:ok, deduplicated} =
        WarningAggregator.aggregate_warnings([
          {:credo, duplicate_credo},
          {:dialyzer, dialyzer_warnings}
        ])

      # Should remove duplicate
      assert length(deduplicated) == 5

      # Test prioritization
      prioritized = WarningAggregator.prioritize_warnings(aggregated)

      # High severity warnings should come first
      first_warning = List.first(prioritized)
      assert first_warning.severity == :high

      # Should have proper priority scores
      assert Enum.all?(prioritized, fn warning ->
               Map.has_key?(warning, :priority_score)
             end)
    end
  end

  describe "graduated scoring system integration" do
    @tag timeout: @test_timeout
    test "quality scoring tiers and partial credit" do
      # Test different quality levels
      quality_levels = [
        %{
          name: "excellent_code",
          code: """
          defmodule ExcellentCode do
            @moduledoc "Well-documented, clean module"

            @spec process_data(map()) :: {:ok, map()} | {:error, atom()}
            def process_data(%{} = data) do
              data
              |> validate_required_fields()
              |> transform_safely()
              |> format_result()
            end

            @spec validate_required_fields(map()) :: {:ok, map()} | {:error, :missing_fields}
            defp validate_required_fields(%{name: _, type: _} = data), do: {:ok, data}
            defp validate_required_fields(_), do: {:error, :missing_fields}

            @spec transform_safely({:ok, map()} | {:error, atom()}) :: {:ok, map()} | {:error, atom()}
            defp transform_safely({:ok, data}), do: {:ok, Map.put(data, :processed, true)}
            defp transform_safely(error), do: error

            @spec format_result({:ok, map()} | {:error, atom()}) :: {:ok, map()} | {:error, atom()}
            defp format_result(result), do: result
          end
          """,
          # 100% - excellent
          expected_tier: 4
        },
        %{
          name: "good_code",
          code: """
          defmodule GoodCode do
            @spec process_data(map()) :: {:ok, map()} | {:error, atom()}
            def process_data(data) when is_map(data) do
              if Map.has_key?(data, :name) and Map.has_key?(data, :type) do
                {:ok, Map.put(data, :processed, true)}
              else
                {:error, :missing_fields}
              end
            end
          end
          """,
          # 75% - good
          expected_tier: 3
        },
        %{
          name: "average_code",
          code: """
          defmodule AverageCode do
            def process_data(data) do
              case data do
                %{name: name, type: type} -> {:ok, %{name: name, type: type, processed: true}}
                _ -> {:error, :invalid}
              end
            end
          end
          """,
          # 50% - average
          expected_tier: 2
        },
        %{
          name: "poor_code",
          code: """
          defmodule PoorCode do
            def process_data(x) do
              if x[:name] != nil do
                if x[:type] != nil do
                  {:ok, Map.put(x, :processed, true)}
                else
                  {:error, :no_type}
                end
              else
                {:error, :no_name}
              end
            end
          end
          """,
          # 25% - poor
          expected_tier: 1
        }
      ]

      # Analyze each quality level
      tier_results =
        Enum.map(quality_levels, fn %{name: name, code: code, expected_tier: expected_tier} ->
          temp_file = create_temp_file(code)

          try do
            {:ok, credo_result} = CredoAnalyzer.analyze_file(temp_file)
            {:ok, dialyzer_result} = DialyzerIntegration.analyze_file(temp_file)

            {:ok, aggregated_warnings} =
              WarningAggregator.aggregate_warnings([
                {:credo, credo_result.issues},
                {:dialyzer, dialyzer_result.warnings}
              ])

            {:ok, quality_metrics} =
              QualityCalculator.calculate_metrics(
                code,
                credo_result,
                dialyzer_result,
                aggregated_warnings
              )

            # Calculate tier based on overall score
            calculated_tier =
              case quality_metrics.overall_score do
                # 100%
                score when score >= 0.9 -> 4
                # 75%
                score when score >= 0.75 -> 3
                # 50%
                score when score >= 0.5 -> 2
                # 25%
                score when score >= 0.25 -> 1
                # 0%
                _ -> 0
              end

            {name, expected_tier, calculated_tier, quality_metrics.overall_score}
          after
            File.rm(temp_file)
          end
        end)

      # Validate tier assignments
      Enum.each(tier_results, fn {name, expected_tier, calculated_tier, score} ->
        # Allow some flexibility in tier assignment (±1 tier)
        assert abs(calculated_tier - expected_tier) <= 1,
               "#{name}: expected tier #{expected_tier}, got #{calculated_tier} (score: #{score})"
      end)

      # Verify score progression (better code should have higher scores)
      scores = Enum.map(tier_results, fn {_, _, _, score} -> score end)
      excellent_score = Enum.at(scores, 0)
      poor_score = Enum.at(scores, 3)
      assert excellent_score > poor_score
    end
  end

  describe "performance and scalability" do
    @tag timeout: @test_timeout
    test "static analysis performance with large codebases" do
      large_module = generate_large_module_for_analysis(100)
      temp_file = create_temp_file(large_module)

      try do
        # Test Credo performance
        {credo_time_us, {:ok, credo_result}} =
          :timer.tc(fn ->
            CredoAnalyzer.analyze_file(temp_file)
          end)

        # Should complete Credo analysis within 10 seconds for 100 functions
        assert credo_time_us < 10_000_000
        assert is_map(credo_result)

        # Test quality calculation performance
        {quality_time_us, {:ok, _quality_metrics}} =
          :timer.tc(fn ->
            QualityCalculator.calculate_metrics(
              large_module,
              credo_result,
              %{warnings: [], type_safety_score: 0.8},
              []
            )
          end)

        # Should complete quality calculation within 5 seconds
        assert quality_time_us < 5_000_000
      after
        File.rm(temp_file)
      end
    end
  end

  # Helper functions
  defp create_temp_file(content) do
    temp_file = "#{System.tmp_dir()}/static_analysis_test_#{:rand.uniform(1_000_000)}.ex"
    File.write!(temp_file, content)
    temp_file
  end

  defp generate_large_module_for_analysis(function_count) do
    functions =
      Enum.map_join(1..function_count, "\n", fn i ->
        """
          @spec process_item_#{i}(term()) :: {:ok, term()} | {:error, atom()}
          def process_item_#{i}(item) do
            case validate_item_#{i}(item) do
              true ->
                result = transform_item_#{i}(item)
                {:ok, result}
              false ->
                {:error, :invalid_item_#{i}}
            end
          end

          defp validate_item_#{i}(item) when is_map(item) do
            Map.has_key?(item, :type_#{i})
          end
          defp validate_item_#{i}(_), do: false

          defp transform_item_#{i}(item) do
            Map.put(item, :processed_#{i}, true)
          end
        """
      end)

    """
    defmodule LargeModuleForAnalysis do
      @moduledoc "Large module generated for static analysis performance testing"

    #{functions}
    end
    """
  end
end
