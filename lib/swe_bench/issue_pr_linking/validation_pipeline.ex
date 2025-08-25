defmodule SweBench.IssuePrLinking.ValidationPipeline do
  @moduledoc """
  Validation pipeline for Issue-PR relationships.

  Implements multi-stage validation to ensure relationship quality and
  accuracy before persisting to database and using for benchmark generation.
  """

  use GenServer
  require Logger

  @minimum_confidence 0.5
  @auto_validate_threshold 0.85

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validates a single issue-PR relationship.
  """
  def validate_relationship(correlation) do
    GenServer.call(__MODULE__, {:validate, correlation})
  end

  @doc """
  Gets validation pipeline statistics.
  """
  def get_validation_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      validations_processed: 0,
      validations_passed: 0,
      validations_failed: 0,
      avg_validation_time: 0.0
    }

    Logger.info("Validation pipeline started")
    {:ok, state}
  end

  @impl true
  def handle_call({:validate, correlation}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      correlation
      |> validate_confidence_threshold()
      |> validate_temporal_consistency()
      |> validate_relationship_logic()
      |> determine_validation_status()

    processing_time = System.monotonic_time(:millisecond) - start_time
    updated_state = update_validation_stats(state, processing_time, result)

    {:reply, result, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  # Private validation functions

  defp validate_confidence_threshold(correlation) do
    if correlation.confidence_score >= @minimum_confidence do
      add_validation_result(
        correlation,
        :confidence_threshold,
        :passed,
        "Confidence #{correlation.confidence_score} meets minimum threshold"
      )
    else
      add_validation_result(
        correlation,
        :confidence_threshold,
        :failed,
        "Confidence #{correlation.confidence_score} below minimum threshold #{@minimum_confidence}"
      )
    end
  end

  defp validate_temporal_consistency(correlation) do
    issue_created = parse_github_datetime(correlation.issue["created_at"])
    pr_created = parse_github_datetime(correlation.pull_request["created_at"])

    case {issue_created, pr_created} do
      {%DateTime{} = issue_time, %DateTime{} = pr_time} ->
        if DateTime.compare(issue_time, pr_time) in [:lt, :eq] do
          add_validation_result(
            correlation,
            :temporal_consistency,
            :passed,
            "Issue created before or at same time as PR"
          )
        else
          add_validation_result(
            correlation,
            :temporal_consistency,
            :warning,
            "PR created before issue - unusual but possible"
          )
        end

      _ ->
        add_validation_result(
          correlation,
          :temporal_consistency,
          :warning,
          "Unable to parse creation timestamps"
        )
    end
  end

  defp validate_relationship_logic(correlation) do
    case correlation.relationship_type do
      type when type in [:fixes, :closes, :addresses] ->
        validate_fix_relationship(correlation)

      :references ->
        validate_reference_relationship(correlation)

      :related_to ->
        validate_relation_relationship(correlation)

      _ ->
        add_validation_result(
          correlation,
          :relationship_logic,
          :warning,
          "Unknown relationship type: #{correlation.relationship_type}"
        )
    end
  end

  defp validate_fix_relationship(correlation) do
    evidence = Map.get(correlation, :evidence, %{})
    reference_strength = get_in(evidence, [:reference_strength])

    case reference_strength do
      strength when strength in [:strong, :very_strong] ->
        add_validation_result(
          correlation,
          :relationship_logic,
          :passed,
          "Strong evidence for fix relationship"
        )

      :moderate ->
        add_validation_result(
          correlation,
          :relationship_logic,
          :passed,
          "Moderate evidence for fix relationship"
        )

      _ ->
        add_validation_result(
          correlation,
          :relationship_logic,
          :warning,
          "Weak evidence for fix relationship"
        )
    end
  end

  defp validate_reference_relationship(correlation) do
    # References are more permissive but still need some evidence
    if correlation.confidence_score >= 0.6 do
      add_validation_result(
        correlation,
        :relationship_logic,
        :passed,
        "Sufficient confidence for reference relationship"
      )
    else
      add_validation_result(
        correlation,
        :relationship_logic,
        :warning,
        "Low confidence for reference relationship"
      )
    end
  end

  defp validate_relation_relationship(correlation) do
    # Related relationships are most permissive
    add_validation_result(
      correlation,
      :relationship_logic,
      :passed,
      "Related relationship validation passed"
    )
  end

  defp determine_validation_status(correlation) do
    validation_results = Map.get(correlation, :validation_results, [])

    failed_validations = Enum.filter(validation_results, &(&1.status == :failed))
    warning_validations = Enum.filter(validation_results, &(&1.status == :warning))

    final_status =
      cond do
        not Enum.empty?(failed_validations) ->
          :rejected

        correlation.confidence_score >= @auto_validate_threshold and
            Enum.empty?(warning_validations) ->
          :validated

        correlation.confidence_score >= 0.7 and length(warning_validations) <= 1 ->
          :pending

        true ->
          :uncertain
      end

    final_correlation = Map.put(correlation, :final_validation_status, final_status)

    case final_status do
      :rejected ->
        {:error, {:validation_failed, final_correlation}}

      _ ->
        {:ok, final_correlation}
    end
  end

  defp add_validation_result(correlation, stage, status, message) do
    validation_result = %{
      stage: stage,
      status: status,
      message: message,
      timestamp: DateTime.utc_now()
    }

    existing_results = Map.get(correlation, :validation_results, [])
    Map.put(correlation, :validation_results, [validation_result | existing_results])
  end

  defp parse_github_datetime(nil), do: nil

  defp parse_github_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp update_validation_stats(state, processing_time, result) do
    new_total = state.validations_processed + 1

    {new_passed, new_failed} =
      case result do
        {:ok, _} -> {state.validations_passed + 1, state.validations_failed}
        {:error, _} -> {state.validations_passed, state.validations_failed + 1}
      end

    new_avg_time =
      if new_total > 1 do
        (state.avg_validation_time * (new_total - 1) + processing_time) / new_total
      else
        processing_time
      end

    %{
      state
      | validations_processed: new_total,
        validations_passed: new_passed,
        validations_failed: new_failed,
        avg_validation_time: new_avg_time
    }
  end
end
