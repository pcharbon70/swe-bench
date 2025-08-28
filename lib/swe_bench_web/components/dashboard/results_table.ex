defmodule SweBenchWeb.Components.Dashboard.ResultsTable do
  @moduledoc """
  LiveView component for displaying evaluation results in a sortable table.

  Provides public access to evaluation results with sorting, filtering,
  and real-time updates as new evaluations complete.
  """

  use SweBenchWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:sort_by, assigns[:sort_by] || :completed_at)
      |> assign(:sort_direction, assigns[:sort_direction] || :desc)
      |> sort_results()

    {:ok, socket}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)

    {sort_by, sort_direction} =
      if socket.assigns.sort_by == field_atom do
        {field_atom, toggle_direction(socket.assigns.sort_direction)}
      else
        {field_atom, :desc}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_direction, sort_direction)
      |> sort_results()

    send(self(), {:sort_changed, sort_by, sort_direction})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-hidden">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <.sortable_header field={:model} current_sort={@sort_by} direction={@sort_direction}>
                Model
              </.sortable_header>

              <.sortable_header field={:provider} current_sort={@sort_by} direction={@sort_direction}>
                Provider
              </.sortable_header>

              <.sortable_header
                field={:repository}
                current_sort={@sort_by}
                direction={@sort_direction}
              >
                Repository
              </.sortable_header>

              <.sortable_header field={:task_type} current_sort={@sort_by} direction={@sort_direction}>
                Task Type
              </.sortable_header>

              <.sortable_header
                field={:complexity}
                current_sort={@sort_by}
                direction={@sort_direction}
              >
                Complexity
              </.sortable_header>

              <.sortable_header field={:score} current_sort={@sort_by} direction={@sort_direction}>
                Score
              </.sortable_header>

              <.sortable_header
                field={:completed_at}
                current_sort={@sort_by}
                direction={@sort_direction}
              >
                Completed
              </.sortable_header>

              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Status
              </th>
            </tr>
          </thead>

          <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
            <%= if @loading do %>
              <tr>
                <td colspan="8" class="px-6 py-4 text-center text-gray-500 dark:text-gray-400">
                  <div class="flex items-center justify-center">
                    <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
                    <span class="ml-2">Loading results...</span>
                  </div>
                </td>
              </tr>
            <% else %>
              <%= for result <- @sorted_results do %>
                <tr class="hover:bg-gray-50 dark:hover:bg-gray-800">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="flex items-center">
                      <div class="text-sm font-medium text-gray-900 dark:text-white">
                        {result.model}
                      </div>
                    </div>
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap">
                    <.provider_badge provider={result.provider} />
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                    {result.repository}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap">
                    <.task_type_badge task_type={result.task_type} />
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap">
                    <.complexity_badge complexity={result.complexity} />
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap">
                    <.score_display score={result.score} />
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {format_datetime(result.completed_at)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap">
                    <.status_badge status={result.status} />
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <%= if not @loading and @sorted_results == [] do %>
        <div class="text-center py-12">
          <div class="text-gray-500 dark:text-gray-400">
            <svg class="mx-auto h-12 w-12 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 17v-2m3 2v-4m3 4v-6m2 5V9a7 7 0 10-14 0v8a2 2 0 002 2h10a2 2 0 002-2z"
              />
            </svg>
            <h3 class="text-lg font-medium">No evaluation results found</h3>
            <p class="text-sm mt-1">Results will appear here as evaluations complete</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Component helper functions

  defp sortable_header(assigns) do
    ~H"""
    <th
      class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
      phx-click="sort"
      phx-value-field={@field}
      phx-target={@myself}
    >
      <div class="flex items-center space-x-1">
        <span>{render_slot(@inner_block)}</span>
        <%= if @current_sort == @field do %>
          <svg
            class={["w-4 h-4", sort_arrow_class(@direction)]}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fill-rule="evenodd"
              d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        <% end %>
      </div>
    </th>
    """
  end

  defp provider_badge(assigns) do
    ~H"""
    <span class={["inline-flex px-2 py-1 text-xs font-medium rounded-full", provider_color(@provider)]}>
      {@provider}
    </span>
    """
  end

  defp task_type_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex px-2 py-1 text-xs font-medium rounded-full",
      task_type_color(@task_type)
    ]}>
      {format_task_type(@task_type)}
    </span>
    """
  end

  defp complexity_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex px-2 py-1 text-xs font-medium rounded-full",
      complexity_color(@complexity)
    ]}>
      {String.capitalize(to_string(@complexity))}
    </span>
    """
  end

  defp score_display(assigns) do
    ~H"""
    <div class="flex items-center">
      <div class="text-sm font-medium text-gray-900 dark:text-white">
        {Float.round(@score, 1)}%
      </div>
      <div class="ml-2 w-16 bg-gray-200 rounded-full h-2 dark:bg-gray-700">
        <div
          class={["h-2 rounded-full", score_color(@score)]}
          style={"width: #{@score}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={["inline-flex px-2 py-1 text-xs font-medium rounded-full", status_color(@status)]}>
      {String.capitalize(to_string(@status))}
    </span>
    """
  end

  # Helper functions

  defp sort_results(socket) do
    sorted_results =
      socket.assigns.results
      |> Enum.sort_by(fn result ->
        Map.get(result, socket.assigns.sort_by)
      end)
      |> maybe_reverse(socket.assigns.sort_direction)

    assign(socket, :sorted_results, sorted_results)
  end

  defp maybe_reverse(results, :desc), do: Enum.reverse(results)
  defp maybe_reverse(results, :asc), do: results

  defp toggle_direction(:asc), do: :desc
  defp toggle_direction(:desc), do: :asc

  defp sort_arrow_class(:asc), do: "transform rotate-180"
  defp sort_arrow_class(:desc), do: ""

  defp provider_color("OpenAI"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  defp provider_color("Anthropic"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"

  defp provider_color("Google"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"

  defp provider_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp task_type_color(:web_framework),
    do: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-300"

  defp task_type_color(:database),
    do: "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-300"

  defp task_type_color(:real_time_web),
    do: "bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-300"

  defp task_type_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp complexity_color(:low),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  defp complexity_color(:medium),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"

  defp complexity_color(:high),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300"

  defp complexity_color(:very_high),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300"

  defp complexity_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp score_color(score) when score >= 90, do: "bg-green-500"
  defp score_color(score) when score >= 75, do: "bg-blue-500"
  defp score_color(score) when score >= 60, do: "bg-yellow-500"
  defp score_color(score) when score >= 40, do: "bg-orange-500"
  defp score_color(_), do: "bg-red-500"

  defp status_color(:completed),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  defp status_color(:running), do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"

  defp status_color(:queued),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"

  defp status_color(:failed), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300"
  defp status_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp format_task_type(task_type) do
    task_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_datetime(datetime) do
    case DateTime.from_iso8601(to_string(datetime)) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M")

      _ ->
        case is_struct(datetime, DateTime) do
          true -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
          false -> "Unknown"
        end
    end
  rescue
    _ -> "Invalid date"
  end
end
