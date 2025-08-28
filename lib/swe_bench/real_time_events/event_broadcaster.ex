defmodule SweBench.RealTimeEvents.EventBroadcaster do
  @moduledoc """
  Handles broadcasting of specific event types with proper formatting and routing.

  Provides convenience functions for broadcasting evaluation, dataset, and system
  events with appropriate channel routing and payload formatting.
  """

  alias SweBench.RealTimeEvents.EventCoordinator

  @doc """
  Broadcasts evaluation submission event.
  """
  def broadcast_evaluation_submitted(evaluation_data) do
    payload = %{
      evaluation_id: evaluation_data.id,
      model: evaluation_data.model,
      repository: evaluation_data.repository,
      submitted_by: evaluation_data.submitted_by,
      submitted_at: evaluation_data.submitted_at,
      status: :queued
    }

    EventCoordinator.broadcast_event(:evaluation_submitted, payload,
      source: :evaluation_system,
      correlation_id: evaluation_data.id
    )
  end

  @doc """
  Broadcasts real-time evaluation progress update.
  """
  def broadcast_evaluation_progress(evaluation_id, progress_data) do
    payload = %{
      evaluation_id: evaluation_id,
      progress_percentage: progress_data.percentage,
      current_stage: progress_data.stage,
      stage_details: progress_data.details,
      estimated_completion: progress_data.estimated_completion,
      tests_completed: progress_data.tests_completed || 0,
      tests_total: progress_data.tests_total || 0
    }

    EventCoordinator.broadcast_event(:progress_update, payload,
      source: :evaluation_engine,
      correlation_id: evaluation_id
    )
  end

  @doc """
  Broadcasts evaluation completion with results.
  """
  def broadcast_evaluation_completed(evaluation_id, results_data) do
    payload = %{
      evaluation_id: evaluation_id,
      model: results_data.model,
      repository: results_data.repository,
      overall_score: results_data.score,
      completion_time: results_data.completed_at,
      test_results: %{
        total_tests: results_data.total_tests,
        passed_tests: results_data.passed_tests,
        failed_tests: results_data.failed_tests
      },
      advanced_analysis: %{
        distributed_score: results_data.distributed_score,
        concurrent_score: results_data.concurrent_score,
        performance_score: results_data.performance_score,
        partial_credit_score: results_data.partial_credit_score
      }
    }

    EventCoordinator.broadcast_event(:evaluation_completed, payload,
      source: :evaluation_system,
      correlation_id: evaluation_id
    )
  end

  @doc """
  Broadcasts test execution results in real-time.
  """
  def broadcast_test_executed(evaluation_id, test_data) do
    payload = %{
      evaluation_id: evaluation_id,
      test_name: test_data.name,
      test_result: test_data.result,
      execution_time: test_data.execution_time,
      error_message: test_data.error_message,
      test_output: test_data.output
    }

    EventCoordinator.broadcast_event(:test_executed, payload,
      source: :test_runner,
      correlation_id: evaluation_id
    )
  end

  @doc """
  Broadcasts task instance updates for dataset changes.
  """
  def broadcast_task_instance_updated(task_instance) do
    payload = %{
      task_id: task_instance.id,
      repository: task_instance.repository,
      complexity: task_instance.complexity,
      validation_status: task_instance.validation_status,
      last_updated: task_instance.updated_at
    }

    EventCoordinator.broadcast_event(:task_instance_added, payload, source: :dataset_manager)
  end

  @doc """
  Broadcasts repository status changes.
  """
  def broadcast_repository_updated(repository_name, status_data) do
    payload = %{
      repository_name: repository_name,
      status: status_data.status,
      last_evaluation: status_data.last_evaluation,
      task_count: status_data.task_count,
      average_score: status_data.average_score,
      updated_at: DateTime.utc_now()
    }

    EventCoordinator.broadcast_event(:repository_updated, payload, source: :repository_manager)
  end

  @doc """
  Broadcasts system health events.
  """
  def broadcast_system_health(health_data) do
    payload = %{
      system_status: health_data.status,
      resource_usage: health_data.resource_usage,
      active_evaluations: health_data.active_evaluations,
      queue_depth: health_data.queue_depth,
      performance_metrics: health_data.performance_metrics,
      timestamp: DateTime.utc_now()
    }

    EventCoordinator.broadcast_event(:health_check, payload, source: :system_monitor)
  end

  @doc """
  Broadcasts dataset version release events.
  """
  def broadcast_dataset_released(dataset_version, release_data) do
    payload = %{
      version: dataset_version,
      repository_count: release_data.repository_count,
      task_instance_count: release_data.task_instance_count,
      release_notes: release_data.release_notes,
      download_url: release_data.download_url,
      released_at: DateTime.utc_now()
    }

    EventCoordinator.broadcast_event(:dataset_version_released, payload, source: :dataset_manager)
  end

  @doc """
  Broadcasts evaluation error or cancellation events.
  """
  def broadcast_evaluation_error(evaluation_id, error_data) do
    payload = %{
      evaluation_id: evaluation_id,
      error_type: error_data.type,
      error_message: error_data.message,
      error_details: error_data.details,
      recovery_possible: error_data.recovery_possible,
      occurred_at: DateTime.utc_now()
    }

    EventCoordinator.broadcast_event(:evaluation_error, payload,
      source: :evaluation_system,
      correlation_id: evaluation_id
    )
  end

  @doc """
  Broadcasts maintenance and system notices.
  """
  def broadcast_maintenance_notice(notice_data) do
    payload = %{
      notice_type: notice_data.type,
      title: notice_data.title,
      message: notice_data.message,
      scheduled_time: notice_data.scheduled_time,
      expected_duration: notice_data.duration,
      impact_level: notice_data.impact_level
    }

    EventCoordinator.broadcast_event(:maintenance_notice, payload, source: :system_admin)
  end
end
