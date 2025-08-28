defmodule SweBenchWeb.Components.Admin.LogStreamer do
  @moduledoc """
  Live log streaming component for admin system monitoring.

  Provides real-time system log access with filtering and search capabilities
  for administrative oversight and debugging.
  """

  use SweBenchWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:log_lines, assigns[:log_lines] || [])
      |> assign(:max_lines, assigns[:max_lines] || 100)
      |> assign(:log_level, assigns[:log_level] || :info)
      |> assign(:auto_scroll, true)
      |> assign(:search_term, "")
      |> load_initial_logs_if_empty()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_auto_scroll", _params, socket) do
    socket = assign(socket, :auto_scroll, not socket.assigns.auto_scroll)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_logs", _params, socket) do
    socket = assign(socket, :log_lines, [])
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_logs", %{"search" => search_term}, socket) do
    socket = assign(socket, :search_term, search_term)
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_log_level", %{"level" => level}, socket) do
    socket = assign(socket, :log_level, String.to_existing_atom(level))
    {:noreply, socket}
  end

  # Note: LiveComponents receive log updates from parent LiveView

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Log Controls -->
      <div class="flex flex-wrap items-center justify-between gap-4 px-6 py-3">
        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2">
            <label class="text-xs font-medium text-gray-700 dark:text-gray-300">
              Level:
            </label>
            <select
              phx-change="change_log_level"
              phx-target={@myself}
              class="text-xs rounded border-gray-300 focus:border-blue-500 focus:ring-blue-500"
            >
              <option value="debug" selected={@log_level == :debug}>Debug</option>
              <option value="info" selected={@log_level == :info}>Info</option>
              <option value="warning" selected={@log_level == :warning}>Warning</option>
              <option value="error" selected={@log_level == :error}>Error</option>
            </select>
          </div>

          <div class="flex items-center">
            <input
              type="text"
              placeholder="Search logs..."
              value={@search_term}
              phx-change="search_logs"
              phx-debounce="300"
              phx-target={@myself}
              class="text-xs rounded border-gray-300 focus:border-blue-500 focus:ring-blue-500"
            />
          </div>
        </div>

        <div class="flex items-center space-x-2">
          <label class="flex items-center text-xs">
            <input
              type="checkbox"
              checked={@auto_scroll}
              phx-click="toggle_auto_scroll"
              phx-target={@myself}
              class="rounded border-gray-300 text-blue-600"
            />
            <span class="ml-1 text-gray-700 dark:text-gray-300">Auto-scroll</span>
          </label>

          <button
            phx-click="clear_logs"
            phx-target={@myself}
            class="px-2 py-1 text-xs text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
          >
            Clear
          </button>
        </div>
      </div>
      
    <!-- Log Display -->
      <div class="bg-black text-green-400 p-4 rounded-lg font-mono text-xs overflow-hidden">
        <div
          class="space-y-1 overflow-y-auto"
          style="height: 400px;"
          id="log-container"
          phx-hook={if @auto_scroll, do: "AutoScroll", else: nil}
        >
          <%= for log_line <- filtered_log_lines(@log_lines, @search_term, @log_level) do %>
            <div class="flex items-start space-x-2">
              <span class="text-gray-500 shrink-0">
                {Calendar.strftime(log_line.timestamp, "%H:%M:%S")}
              </span>
              <span class={["shrink-0", log_level_color(log_line.level)]}>
                [{String.upcase(to_string(log_line.level))}]
              </span>
              <span class="text-gray-300 shrink-0">
                {log_line.source}:
              </span>
              <span class="text-green-400">
                {log_line.message}
              </span>
            </div>
          <% end %>

          <%= if filtered_log_lines(@log_lines, @search_term, @log_level) == [] do %>
            <div class="text-center py-8 text-gray-500">
              <%= if @log_lines == [] do %>
                No logs available yet
              <% else %>
                No logs match your filters
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp load_initial_logs_if_empty(socket) do
    # Only load initial logs if no logs are provided
    if socket.assigns[:log_lines] == [] do
      load_recent_logs(socket)
    else
      socket
    end
  end

  defp load_recent_logs(socket) do
    # Mock recent logs - would integrate with actual log system
    recent_logs = [
      %{
        timestamp: DateTime.utc_now(),
        level: :info,
        message: "System health check completed successfully",
        source: "health_monitor"
      },
      %{
        timestamp: DateTime.add(DateTime.utc_now(), -30, :second),
        level: :info,
        message: "Evaluation eval_001 completed with score 87.5%",
        source: "evaluation_system"
      },
      %{
        timestamp: DateTime.add(DateTime.utc_now(), -60, :second),
        level: :debug,
        message: "Container pool scaled to 5 active containers",
        source: "container_manager"
      }
    ]

    assign(socket, :log_lines, recent_logs)
  end

  defp format_log_entry(log_data) when is_map(log_data) do
    %{
      timestamp: Map.get(log_data, :timestamp, DateTime.utc_now()),
      level: Map.get(log_data, :level, :info),
      message: Map.get(log_data, :message, ""),
      source: Map.get(log_data, :source, "system")
    }
  end

  defp filtered_log_lines(log_lines, search_term, log_level) do
    log_lines
    |> filter_by_level(log_level)
    |> filter_by_search(search_term)
  end

  # Show all
  defp filter_by_level(log_lines, :debug), do: log_lines

  defp filter_by_level(log_lines, :info) do
    Enum.filter(log_lines, fn log -> log.level in [:info, :warning, :error] end)
  end

  defp filter_by_level(log_lines, :warning) do
    Enum.filter(log_lines, fn log -> log.level in [:warning, :error] end)
  end

  defp filter_by_level(log_lines, :error) do
    Enum.filter(log_lines, fn log -> log.level == :error end)
  end

  defp filter_by_search(log_lines, ""), do: log_lines

  defp filter_by_search(log_lines, search_term) do
    search_lower = String.downcase(search_term)

    Enum.filter(log_lines, fn log ->
      String.contains?(String.downcase(log.message), search_lower) or
        String.contains?(String.downcase(log.source), search_lower)
    end)
  end

  defp log_level_color(:debug), do: "text-gray-400"
  defp log_level_color(:info), do: "text-blue-400"
  defp log_level_color(:warning), do: "text-yellow-400"
  defp log_level_color(:error), do: "text-red-400"
end
