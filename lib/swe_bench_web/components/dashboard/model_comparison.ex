defmodule SweBenchWeb.Components.Dashboard.ModelComparison do
  @moduledoc """
  LiveView component for displaying LLM model performance comparisons.

  Provides interactive charts, head-to-head comparisons, and model capability
  analysis with real-time updates from evaluation streaming.
  """

  use SweBenchWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:chart_type, assigns[:chart_type] || :bar_chart)
      |> assign(:comparison_mode, assigns[:comparison_mode] || :overall)
      |> prepare_chart_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_chart_type", %{"type" => chart_type}, socket) do
    socket =
      socket
      |> assign(:chart_type, String.to_existing_atom(chart_type))
      |> prepare_chart_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_comparison_mode", %{"mode" => mode}, socket) do
    socket =
      socket
      |> assign(:comparison_mode, String.to_existing_atom(mode))
      |> prepare_chart_data()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Chart Controls -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2">
            <label class="text-sm font-medium text-gray-700 dark:text-gray-300">
              Chart Type:
            </label>
            <select
              phx-change="change_chart_type"
              phx-target={@myself}
              class="rounded border-gray-300 text-sm focus:border-blue-500 focus:ring-blue-500"
            >
              <option value="bar_chart" selected={@chart_type == :bar_chart}>Bar Chart</option>
              <option value="radar_chart" selected={@chart_type == :radar_chart}>Radar Chart</option>
              <option value="line_chart" selected={@chart_type == :line_chart}>Trend Line</option>
              <option value="heatmap" selected={@chart_type == :heatmap}>Heat Map</option>
            </select>
          </div>

          <div class="flex items-center space-x-2">
            <label class="text-sm font-medium text-gray-700 dark:text-gray-300">
              Comparison:
            </label>
            <select
              phx-change="change_comparison_mode"
              phx-target={@myself}
              class="rounded border-gray-300 text-sm focus:border-blue-500 focus:ring-blue-500"
            >
              <option value="overall" selected={@comparison_mode == :overall}>
                Overall Performance
              </option>
              <option value="by_repository" selected={@comparison_mode == :by_repository}>
                By Repository
              </option>
              <option value="by_complexity" selected={@comparison_mode == :by_complexity}>
                By Complexity
              </option>
              <option value="by_category" selected={@comparison_mode == :by_category}>
                By Category
              </option>
            </select>
          </div>
        </div>

        <div class="text-sm text-gray-500 dark:text-gray-400">
          Last updated: {format_timestamp(@last_updated)}
        </div>
      </div>
      
    <!-- Chart Display -->
      <div class="bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700">
        <div class="p-6">
          <%= case @chart_type do %>
            <% :bar_chart -> %>
              <.bar_chart_display chart_data={@chart_data} comparison_mode={@comparison_mode} />
            <% :radar_chart -> %>
              <.radar_chart_display chart_data={@chart_data} comparison_mode={@comparison_mode} />
            <% :line_chart -> %>
              <.line_chart_display chart_data={@chart_data} comparison_mode={@comparison_mode} />
            <% :heatmap -> %>
              <.heatmap_display chart_data={@chart_data} comparison_mode={@comparison_mode} />
            <% _ -> %>
              <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                Chart type not implemented yet
              </div>
          <% end %>
        </div>
      </div>
      
    <!-- Model Performance Summary -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <%= for {model, data} <- @model_summary do %>
          <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
            <div class="flex items-center justify-between mb-4">
              <h4 class="text-lg font-medium text-gray-900 dark:text-white">
                {model}
              </h4>
              <.provider_badge provider={data.provider} />
            </div>

            <dl class="space-y-2">
              <div class="flex justify-between">
                <dt class="text-sm text-gray-600 dark:text-gray-400">Average Score:</dt>
                <dd class="text-sm font-medium text-gray-900 dark:text-white">
                  {Float.round(data.average_score, 1)}%
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-sm text-gray-600 dark:text-gray-400">Evaluations:</dt>
                <dd class="text-sm font-medium text-gray-900 dark:text-white">
                  {data.evaluation_count}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-sm text-gray-600 dark:text-gray-400">Best Category:</dt>
                <dd class="text-sm font-medium text-gray-900 dark:text-white">
                  {data.best_category}
                </dd>
              </div>
            </dl>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Chart display components

  defp bar_chart_display(assigns) do
    ~H"""
    <div class="h-96">
      <svg viewBox="0 0 800 400" class="w-full h-full">
        <!-- Chart implementation would go here -->
        <!-- For now, show placeholder -->
        <text x="400" y="200" text-anchor="middle" class="text-lg fill-gray-500">
          Interactive Bar Chart
        </text>
        <text x="400" y="230" text-anchor="middle" class="text-sm fill-gray-400">
          Chart library integration coming soon
        </text>
      </svg>
    </div>
    """
  end

  defp radar_chart_display(assigns) do
    ~H"""
    <div class="h-96">
      <svg viewBox="0 0 400 400" class="w-full h-full mx-auto">
        <text x="200" y="200" text-anchor="middle" class="text-lg fill-gray-500">
          Model Capability Radar
        </text>
        <text x="200" y="230" text-anchor="middle" class="text-sm fill-gray-400">
          Multi-dimensional analysis coming soon
        </text>
      </svg>
    </div>
    """
  end

  defp line_chart_display(assigns) do
    ~H"""
    <div class="h-96">
      <svg viewBox="0 0 800 400" class="w-full h-full">
        <text x="400" y="200" text-anchor="middle" class="text-lg fill-gray-500">
          Performance Trend Analysis
        </text>
        <text x="400" y="230" text-anchor="middle" class="text-sm fill-gray-400">
          Historical trend charts coming soon
        </text>
      </svg>
    </div>
    """
  end

  defp heatmap_display(assigns) do
    ~H"""
    <div class="h-96">
      <svg viewBox="0 0 800 400" class="w-full h-full">
        <text x="400" y="200" text-anchor="middle" class="text-lg fill-gray-500">
          Performance Heat Map
        </text>
        <text x="400" y="230" text-anchor="middle" class="text-sm fill-gray-400">
          Repository vs Model performance matrix coming soon
        </text>
      </svg>
    </div>
    """
  end

  defp provider_badge(assigns) do
    ~H"""
    <span class={["inline-flex px-2 py-1 text-xs font-medium rounded-full", provider_color(@provider)]}>
      {@provider}
    </span>
    """
  end

  # Helper functions

  defp prepare_chart_data(socket) do
    model_comparisons = socket.assigns[:model_comparisons] || %{}

    chart_data =
      case socket.assigns.comparison_mode do
        :overall ->
          prepare_overall_comparison_data(model_comparisons)

        :by_repository ->
          prepare_repository_comparison_data(model_comparisons)

        :by_complexity ->
          prepare_complexity_comparison_data(model_comparisons)

        :by_category ->
          prepare_category_comparison_data(model_comparisons)

        _ ->
          %{}
      end

    model_summary = generate_model_summary(model_comparisons)

    socket
    |> assign(:chart_data, chart_data)
    |> assign(:model_summary, model_summary)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp prepare_overall_comparison_data(model_comparisons) do
    case Map.get(model_comparisons, :score_by_model) do
      nil ->
        %{}

      scores ->
        scores
        |> Enum.map(fn {model, score} ->
          {model, %{score: score, color: model_color(model)}}
        end)
        |> Enum.into(%{})
    end
  end

  defp prepare_repository_comparison_data(model_comparisons) do
    Map.get(model_comparisons, :score_by_repository, %{})
  end

  defp prepare_complexity_comparison_data(_model_comparisons) do
    # Mock complexity data - would integrate with actual evaluation data
    %{
      "Low Complexity" => %{"GPT-4" => 95.0, "Claude-3.5-Sonnet" => 97.0, "Gemini-Pro" => 92.0},
      "Medium Complexity" => %{"GPT-4" => 87.0, "Claude-3.5-Sonnet" => 92.0, "Gemini-Pro" => 85.0},
      "High Complexity" => %{"GPT-4" => 78.0, "Claude-3.5-Sonnet" => 85.0, "Gemini-Pro" => 72.0}
    }
  end

  defp prepare_category_comparison_data(_model_comparisons) do
    # Mock category data - would integrate with actual evaluation categories
    %{
      "Web Framework" => %{"GPT-4" => 88.0, "Claude-3.5-Sonnet" => 91.0, "Gemini-Pro" => 82.0},
      "Database" => %{"GPT-4" => 85.0, "Claude-3.5-Sonnet" => 93.0, "Gemini-Pro" => 79.0},
      "Real-time Web" => %{"GPT-4" => 90.0, "Claude-3.5-Sonnet" => 95.0, "Gemini-Pro" => 85.0}
    }
  end

  defp generate_model_summary(model_comparisons) do
    case Map.get(model_comparisons, :score_by_model) do
      nil ->
        []

      scores ->
        scores
        |> Enum.map(fn {model, score} ->
          {model,
           %{
             provider: determine_provider(model),
             average_score: score,
             # Mock data
             evaluation_count: :rand.uniform(50) + 10,
             best_category: determine_best_category(model)
           }}
        end)
    end
  end

  defp determine_provider(model) do
    cond do
      String.contains?(model, "GPT") -> "OpenAI"
      String.contains?(model, "Claude") -> "Anthropic"
      String.contains?(model, "Gemini") -> "Google"
      true -> "Unknown"
    end
  end

  defp determine_best_category(_model) do
    # Mock best category determination - would analyze actual results
    categories = ["Web Framework", "Database", "Real-time Web", "Performance"]
    Enum.random(categories)
  end

  defp model_color(model) do
    case determine_provider(model) do
      # Green
      "OpenAI" -> "#10B981"
      # Blue  
      "Anthropic" -> "#3B82F6"
      # Yellow
      "Google" -> "#F59E0B"
      # Gray
      _ -> "#6B7280"
    end
  end

  defp provider_color("OpenAI"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  defp provider_color("Anthropic"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"

  defp provider_color("Google"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"

  defp provider_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp format_timestamp(timestamp) when is_struct(timestamp, DateTime) do
    Calendar.strftime(timestamp, "%H:%M:%S")
  rescue
    _ -> "Unknown"
  end

  defp format_timestamp(_), do: "Unknown"
end
