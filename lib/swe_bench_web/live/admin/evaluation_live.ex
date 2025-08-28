defmodule SweBenchWeb.Admin.EvaluationLive do
  @moduledoc """
  Admin-only evaluation submission and monitoring LiveView.

  Provides authenticated admin users with evaluation submission capabilities,
  real-time progress monitoring, and system oversight tools.
  """

  use SweBenchWeb, :live_view

  # Future: Will integrate with actual evaluation system
  # alias SweBench.{Repo, TaskInstances}
  alias SweBenchWeb.Components.{EvaluationForm, ProgressTracker, LogStreamer}

  @impl true
  def mount(_params, _session, socket) do
    # Verify admin authentication
    case socket.assigns[:current_user] do
      %{role: :admin} ->
        if connected?(socket) do
          # Subscribe to admin-specific channels
          Phoenix.PubSub.subscribe(SweBench.PubSub, "admin_evaluations")
          Phoenix.PubSub.subscribe(SweBench.PubSub, "system_monitoring")
        end

        socket =
          socket
          |> assign(:page_title, "Admin | Evaluation Management")
          |> assign(:active_evaluations, [])
          |> assign(:available_models, get_available_models())
          |> assign(:available_repositories, get_available_repositories())
          |> assign(:system_status, %{healthy: true, load: :normal})
          |> load_admin_data()

        {:ok, socket}

      _ ->
        # Redirect non-admin users
        {:ok, redirect(socket, to: "/dashboard")}
    end
  end

  @impl true
  def handle_event("submit_evaluation", evaluation_params, socket) do
    case socket.assigns[:current_user] do
      %{role: :admin} = user ->
        # Process evaluation submission
        case submit_evaluation(evaluation_params, user) do
          {:ok, evaluation} ->
            socket =
              socket
              |> put_flash(:info, "Evaluation submitted successfully")
              |> update(:active_evaluations, fn evals -> [evaluation | evals] end)

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> put_flash(:error, "Failed to submit evaluation: #{inspect(reason)}")

            {:noreply, socket}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("cancel_evaluation", %{"id" => evaluation_id}, socket) do
    case cancel_evaluation(evaluation_id, socket.assigns.current_user) do
      {:ok, _evaluation} ->
        socket =
          socket
          |> put_flash(:info, "Evaluation cancelled")
          |> update(:active_evaluations, fn evals ->
            Enum.reject(evals, &(&1.id == evaluation_id))
          end)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel: #{reason}")}
    end
  end

  @impl true
  def handle_info({:evaluation_progress, evaluation_id, progress_data}, socket) do
    # Update real-time progress for specific evaluation
    socket = update(socket, :active_evaluations, fn evaluations ->
      update_evaluation_progress(evaluations, evaluation_id, progress_data)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:system_health, health_data}, socket) do
    socket = assign(socket, :system_status, health_data)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
      <!-- Admin Header -->
      <header class="bg-red-600 shadow-sm">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16">
            <div class="flex items-center">
              <h1 class="text-2xl font-bold text-white">
                Admin Panel
              </h1>
              <span class="ml-2 px-2 py-1 text-xs font-medium text-red-100 bg-red-700 rounded-full">
                Evaluation Management
              </span>
            </div>

            <div class="flex items-center space-x-4">
              <div class="text-sm text-red-100">
                System Status:
                <span class={["font-medium", status_color(@system_status.healthy)]}>
                  {if @system_status.healthy, do: "Healthy", else: "Issues"}
                </span>
              </div>

              <.link navigate="/dashboard" class="text-red-100 hover:text-white">
                Public Dashboard
              </.link>
            </div>
          </div>
        </div>
      </header>
      
    <!-- Admin Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Evaluation Submission -->
          <div class="lg:col-span-1">
            <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                  Submit Evaluation
                </h2>
              </div>

              <.live_component
                module={EvaluationForm}
                id="evaluation-form"
                available_models={@available_models}
                available_repositories={@available_repositories}
                on_submit={&send(self(), {:submit_evaluation, &1})}
              />
            </div>
          </div>
          
    <!-- Active Evaluations -->
          <div class="lg:col-span-2">
            <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
              <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                  Active Evaluations
                </h2>
                <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                  {length(@active_evaluations)} running
                </p>
              </div>

              <.live_component
                module={ProgressTracker}
                id="progress-tracker"
                active_evaluations={@active_evaluations}
                on_cancel={&send(self(), {:cancel_evaluation, &1})}
              />
            </div>
          </div>
        </div>
        
    <!-- Log Streaming -->
        <div class="mt-8">
          <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
            <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
              <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                Live System Logs
              </h2>
            </div>

            <.live_component
              module={LogStreamer}
              id="log-streamer"
              log_level={:info}
              max_lines={100}
            />
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Helper functions

  defp status_color(true), do: "text-green-400"
  defp status_color(false), do: "text-red-400"

  defp get_available_models do
    [
      %{id: "gpt-4", name: "GPT-4", provider: "OpenAI"},
      %{id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: "OpenAI"},
      %{id: "claude-3-5-sonnet", name: "Claude-3.5-Sonnet", provider: "Anthropic"},
      %{id: "claude-3-haiku", name: "Claude-3-Haiku", provider: "Anthropic"},
      %{id: "gemini-pro", name: "Gemini-Pro", provider: "Google"},
      %{id: "gemini-flash", name: "Gemini-1.5-Flash", provider: "Google"}
    ]
  end

  defp get_available_repositories do
    # Would integrate with actual repository manager
    [
      "phoenix",
      "ecto",
      "jason",
      "tesla",
      "credo",
      "phoenix_live_view",
      "oban",
      "broadway",
      "benchee",
      "ex_doc",
      "bamboo",
      "guardian",
      "absinthe",
      "nx",
      "membrane"
    ]
  end

  defp load_admin_data(socket) do
    # Load admin-specific data
    active_evaluations = get_active_evaluations()

    assign(socket, :active_evaluations, active_evaluations)
  end

  defp get_active_evaluations do
    # Mock active evaluations - would integrate with actual evaluation system
    [
      %{
        id: "eval_active_001",
        model: "Claude-3.5-Sonnet",
        repository: "phoenix",
        progress: 65.5,
        status: :running,
        started_at: DateTime.add(DateTime.utc_now(), -300, :second),
        estimated_completion: DateTime.add(DateTime.utc_now(), 180, :second)
      }
    ]
  end

  defp submit_evaluation(params, user) do
    # Mock evaluation submission - would integrate with actual evaluation system
    evaluation = %{
      id: "eval_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      model: params["model"],
      repository: params["repository"],
      task_type: params["task_type"],
      submitted_by: user.id,
      submitted_at: DateTime.utc_now(),
      status: :queued,
      progress: 0.0
    }

    # Simulate submission to evaluation system
    {:ok, evaluation}
  end

  defp cancel_evaluation(evaluation_id, user) do
    # Mock evaluation cancellation - would integrate with actual evaluation system
    if user.role == :admin do
      {:ok, %{id: evaluation_id, status: :cancelled}}
    else
      {:error, :unauthorized}
    end
  end

  defp update_evaluation_progress(evaluations, evaluation_id, progress_data) do
    Enum.map(evaluations, fn eval ->
      if eval.id == evaluation_id do
        Map.put(eval, :progress, progress_data)
      else
        eval
      end
    end)
  end
end
