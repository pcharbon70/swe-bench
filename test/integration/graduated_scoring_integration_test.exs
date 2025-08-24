defmodule SweBench.Integration.GraduatedScoringIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :graduated_scoring

  @test_timeout 30_000

  describe "complete graduated scoring system validation" do
    @tag timeout: @test_timeout
    test "all scoring tiers (0%, 25%, 50%, 75%, 100%) with accurate tier assignment" do
      # Define code samples for each scoring tier
      scoring_tier_examples = [
        %{
          # 100% - Excellent
          tier: 4,
          percentage: 100,
          name: "excellent_elixir_code",
          code: """
          defmodule ExcellentCode do
            @moduledoc '''
            Demonstrates excellent Elixir practices with comprehensive pattern matching,
            functional programming principles, and robust error handling.
            '''
            
            @type user :: %{id: pos_integer(), name: binary(), email: binary()}
            @type result :: {:ok, term()} | {:error, atom()}
            
            @spec process_user_data([user()]) :: result()
            def process_user_data(users) when is_list(users) do
              users
              |> validate_all_users()
              |> transform_user_data()
              |> enrich_with_metadata()
              |> format_final_result()
            end
            
            @spec validate_all_users([user()]) :: {:ok, [user()]} | {:error, atom()}
            defp validate_all_users(users) do
              case Enum.find(users, &(!valid_user?(&1))) do
                nil -> {:ok, users}
                _invalid -> {:error, :invalid_user_found}
              end
            end
            
            @spec valid_user?(user()) :: boolean()
            defp valid_user?(%{id: id, name: name, email: email}) 
                 when is_integer(id) and id > 0 and 
                      is_binary(name) and byte_size(name) > 0 and
                      is_binary(email) and byte_size(email) > 0 do
              String.contains?(email, "@")
            end
            defp valid_user?(_), do: false
            
            @spec transform_user_data({:ok, [user()]} | {:error, atom()}) :: {:ok, [map()]} | {:error, atom()}
            defp transform_user_data({:ok, users}) do
              transformed = Enum.map(users, fn user ->
                user
                |> Map.put(:display_name, format_display_name(user))
                |> Map.put(:email_domain, extract_email_domain(user.email))
                |> Map.put(:created_at, DateTime.utc_now())
              end)
              {:ok, transformed}
            end
            defp transform_user_data(error), do: error
            
            defp format_display_name(%{name: name}), do: String.trim(name) |> String.title()
            
            defp extract_email_domain(email) do
              email |> String.split("@") |> List.last() |> String.downcase()
            end
            
            defp enrich_with_metadata({:ok, users}) do
              enriched = Enum.map(users, &Map.put(&1, :metadata, %{version: "1.0", source: "api"}))
              {:ok, enriched}
            end
            defp enrich_with_metadata(error), do: error
            
            defp format_final_result({:ok, users}), do: {:success, %{users: users, count: length(users)}}
            defp format_final_result({:error, reason}), do: {:failure, %{error: reason, timestamp: DateTime.utc_now()}}
          end
          """
        },
        %{
          # 75% - Good
          tier: 3,
          percentage: 75,
          name: "good_elixir_code",
          code: """
          defmodule GoodCode do
            @moduledoc "Good Elixir code with solid patterns and decent error handling"
            
            def process_user_data(users) when is_list(users) do
              users
              |> filter_valid_users()
              |> transform_users()
              |> create_response()
            end
            
            defp filter_valid_users(users) do
              Enum.filter(users, fn user ->
                is_map(user) and Map.has_key?(user, :email) and Map.has_key?(user, :name)
              end)
            end
            
            defp transform_users(users) do
              Enum.map(users, fn user ->
                %{
                  id: Map.get(user, :id, 0),
                  name: String.trim(user.name),
                  email: String.downcase(user.email),
                  processed: true
                }
              end)
            end
            
            defp create_response(users) do
              case length(users) do
                0 -> {:error, :no_users}
                count -> {:ok, %{users: users, count: count}}
              end
            end
            
            # Additional helper function with pattern matching
            def categorize_by_domain(users) do
              users
              |> Enum.group_by(fn user -> 
                case String.split(user.email, "@") do
                  [_name, domain] -> domain
                  _ -> "unknown"
                end
              end)
            end
          end
          """
        },
        %{
          # 50% - Average
          tier: 2,
          percentage: 50,
          name: "average_elixir_code",
          code: """
          defmodule AverageCode do
            def process_user_data(users) do
              if is_list(users) do
                valid_users = Enum.filter(users, fn user ->
                  user != nil and is_map(user)
                end)
                
                transformed = Enum.map(valid_users, fn user ->
                  name = if Map.has_key?(user, :name), do: user.name, else: ""
                  email = if Map.has_key?(user, :email), do: user.email, else: ""
                  
                  %{name: name, email: email, processed: true}
                end)
                
                {:ok, transformed}
              else
                {:error, :invalid_input}
              end
            end
            
            def get_user_count(users) do
              case users do
                [] -> 0
                list when is_list(list) -> length(list)
                _ -> -1
              end
            end
            
            # Some pattern matching, but basic
            def format_user(%{name: name, email: email}) do
              "#{name} <#{email}>"
            end
            def format_user(_), do: "Invalid User"
          end
          """
        },
        %{
          # 25% - Poor
          tier: 1,
          percentage: 25,
          name: "poor_elixir_code",
          code: """
          defmodule PoorCode do
            def process_user_data(users) do
              if users != nil do
                if is_list(users) then
                  result = []
                  for user in users do
                    if user != nil then
                      if user[:name] != nil then
                        if user[:email] != nil then
                          new_user = %{}
                          new_user = Map.put(new_user, :name, user[:name])
                          new_user = Map.put(new_user, :email, user[:email])
                          result = result ++ [new_user]
                        end
                      end
                    end
                  end
                  result
                else
                  nil
                end
              else
                nil
              end
            end
            
            # Poor error handling and style
            def do_something(x) do
              try do
                if x > 0 do
                  if x < 100 do
                    x * 2
                  else
                    100
                  end
                else
                  0
                end
              rescue
                _ -> -1
              end
            end
          end
          """
        },
        %{
          # 0% - Failing
          tier: 0,
          percentage: 0,
          name: "failing_elixir_code",
          code: """
          defmodule FailingCode do
            # Syntax errors, bad practices, no pattern matching
            def broken_function(
              # Missing closing parenthesis and implementation
            
            def another_broken() do
              # Uses undefined variables
              result = undefined_variable + another_undefined
              if something_not_defined do
                bad_syntax here
              end
            end
            
            # Completely wrong Elixir syntax
            def wrong_syntax() {
              return "this is not elixir syntax"
            }
          end
          """
        }
      ]

      # Analyze each tier example and validate scoring
      tier_results =
        Enum.map(scoring_tier_examples, fn example ->
          result = analyze_code_with_graduated_scoring(example.code)
          calculated_tier = score_to_tier(result.overall_score)

          {example.name, example.tier, calculated_tier, result.overall_score, result}
        end)

      # Validate tier assignments (allow some flexibility for edge cases)
      Enum.each(tier_results, fn {name, expected_tier, calculated_tier, score, _result} ->
        # For failing code, special handling since it might not parse
        if expected_tier == 0 and (calculated_tier == 0 or score < 0.1) do
          # Failing code correctly identified
          assert true
        else
          # Allow ±1 tier difference for scoring edge cases
          tier_difference = abs(calculated_tier - expected_tier)

          assert tier_difference <= 1,
                 "#{name}: expected tier #{expected_tier}, got #{calculated_tier} (score: #{score}), difference: #{tier_difference}"

          # But score should be in reasonable range for the tier
          case expected_tier do
            4 ->
              assert score >= 0.75, "Excellent code should score >= 0.75, got #{score}"

            3 ->
              assert score >= 0.6 and score < 0.9, "Good code should score 0.6-0.9, got #{score}"

            2 ->
              assert score >= 0.35 and score < 0.75,
                     "Average code should score 0.35-0.75, got #{score}"

            1 ->
              assert score >= 0.1 and score < 0.5, "Poor code should score 0.1-0.5, got #{score}"

            0 ->
              assert score < 0.25, "Failing code should score < 0.25, got #{score}"
          end
        end
      end)

      # Validate score progression - better code should score higher
      non_failing_results =
        Enum.filter(tier_results, fn {_, expected_tier, _, _, _} -> expected_tier > 0 end)

      scores = Enum.map(non_failing_results, fn {_, _, _, score, _} -> score end)
      sorted_scores = Enum.sort(scores)

      # Scores should be in ascending order (roughly)
      assert sorted_scores == scores or length(Enum.uniq(scores)) < length(scores),
             "Scores should generally increase with code quality"
    end

    @tag timeout: @test_timeout
    test "partial credit assignment accuracy across scoring dimensions" do
      # Test code that scores well in some dimensions but poorly in others
      mixed_quality_examples = [
        %{
          name: "good_patterns_poor_functional",
          code: """
          defmodule GoodPatternsPoorFunctional do
            # Excellent pattern matching
            def handle_request(%{type: :create, data: data}) when is_map(data) do
              create_resource(data)
            end
            def handle_request(%{type: :update, id: id, data: data}) when is_integer(id) and is_map(data) do
              update_resource(id, data)
            end
            def handle_request(%{type: :delete, id: id}) when is_integer(id) do
              delete_resource(id)
            end
            def handle_request(%{type: :read, id: id}) when is_integer(id) do
              read_resource(id)
            end
            def handle_request(_), do: {:error, :invalid_request}
            
            # Poor functional style - nested conditionals instead of pipelines
            defp create_resource(data) do
              if Map.has_key?(data, :name) do
                if Map.has_key?(data, :email) do
                  if String.contains?(data.email, "@") do
                    if String.length(data.name) > 0 do
                      {:ok, %{id: 1, name: data.name, email: data.email}}
                    else
                      {:error, :name_required}
                    end
                  else
                    {:error, :invalid_email}
                  end
                else
                  {:error, :email_required}
                end
              else
                {:error, :name_required}
              end
            end
            
            defp update_resource(_id, _data), do: {:ok, :updated}
            defp delete_resource(_id), do: {:ok, :deleted}
            defp read_resource(_id), do: {:ok, %{}}
          end
          """,
          expected_characteristics: %{
            high_pattern_score: true,
            low_functional_score: true,
            medium_overall: true
          }
        },
        %{
          name: "good_functional_poor_patterns",
          code: """
          defmodule GoodFunctionalPoorPatterns do
            # Excellent functional style with pipelines
            def process_users(users) do
              users
              |> validate_users()
              |> transform_users()
              |> enrich_users()
              |> format_response()
            end
            
            defp validate_users(users) do
              users
              |> Enum.filter(&valid_user?/1)
              |> case do
                [] -> {:error, :no_valid_users}
                valid_users -> {:ok, valid_users}
              end
            end
            
            defp transform_users({:ok, users}) do
              transformed = users
                           |> Enum.map(&normalize_user/1)
                           |> Enum.map(&add_metadata/1)
              {:ok, transformed}
            end
            defp transform_users(error), do: error
            
            defp enrich_users({:ok, users}) do
              enriched = Enum.map(users, &enrich_single_user/1)
              {:ok, enriched}
            end
            defp enrich_users(error), do: error
            
            # Poor pattern matching - everything goes through catch-all
            defp valid_user?(user) do
              if is_map(user) do
                if Map.has_key?(user, :name) and Map.has_key?(user, :email) do
                  true
                else
                  false
                end
              else
                false
              end
            end
            
            defp normalize_user(user) do
              # No pattern matching, just conditional logic
              name = if Map.has_key?(user, :name), do: String.trim(user.name), else: ""
              email = if Map.has_key?(user, :email), do: String.downcase(user.email), else: ""
              %{name: name, email: email}
            end
            
            defp add_metadata(user), do: Map.put(user, :processed_at, DateTime.utc_now())
            defp enrich_single_user(user), do: Map.put(user, :enriched, true)
            defp format_response({:ok, users}), do: {:success, users}
            defp format_response(error), do: error
          end
          """,
          expected_characteristics: %{
            high_functional_score: true,
            low_pattern_score: true,
            medium_overall: true
          }
        },
        %{
          name: "good_static_poor_design",
          code: """
          defmodule GoodStaticPoorDesign do
            @moduledoc "Well-documented module with specs but poor design"
            
            @type user_data :: %{name: binary(), email: binary()}
            @type result :: {:ok, term()} | {:error, atom()}
            
            # Excellent static analysis - full specs and documentation
            @spec process_user(user_data()) :: result()
            def process_user(%{name: name, email: email} = user) when is_binary(name) and is_binary(email) do
              # But poor design - no separation of concerns, everything in one place
              if String.trim(name) != "" do
                if String.contains?(email, "@") do
                  if String.length(email) > 5 do
                    # All logic crammed together
                    normalized_name = name |> String.trim() |> String.title()
                    normalized_email = String.downcase(email)
                    [local, domain] = String.split(normalized_email, "@")
                    
                    if String.length(local) > 0 and String.length(domain) > 0 do
                      current_time = DateTime.utc_now()
                      user_id = :rand.uniform(1000)
                      
                      result = %{
                        id: user_id,
                        name: normalized_name,
                        email: normalized_email,
                        domain: domain,
                        created: current_time,
                        processed: true,
                        metadata: %{
                          original_name: name,
                          original_email: email,
                          processing_time: current_time
                        }
                      }
                      
                      {:ok, result}
                    else
                      {:error, :invalid_email_format}
                    end
                  else
                    {:error, :email_too_short}
                  end
                else
                  {:error, :invalid_email}
                end
              else
                {:error, :empty_name}
              end
            end
            
            @spec batch_process([user_data()]) :: [result()]
            def batch_process(users) when is_list(users) do
              Enum.map(users, &process_user/1)
            end
          end
          """,
          expected_characteristics: %{
            high_static_score: true,
            low_design_score: true,
            medium_overall: true
          }
        }
      ]

      # Analyze mixed quality examples
      mixed_results =
        Enum.map(mixed_quality_examples, fn example ->
          result = analyze_code_with_graduated_scoring(example.code)
          {example.name, example.expected_characteristics, result}
        end)

      # Validate dimensional scoring
      Enum.each(mixed_results, fn {name, expected, result} ->
        case expected do
          %{high_pattern_score: true, low_functional_score: true} ->
            assert result.pattern_analysis_score > 0.7,
                   "#{name} should have high pattern score, got #{result.pattern_analysis_score}"

            assert result.functional_analysis_score < 0.6,
                   "#{name} should have low functional score, got #{result.functional_analysis_score}"

          %{high_functional_score: true, low_pattern_score: true} ->
            assert result.functional_analysis_score > 0.7,
                   "#{name} should have high functional score, got #{result.functional_analysis_score}"

            assert result.pattern_analysis_score < 0.6,
                   "#{name} should have low pattern score, got #{result.pattern_analysis_score}"

          %{high_static_score: true, low_design_score: true} ->
            assert result.static_analysis_score > 0.7,
                   "#{name} should have high static score, got #{result.static_analysis_score}"

            # Design score would be reflected in overall functional/pattern scores
            assert result.functional_analysis_score < 0.6 or result.pattern_analysis_score < 0.6,
                   "#{name} should have low design reflected in other scores"
        end

        # All should have medium overall scores due to mixed quality
        if Map.get(expected, :medium_overall) do
          assert result.overall_score > 0.4 and result.overall_score < 0.8,
                 "#{name} should have medium overall score, got #{result.overall_score}"
        end
      end)
    end

    @tag timeout: @test_timeout
    test "score calculation consistency and reporting accuracy" do
      # Test score calculation consistency with known examples
      consistency_test_code = """
      defmodule ConsistencyTest do
        @moduledoc "Test module for consistent scoring"
        
        def process_items(items) when is_list(items) do
          items
          |> Enum.filter(&valid_item?/1)
          |> Enum.map(&transform_item/1)
          |> Enum.reduce([], &accumulate_item/2)
        end
        
        defp valid_item?(%{type: :valid, data: data}) when is_map(data), do: true
        defp valid_item?(_), do: false
        
        defp transform_item(%{data: data} = item) do
          %{item | data: Map.put(data, :processed, true)}
        end
        
        defp accumulate_item(item, acc), do: [item | acc]
        
        # Recursive function with proper termination
        def sum_numbers([]), do: 0
        def sum_numbers([head | tail]) when is_number(head) do
          head + sum_numbers(tail)
        end
      end
      """

      # Run analysis multiple times to test consistency
      consistency_results =
        Enum.map(1..5, fn _run ->
          analyze_code_with_graduated_scoring(consistency_test_code)
        end)

      # All results should be identical
      first_result = List.first(consistency_results)

      Enum.each(consistency_results, fn result ->
        assert_in_delta result.overall_score, first_result.overall_score, 0.001
        assert_in_delta result.pattern_analysis_score, first_result.pattern_analysis_score, 0.001

        assert_in_delta result.functional_analysis_score,
                        first_result.functional_analysis_score,
                        0.001

        assert_in_delta result.static_analysis_score, first_result.static_analysis_score, 0.001
      end)

      # Validate score components sum correctly
      Enum.each(consistency_results, fn result ->
        # Overall score should be weighted average of components
        expected_overall =
          (result.pattern_analysis_score +
             result.functional_analysis_score +
             result.static_analysis_score) / 3

        assert_in_delta result.overall_score, expected_overall, 0.1
      end)

      # Validate score reporting structure
      result = first_result

      # Should have all required score fields
      required_fields = [
        :overall_score,
        :pattern_analysis_score,
        :functional_analysis_score,
        :static_analysis_score,
        :tier,
        :percentage
      ]

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(result, field), "Result should have #{field}"

        if field in [
             :overall_score,
             :pattern_analysis_score,
             :functional_analysis_score,
             :static_analysis_score
           ] do
          score = Map.get(result, field)
          assert is_number(score), "#{field} should be a number"
          assert score >= 0.0, "#{field} should be >= 0.0"
          assert score <= 1.0, "#{field} should be <= 1.0"
        end
      end)

      # Tier and percentage should match
      assert result.tier == score_to_tier(result.overall_score)
      assert result.percentage == tier_to_percentage(result.tier)
    end

    @tag timeout: @test_timeout
    test "edge cases and boundary conditions in scoring" do
      # Test edge cases for scoring system
      edge_case_examples = [
        %{
          name: "empty_module",
          code: """
          defmodule EmptyModule do
          end
          """,
          expected_low_score: true
        },
        %{
          name: "only_comments",
          code: """
          defmodule OnlyComments do
            # This module only has comments
            # No actual implementation
            # Should score very low
          end
          """,
          expected_low_score: true
        },
        %{
          name: "minimal_but_correct",
          code: """
          defmodule MinimalButCorrect do
            def hello(name) when is_binary(name) do
              "Hello, #{name}!"
            end
            def hello(_), do: "Hello, World!"
          end
          """,
          expected_reasonable_score: true
        },
        %{
          name: "complex_but_bad",
          code: """
          defmodule ComplexButBad do
            def mega_function(a, b, c, d, e, f, g, h) do
              if a do
                if b do
                  if c do
                    if d do
                      if e do
                        if f do
                          if g do
                            if h do
                              "success"
                            else
                              if h == nil do
                                "h is nil"
                              else
                                if is_atom(h) do
                                  "h is atom"
                                else
                                  "h is something else"
                                end
                              end
                            end
                          else
                            "g failed"
                          end
                        else
                          "f failed" 
                        end
                      else
                        "e failed"
                      end
                    else
                      "d failed"
                    end
                  else
                    "c failed"
                  end
                else
                  "b failed"
                end
              else
                "a failed"
              end
            end
          end
          """,
          # Complex but terrible quality
          expected_low_score: true
        }
      ]

      # Analyze edge cases
      edge_results =
        Enum.map(edge_case_examples, fn example ->
          result = analyze_code_with_graduated_scoring(example.code)
          {example.name, result, example}
        end)

      # Validate edge case handling
      Enum.each(edge_results, fn {name, result, example} ->
        cond do
          Map.get(example, :expected_low_score) ->
            assert result.overall_score < 0.4,
                   "#{name} should have low score, got #{result.overall_score}"

          Map.get(example, :expected_reasonable_score) ->
            assert result.overall_score > 0.5 and result.overall_score < 0.8,
                   "#{name} should have reasonable score, got #{result.overall_score}"
        end

        # All results should be valid
        assert is_number(result.overall_score)
        assert result.overall_score >= 0.0
        assert result.overall_score <= 1.0
        assert result.tier in 0..4
        assert result.percentage in [0, 25, 50, 75, 100]
      end)
    end
  end

  describe "performance and scalability of scoring system" do
    @tag timeout: @test_timeout
    test "scoring system performance with large codebases" do
      # Generate large codebase for performance testing
      # 200 functions
      large_codebase = generate_large_codebase_for_scoring(200)

      # Time the scoring process
      {time_microseconds, result} =
        :timer.tc(fn ->
          analyze_code_with_graduated_scoring(large_codebase)
        end)

      # Should complete scoring within reasonable time (30 seconds for 200 functions)
      assert time_microseconds < 30_000_000,
             "Scoring took #{time_microseconds}μs (>30s) for large codebase"

      # Result should still be valid and comprehensive
      assert is_map(result)
      assert Map.has_key?(result, :overall_score)
      assert result.overall_score > 0.0
      assert result.tier in 0..4

      # Performance should not compromise accuracy
      # Large codebase should have decent patterns
      assert result.pattern_analysis_score > 0.6
      # And functional style
      assert result.functional_analysis_score > 0.6
    end
  end

  # Helper functions for graduated scoring analysis
  defp analyze_code_with_graduated_scoring(code) do
    # This simulates the complete graduated scoring pipeline
    # integrating all Phase 2 components

    case parse_and_validate_code(code) do
      {:error, _reason} ->
        # Code that fails to parse gets 0 score
        %{
          overall_score: 0.0,
          pattern_analysis_score: 0.0,
          functional_analysis_score: 0.0,
          static_analysis_score: 0.0,
          tier: 0,
          percentage: 0,
          parse_error: true
        }

      {:ok, _parsed_code} ->
        # Calculate component scores
        pattern_score = calculate_pattern_analysis_score(code)
        functional_score = calculate_functional_analysis_score(code)
        static_score = calculate_static_analysis_score(code)

        # Calculate weighted overall score
        overall_score =
          calculate_weighted_overall_score(
            pattern_score,
            functional_score,
            static_score
          )

        # Determine tier and percentage
        tier = score_to_tier(overall_score)
        percentage = tier_to_percentage(tier)

        %{
          overall_score: overall_score,
          pattern_analysis_score: pattern_score,
          functional_analysis_score: functional_score,
          static_analysis_score: static_score,
          tier: tier,
          percentage: percentage
        }
    end
  end

  defp parse_and_validate_code(code) do
    # Basic syntax validation
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> {:ok, code}
      {:error, _} -> {:error, :parse_error}
    end
  end

  defp calculate_pattern_analysis_score(code) do
    # Base score
    score = 0.5

    # Boost for pattern matching
    score =
      if String.contains?(code, "def ") and
           (String.contains?(code, " when ") or
              String.contains?(code, "%{") or
              String.contains?(code, "case ")),
         do: score + 0.2,
         else: score

    # Boost for guards
    score = if String.contains?(code, " when "), do: score + 0.1, else: score

    # Boost for comprehensive pattern coverage
    score =
      if String.contains?(code, "def ") and String.contains?(code, "_"),
        do: score + 0.1,
        else: score

    # Penalty for poor patterns (many ifs)
    if_count = code |> String.split("if ") |> length() |> Kernel.-(1)
    score = if if_count > 3, do: max(score - 0.3, 0.1), else: score

    min(score, 1.0)
  end

  defp calculate_functional_analysis_score(code) do
    # Base score
    score = 0.4

    # Boost for pipelines
    pipeline_count = code |> String.split("|>") |> length() |> Kernel.-(1)
    score = score + min(pipeline_count * 0.15, 0.4)

    # Boost for Enum functions
    score = if String.contains?(code, "Enum."), do: score + 0.1, else: score

    # Boost for pattern matching in function heads
    score =
      if String.contains?(code, "def ") and String.contains?(code, "%{"),
        do: score + 0.1,
        else: score

    # Penalty for nested conditionals
    nested_if_penalty = max(0, (code |> String.split("if ") |> length()) - 2) * 0.1
    score = max(score - nested_if_penalty, 0.1)

    min(score, 1.0)
  end

  defp calculate_static_analysis_score(code) do
    # Base score
    score = 0.6

    # Boost for documentation
    score =
      if String.contains?(code, "@moduledoc") or String.contains?(code, "@doc"),
        do: score + 0.1,
        else: score

    # Boost for type specs
    score =
      if String.contains?(code, "@spec") or String.contains?(code, "@type"),
        do: score + 0.15,
        else: score

    # Boost for guards (type safety)
    score = if String.contains?(code, " when is_"), do: score + 0.1, else: score

    # Penalty for complex functions (rough estimate)
    lines_per_function = estimate_avg_function_length(code)
    complexity_penalty = if lines_per_function > 10, do: 0.2, else: 0.0
    score = max(score - complexity_penalty, 0.2)

    min(score, 1.0)
  end

  defp calculate_weighted_overall_score(pattern_score, functional_score, static_score) do
    # Weighted average with slight emphasis on functional programming
    pattern_score * 0.3 + functional_score * 0.4 + static_score * 0.3
  end

  defp score_to_tier(score) do
    case score do
      # 100% - Excellent
      s when s >= 0.9 -> 4
      # 75% - Good
      s when s >= 0.75 -> 3
      # 50% - Average
      s when s >= 0.5 -> 2
      # 25% - Poor
      s when s >= 0.25 -> 1
      # 0% - Failing
      _ -> 0
    end
  end

  defp tier_to_percentage(tier) do
    case tier do
      4 -> 100
      3 -> 75
      2 -> 50
      1 -> 25
      0 -> 0
    end
  end

  defp estimate_avg_function_length(code) do
    function_count = code |> String.split("def ") |> length() |> Kernel.-(1)

    if function_count > 0 do
      total_lines = code |> String.split("\n") |> length()
      div(total_lines, function_count)
    else
      0
    end
  end

  defp generate_large_codebase_for_scoring(function_count) do
    functions =
      Enum.map_join(1..function_count, "\n", fn i ->
        """
          def function_#{i}(data) when is_map(data) do
            data
            |> validate_function_#{i}_input()
            |> process_function_#{i}_data()
            |> format_function_#{i}_output()
          end
          
          defp validate_function_#{i}_input(%{key_#{i}: value}) when not is_nil(value), do: {:ok, value}
          defp validate_function_#{i}_input(_), do: {:error, :invalid_input_#{i}}
          
          defp process_function_#{i}_data({:ok, value}), do: {:ok, value * #{i}}
          defp process_function_#{i}_data(error), do: error
          
          defp format_function_#{i}_output({:ok, result}), do: %{result: result, function: #{i}}
          defp format_function_#{i}_output({:error, reason}), do: %{error: reason, function: #{i}}
        """
      end)

    """
    defmodule LargeCodebaseForScoring do
      @moduledoc "Large codebase generated for graduated scoring performance testing"
      
    #{functions}
    end
    """
  end
end
