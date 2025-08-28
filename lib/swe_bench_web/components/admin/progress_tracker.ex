defmodule SweBenchWeb.Components.Admin.ProgressTracker do
  @moduledoc """
  Real-time progress tracker component for admin evaluation monitoring.

  Displays live evaluation progress with cancellation capabilities
  and detailed status information.
  """

  use SweBenchWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:expanded_evaluations, %{})

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_details", %{"evaluation_id" => evaluation_id}, socket) do
    socket =
      update(socket, :expanded_evaluations, fn expanded ->
        Map.update(expanded, evaluation_id, true, &(!&1))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_evaluation", %{"evaluation_id" => evaluation_id}, socket) do
    # Send cancellation request to parent
    send(self(), {:cancel_evaluation, %{"id" => evaluation_id}})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @active_evaluations == [] do %>
        <div class="text-center py-8">
          <div class="text-gray-500 dark:text-gray-400">
            <svg class="mx-auto h-12 w-12 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <h3 class="text-lg font-medium">No active evaluations</h3>
            <p class="text-sm mt-1">Submit an evaluation to see progress here</p>
          </div>
        </div>
      <% else %>
        <%= for evaluation <- @active_evaluations do %>
          <div class="border border-gray-200 dark:border-gray-700 rounded-lg">
            <!-- Evaluation Header -->
            <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-3">
                  <.status_indicator status={evaluation.status} />
                  <div>
                    <h4 class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= evaluation.model %> on <%= evaluation.repository %>
                    </h4>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      ID: <%= evaluation.id %>
                    </p>
                  </div>
                </div>
                
                <div class="flex items-center space-x-2">
                  <button
                    phx-click="toggle_details"
                    phx-value-evaluation_id={evaluation.id}
                    phx-target={@myself}
                    class="text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                  >
                    <%= if @expanded_evaluations[evaluation.id] do %>
                      Hide Details
                    <% else %>
                      Show Details
                    <% end %>
                  </button>
                  
                  <%= if evaluation.status in [:running, :queued] do %>
                    <button
                      phx-click="cancel_evaluation"
                      phx-value-evaluation_id={evaluation.id}
                      phx-target={@myself}
                      class="px-3 py-1 text-xs bg-red-100 text-red-700 rounded hover:bg-red-200 dark:bg-red-900 dark:text-red-300"
                    >
                      Cancel
                    </button>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- Progress Bar -->
            <div class="px-4 py-3">
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-medium text-gray-700 dark:text-gray-300">
                  Progress
                </span>
                <span class="text-xs text-gray-500 dark:text-gray-400">
                  <%= format_progress_percentage(evaluation.progress) %>%
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-2 dark:bg-gray-700">
                <div 
                  class={["h-2 rounded-full transition-all duration-300", progress_color(evaluation.status)]}
                  style={"width: #{format_progress_percentage(evaluation.progress)}%"}
                >
                </div>
              </div>
              
              <%= if evaluation.estimated_completion do %>
                <div class="mt-2 text-xs text-gray-500 dark:text-gray-400">
                  Estimated completion: <%= format_datetime(evaluation.estimated_completion) %>
                </div>
              <% end %>
            </div>

            <!-- Expanded Details -->
            <%= if @expanded_evaluations[evaluation.id] do %>
              <div class="px-4 py-3 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800">
                <dl class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                  <div>
                    <dt class="font-medium text-gray-900 dark:text-white">Started:</dt>
                    <dd class="text-gray-600 dark:text-gray-400">
                      <%= format_datetime(evaluation.started_at) %>
                    </dd>
                  </div>
                  
                  <%= if evaluation.current_stage do %>
                    <div>
                      <dt class="font-medium text-gray-900 dark:text-white">Current Stage:</dt>
                      <dd class="text-gray-600 dark:text-gray-400">
                        <%= format_stage_name(evaluation.current_stage) %>
                      </dd>
                    </div>
                  <% end %>
                  
                  <%= if evaluation.tests_completed do %>
                    <div>
                      <dt class="font-medium text-gray-900 dark:text-white">Tests:</dt>
                      <dd class="text-gray-600 dark:text-gray-400">
                        <%= evaluation.tests_completed %> / <%= evaluation.tests_total || "?" %>
                      </dd>
                    </div>
                  <% end %>
                  
                  <div>
                    <dt class="font-medium text-gray-900 dark:text-white">Duration:</dt>
                    <dd class="text-gray-600 dark:text-gray-400">
                      <%= format_duration(evaluation.started_at) %>
                    </dd>
                  </div>
                </dl>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper components and functions

  defp status_indicator(assigns) do
    ~H"""
    <div class={["w-3 h-3 rounded-full", status_indicator_color(@status)]}>
    </div>
    """
  end

  # Note: field_error function kept for potential future use
  defp field_error(assigns) do
    ~H"""
    <%= if @errors != nil and @errors != [] do %>
      <div class="mt-1">
        <%= for error <- List.wrap(@errors) do %>
          <p class="text-sm text-red-600 dark:text-red-400">
            <%= error %>
          </p>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp status_indicator_color(:running), do: "bg-blue-500 animate-pulse"
  defp status_indicator_color(:queued), do: "bg-yellow-500"
  defp status_indicator_color(:completed), do: "bg-green-500"
  defp status_indicator_color(:failed), do: "bg-red-500"
  defp status_indicator_color(:cancelled), do: "bg-gray-500"
  defp status_indicator_color(_), do: "bg-gray-400"

  defp progress_color(:running), do: "bg-blue-500"
  defp progress_color(:completed), do: "bg-green-500"
  defp progress_color(:failed), do: "bg-red-500"
  defp progress_color(_), do: "bg-gray-500"

  defp format_progress_percentage(nil), do: 0
  defp format_progress_percentage(progress) when is_number(progress) do
    Float.round(progress, 1)
  end
  defp format_progress_percentage(_), do: 0

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  rescue
    _ -> "Unknown"
  end
  defp format_datetime(_), do: "Unknown"

  defp format_stage_name(stage) when is_atom(stage) do
    stage
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp format_stage_name(stage), do: to_string(stage)

  defp format_duration(started_at) when is_struct(started_at, DateTime) do
    duration_seconds = DateTime.diff(DateTime.utc_now(), started_at, :second)
    
    cond do
      duration_seconds < 60 ->
        "#{duration_seconds}s"
      
      duration_seconds < 3600 ->
        minutes = div(duration_seconds, 60)
        seconds = rem(duration_seconds, 60)
        "#{minutes}m #{seconds}s"
      
      true ->
        hours = div(duration_seconds, 3600)
        minutes = div(rem(duration_seconds, 3600), 60)
        "#{hours}h #{minutes}m"
    end
  rescue
    _ -> "Unknown"
  end
  defp format_duration(_), do: "Unknown"
end