defmodule SweBench.PatternAnalysis.OTP.ValidationSchemas do
  @moduledoc """
  Schema definitions for OTP behavior validation results.

  Provides structured schemas for GenServer, Supervisor, Behavior, and Process
  validation results that integrate with the existing analysis pipeline.
  """

  @type genserver_validation :: %{
          compliance_score: non_neg_integer(),
          required_callbacks: [atom()],
          missing_callbacks: [atom()],
          return_value_issues: [String.t()],
          state_management_score: non_neg_integer(),
          callback_implementations: %{atom() => callback_validation()},
          overall_otp_compliance: boolean()
        }

  @type callback_validation :: %{
          implemented: boolean(),
          correct_arity: boolean(),
          return_value_valid: boolean(),
          issues: [String.t()]
        }

  @type supervisor_validation :: %{
          tree_structure_valid: boolean(),
          restart_strategy_appropriate: boolean(),
          child_spec_compliance: non_neg_integer(),
          restart_intensity_valid: boolean(),
          restart_period_valid: boolean(),
          supervisor_type: atom(),
          child_count: non_neg_integer(),
          issues: [String.t()]
        }

  @type behavior_validation :: %{
          custom_behaviors_count: non_neg_integer(),
          callback_compliance_score: non_neg_integer(),
          behavior_declarations: [atom()],
          implemented_callbacks: [atom()],
          missing_callbacks: [atom()],
          optional_callbacks_implemented: [atom()],
          composition_patterns: [String.t()],
          issues: [String.t()]
        }

  @type process_metrics :: %{
          spawn_rate: float(),
          avg_message_queue_depth: float(),
          restart_count: non_neg_integer(),
          memory_efficiency_score: non_neg_integer(),
          process_count: non_neg_integer(),
          zombie_processes: non_neg_integer(),
          memory_usage_mb: float(),
          collected_at: DateTime.t()
        }

  @type otp_validation_result :: %{
          genserver: genserver_validation() | nil,
          supervisor: supervisor_validation() | nil,
          behaviors: behavior_validation() | nil,
          process_metrics: process_metrics() | nil,
          overall_otp_score: non_neg_integer(),
          validation_timestamp: DateTime.t(),
          analysis_duration_ms: non_neg_integer()
        }

  @doc """
  Creates a new empty OTP validation result structure.
  """
  def new_validation_result do
    %{
      genserver: nil,
      supervisor: nil,
      behaviors: nil,
      process_metrics: nil,
      overall_otp_score: 0,
      validation_timestamp: DateTime.utc_now(),
      analysis_duration_ms: 0
    }
  end

  @doc """
  Creates a new empty GenServer validation structure.
  """
  def new_genserver_validation do
    %{
      compliance_score: 0,
      required_callbacks: [],
      missing_callbacks: [],
      return_value_issues: [],
      state_management_score: 0,
      callback_implementations: %{},
      overall_otp_compliance: false
    }
  end

  @doc """
  Creates a new empty Supervisor validation structure.
  """
  def new_supervisor_validation do
    %{
      tree_structure_valid: false,
      restart_strategy_appropriate: false,
      child_spec_compliance: 0,
      restart_intensity_valid: false,
      restart_period_valid: false,
      supervisor_type: :unknown,
      child_count: 0,
      issues: []
    }
  end

  @doc """
  Creates a new empty Behavior validation structure.
  """
  def new_behavior_validation do
    %{
      custom_behaviors_count: 0,
      callback_compliance_score: 0,
      behavior_declarations: [],
      implemented_callbacks: [],
      missing_callbacks: [],
      optional_callbacks_implemented: [],
      composition_patterns: [],
      issues: []
    }
  end

  @doc """
  Creates a new empty Process metrics structure.
  """
  def new_process_metrics do
    %{
      spawn_rate: 0.0,
      avg_message_queue_depth: 0.0,
      restart_count: 0,
      memory_efficiency_score: 0,
      process_count: 0,
      zombie_processes: 0,
      memory_usage_mb: 0.0,
      collected_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new callback validation structure.
  """
  def new_callback_validation do
    %{
      implemented: false,
      correct_arity: false,
      return_value_valid: false,
      issues: []
    }
  end

  @doc """
  Validates a GenServer validation result structure.
  """
  def validate_genserver_result(result) when is_map(result) do
    required_keys = [
      :compliance_score,
      :required_callbacks,
      :missing_callbacks,
      :return_value_issues,
      :state_management_score,
      :callback_implementations,
      :overall_otp_compliance
    ]

    case check_required_keys(result, required_keys) do
      :ok ->
        case validate_scores(result, [:compliance_score, :state_management_score]) do
          :ok -> {:ok, result}
          error -> error
        end

      error ->
        error
    end
  end

  def validate_genserver_result(_), do: {:error, :invalid_genserver_result}

  @doc """
  Validates a Supervisor validation result structure.
  """
  def validate_supervisor_result(result) when is_map(result) do
    required_keys = [
      :tree_structure_valid,
      :restart_strategy_appropriate,
      :child_spec_compliance,
      :restart_intensity_valid,
      :restart_period_valid,
      :supervisor_type,
      :child_count,
      :issues
    ]

    case check_required_keys(result, required_keys) do
      :ok ->
        case validate_scores(result, [:child_spec_compliance]) do
          :ok -> {:ok, result}
          error -> error
        end

      error ->
        error
    end
  end

  def validate_supervisor_result(_), do: {:error, :invalid_supervisor_result}

  @doc """
  Validates a Behavior validation result structure.
  """
  def validate_behavior_result(result) when is_map(result) do
    required_keys = [
      :custom_behaviors_count,
      :callback_compliance_score,
      :behavior_declarations,
      :implemented_callbacks,
      :missing_callbacks,
      :optional_callbacks_implemented,
      :composition_patterns,
      :issues
    ]

    case check_required_keys(result, required_keys) do
      :ok ->
        case validate_scores(result, [:callback_compliance_score]) do
          :ok -> {:ok, result}
          error -> error
        end

      error ->
        error
    end
  end

  def validate_behavior_result(_), do: {:error, :invalid_behavior_result}

  @doc """
  Validates a Process metrics result structure.
  """
  def validate_process_metrics(result) when is_map(result) do
    required_keys = [
      :spawn_rate,
      :avg_message_queue_depth,
      :restart_count,
      :memory_efficiency_score,
      :process_count,
      :zombie_processes,
      :memory_usage_mb,
      :collected_at
    ]

    case check_required_keys(result, required_keys) do
      :ok ->
        case validate_scores(result, [:memory_efficiency_score]) do
          :ok -> {:ok, result}
          error -> error
        end

      error ->
        error
    end
  end

  def validate_process_metrics(_), do: {:error, :invalid_process_metrics}

  @doc """
  Calculates overall OTP score from component validation results.
  """
  def calculate_overall_score(%{genserver: gs, supervisor: sv, behaviors: bh}) do
    scores = []

    scores =
      if gs, do: [gs.compliance_score | scores], else: scores

    scores =
      if sv, do: [sv.child_spec_compliance | scores], else: scores

    scores =
      if bh, do: [bh.callback_compliance_score | scores], else: scores

    if scores == [] do
      0
    else
      round(Enum.sum(scores) / length(scores))
    end
  end

  # Private helper functions

  defp check_required_keys(map, keys) do
    missing_keys =
      keys
      |> Enum.reject(&Map.has_key?(map, &1))

    if missing_keys == [] do
      :ok
    else
      {:error, {:missing_keys, missing_keys}}
    end
  end

  defp validate_scores(map, score_keys) do
    invalid_scores =
      score_keys
      |> Enum.reject(fn key ->
        score = Map.get(map, key, -1)
        is_integer(score) and score >= 0 and score <= 100
      end)

    if invalid_scores == [] do
      :ok
    else
      {:error, {:invalid_scores, invalid_scores}}
    end
  end
end
