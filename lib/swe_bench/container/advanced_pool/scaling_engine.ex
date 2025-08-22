defmodule SweBench.Container.AdvancedPool.ScalingEngine do
  @moduledoc """
  Dynamic scaling engine for container pools.

  Implements predictive scaling algorithms, resource optimization,
  and intelligent capacity management for high-throughput evaluations.
  """

  use GenServer
  require Logger

  alias SweBench.Container.AdvancedPool.PoolSupervisor

  defstruct [
    :scaling_policies,
    :metrics_window,
    :scaling_history,
    :predictive_model,
    :resource_constraints
  ]

  @doc """
  Starts the scaling engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Evaluates scaling needs for a specific pool.
  """
  def evaluate_scaling_needs(pool_id) do
    GenServer.call(__MODULE__, {:evaluate_scaling, pool_id})
  end

  @doc """
  Gets scaling recommendations for all pools.
  """
  def get_scaling_recommendations do
    GenServer.call(__MODULE__, :get_scaling_recommendations)
  end

  @doc """
  Updates scaling policies and thresholds.
  """
  def update_scaling_policies(new_policies) do
    GenServer.cast(__MODULE__, {:update_policies, new_policies})
  end

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    # 5 minutes
    metrics_window = Keyword.get(opts, :metrics_window, 300_000)

    state = %__MODULE__{
      scaling_policies: default_scaling_policies(),
      metrics_window: metrics_window,
      scaling_history: %{},
      predictive_model: initialize_predictive_model(),
      resource_constraints: initialize_resource_constraints(opts)
    }

    Logger.info("ScalingEngine started with metrics_window=#{metrics_window}ms")

    # Schedule periodic scaling evaluation
    schedule_scaling_evaluation()

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:evaluate_scaling, pool_id}, _from, state) do
    scaling_decision = evaluate_pool_scaling(pool_id, state)

    # Record scaling decision in history
    new_history = record_scaling_decision(pool_id, scaling_decision, state.scaling_history)
    new_state = %{state | scaling_history: new_history}

    {:reply, scaling_decision, new_state}
  end

  @impl GenServer
  def handle_call(:get_scaling_recommendations, _from, state) do
    recommendations = generate_all_scaling_recommendations(state)
    {:reply, recommendations, state}
  end

  @impl GenServer
  def handle_cast({:update_policies, new_policies}, state) do
    Logger.info("Updating scaling policies")

    merged_policies = Map.merge(state.scaling_policies, new_policies)
    new_state = %{state | scaling_policies: merged_policies}

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:evaluate_all_pools, state) do
    Logger.debug("Performing scheduled scaling evaluation")

    new_state = evaluate_all_pools_scaling(state)

    # Schedule next evaluation
    schedule_scaling_evaluation()

    {:noreply, new_state}
  end

  # Private helper functions

  defp default_scaling_policies do
    %{
      # Scale up when utilization > 80%
      scale_up_threshold: 80,
      # Scale down when utilization < 30%
      scale_down_threshold: 30,
      # 2 minutes
      scale_up_cooldown: 120_000,
      # 5 minutes
      scale_down_cooldown: 300_000,
      max_scale_up_containers: 5,
      max_scale_down_containers: 3
    }
  end

  defp initialize_predictive_model do
    %{
      enabled: true,
      # 10 minutes
      prediction_window: 600_000,
      confidence_threshold: 0.7,
      learning_rate: 0.1
    }
  end

  defp initialize_resource_constraints(opts) do
    %{
      max_total_containers: Keyword.get(opts, :max_total_containers, 100),
      max_memory_gb: Keyword.get(opts, :max_memory_gb, 50),
      max_cpu_cores: Keyword.get(opts, :max_cpu_cores, 32)
    }
  end

  defp schedule_scaling_evaluation do
    # Every minute
    Process.send_after(self(), :evaluate_all_pools, 60_000)
  end

  defp evaluate_pool_scaling(pool_id, state) do
    # Get current pool metrics
    pool_metrics = get_pool_metrics(pool_id)

    # Calculate utilization and demand
    utilization = calculate_pool_utilization(pool_metrics)
    demand_trend = analyze_demand_trend(pool_id, state.scaling_history)

    # Make scaling decision
    scaling_decision = make_scaling_decision(utilization, demand_trend, state.scaling_policies)

    # Check resource constraints
    constrained_decision =
      apply_resource_constraints(scaling_decision, state.resource_constraints)

    %{
      pool_id: pool_id,
      current_utilization: utilization,
      demand_trend: demand_trend,
      scaling_action: constrained_decision.action,
      scale_amount: constrained_decision.amount,
      reasoning: constrained_decision.reasoning,
      timestamp: DateTime.utc_now()
    }
  end

  defp get_pool_metrics(_pool_id) do
    # Placeholder for pool metrics retrieval
    %{
      container_count: 10,
      checked_out_count: 8,
      warm_count: 2,
      average_wait_time: 500,
      error_rate: 0.02
    }
  end

  defp calculate_pool_utilization(metrics) do
    if metrics.container_count > 0 do
      metrics.checked_out_count / metrics.container_count * 100
    else
      0
    end
  end

  defp analyze_demand_trend(_pool_id, _history) do
    # Placeholder for demand trend analysis
    # Would analyze historical scaling events and usage patterns
    %{
      trend: :increasing,
      confidence: 0.8,
      predicted_utilization: 85
    }
  end

  defp make_scaling_decision(utilization, demand_trend, policies) do
    cond do
      utilization > policies.scale_up_threshold ->
        %{
          action: :scale_up,
          amount: calculate_scale_up_amount(utilization, demand_trend, policies)
        }

      utilization < policies.scale_down_threshold ->
        %{
          action: :scale_down,
          amount: calculate_scale_down_amount(utilization, demand_trend, policies)
        }

      true ->
        %{action: :no_action, amount: 0}
    end
  end

  defp calculate_scale_up_amount(utilization, demand_trend, policies) do
    base_amount = round((utilization - policies.scale_up_threshold) / 20)
    trend_multiplier = if demand_trend.trend == :increasing, do: 1.5, else: 1.0

    amount = round(base_amount * trend_multiplier)
    min(amount, policies.max_scale_up_containers)
  end

  defp calculate_scale_down_amount(utilization, demand_trend, policies) do
    base_amount = round((policies.scale_down_threshold - utilization) / 15)
    trend_multiplier = if demand_trend.trend == :decreasing, do: 1.3, else: 0.8

    amount = round(base_amount * trend_multiplier)
    min(amount, policies.max_scale_down_containers)
  end

  defp apply_resource_constraints(decision, _constraints) do
    # Apply global resource constraints to scaling decision
    constrained_decision =
      Map.merge(decision, %{
        reasoning: ["Based on utilization analysis"],
        constrained: false
      })

    # Would check actual resource availability in production
    constrained_decision
  end

  defp record_scaling_decision(pool_id, decision, history) do
    pool_history = Map.get(history, pool_id, [])
    new_entry = Map.put(decision, :recorded_at, DateTime.utc_now())
    # Keep last 100 decisions
    updated_history = [new_entry | Enum.take(pool_history, 99)]

    Map.put(history, pool_id, updated_history)
  end

  defp generate_all_scaling_recommendations(state) do
    # Get all pools and generate recommendations
    case PoolSupervisor.list_pools() do
      {:ok, pools} ->
        recommendations =
          Map.new(pools, fn pool ->
            recommendation = evaluate_pool_scaling(pool.pool_id, state)
            {pool.pool_id, recommendation}
          end)

        %{
          recommendations: recommendations,
          total_pools: length(pools),
          generated_at: DateTime.utc_now()
        }
    end
  end

  defp evaluate_all_pools_scaling(state) do
    case generate_all_scaling_recommendations(state) do
      recommendations ->
        # Log any urgent scaling needs
        urgent_actions =
          Enum.filter(recommendations.recommendations, fn {_pool_id, rec} ->
            rec.scaling_action in [:scale_up, :scale_down]
          end)

        if length(urgent_actions) > 0 do
          Logger.info("Scaling recommendations: #{length(urgent_actions)} pools need scaling")
        end

        state
    end
  end
end
