defmodule SweBenchWeb.DashboardLive do
  @moduledoc """
  Main public dashboard LiveView for SWE-bench evaluation results.

  Provides real-time access to evaluation results, model comparisons,
  and interactive filtering capabilities. Public users can view all
  results and analytics without authentication.
  """

  use SweBenchWeb, :live_view

  # Future: Will integrate with actual data sources
  # alias SweBench.{Repo, TaskInstances}
  alias SweBenchWeb.Components.{ResultsTable, ModelComparison, FilterPanel}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time evaluation updates
      Phoenix.PubSub.subscribe(SweBench.PubSub, "evaluation_results")
      Phoenix.PubSub.subscribe(SweBench.PubSub, "model_comparisons")
    end

    socket =
      socket
      |> assign(:page_title, "SWE-bench Elixir | Evaluation Results")
      |> assign(:evaluation_results, [])
      |> assign(:model_filters, [])
      |> assign(:task_filters, [])
      |> assign(:loading, true)
      |> load_initial_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Handle URL parameters for filters and views
    socket =
      socket
      |> apply_url_filters(params)
      |> assign(:current_view, Map.get(params, "view", "results"))

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_models", %{"models" => selected_models}, socket) do
    socket =
      socket
      |> assign(:model_filters, selected_models)
      |> update_filtered_results()
      |> push_navigate(to: build_filter_url(socket, :models, selected_models))

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_tasks", %{"tasks" => selected_tasks}, socket) do
    socket =
      socket
      |> assign(:task_filters, selected_tasks)
      |> update_filtered_results()
      |> push_navigate(to: build_filter_url(socket, :tasks, selected_tasks))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:model_filters, [])
      |> assign(:task_filters, [])
      |> update_filtered_results()
      |> push_navigate(to: ~p"/dashboard")

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    socket = assign(socket, :current_view, view)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:evaluation_complete, evaluation_data}, socket) do
    # Handle real-time evaluation completion
    socket =
      socket
      |> update(:evaluation_results, fn results ->
        [evaluation_data | results] |> Enum.take(100)  # Keep latest 100
      end)
      |> update_filtered_results()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:model_comparison_update, comparison_data}, socket) do
    # Handle real-time model comparison updates
    socket = assign(socket, :model_comparisons, comparison_data)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
      <!-- Header -->
      <header class="bg-white dark:bg-gray-800 shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16">
            <div class="flex items-center">
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
                SWE-bench Elixir
              </h1>
              <span class="ml-2 px-2 py-1 text-xs font-medium text-blue-700 bg-blue-100 rounded-full">
                Public Dashboard
              </span>
            </div>
            
            <nav class="flex space-x-4">
              <button 
                phx-click="change_view" 
                phx-value-view="results"
                class={["px-3 py-2 rounded-md text-sm font-medium", view_button_classes(@current_view == "results")]}
              >
                Results
              </button>
              <button 
                phx-click="change_view" 
                phx-value-view="comparisons"
                class={["px-3 py-2 rounded-md text-sm font-medium", view_button_classes(@current_view == "comparisons")]}
              >
                Model Comparisons
              </button>
              <button 
                phx-click="change_view" 
                phx-value-view="explorer"
                class={["px-3 py-2 rounded-md text-sm font-medium", view_button_classes(@current_view == "explorer")]}
              >
                Dataset Explorer
              </button>
            </nav>
          </div>
        </div>
      </header>

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Filter Panel -->
        <.live_component 
          module={FilterPanel} 
          id="filter-panel"
          model_filters={@model_filters}
          task_filters={@task_filters}
          on_model_filter={&send(self(), {:filter_models, &1})}
          on_task_filter={&send(self(), {:filter_tasks, &1})}
          on_clear={&send(self(), {:clear_filters, &1})}
        />

        <!-- Content Based on Current View -->
        <div class="mt-8">
          <.view_content 
            view={@current_view}
            evaluation_results={@filtered_results || @evaluation_results}
            model_comparisons={@model_comparisons}
            loading={@loading}
          />
        </div>
      </main>
    </div>
    """
  end

  # Helper functions for rendering

  defp view_content(%{view: "results"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            Evaluation Results
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            Real-time evaluation results across all models and tasks
          </p>
        </div>
        
        <.live_component 
          module={ResultsTable} 
          id="results-table"
          results={@evaluation_results}
          loading={@loading}
        />
      </div>
    </div>
    """
  end

  defp view_content(%{view: "comparisons"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            Model Performance Comparisons
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            Interactive comparison charts and analytics across LLM models
          </p>
        </div>
        
        <.live_component 
          module={ModelComparison} 
          id="model-comparison"
          model_comparisons={@model_comparisons}
          loading={@loading}
        />
      </div>
    </div>
    """
  end

  defp view_content(%{view: "explorer"} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            Dataset Explorer
          </h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
            Explore task instances, validation history, and detailed breakdowns
          </p>
        </div>
        
        <div class="px-6 py-4">
          <p class="text-gray-600 dark:text-gray-400">
            Dataset explorer implementation coming soon...
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp view_button_classes(true) do
    "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300"
  end

  defp view_button_classes(false) do
    "text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white"
  end

  # Private functions

  defp load_initial_data(socket) do
    # Load initial evaluation results
    # For now, return mock data - would integrate with actual evaluation results
    evaluation_results = [
      %{
        id: "eval_001",
        model: "GPT-4",
        provider: "OpenAI",
        repository: "phoenix",
        task_type: "web_framework",
        complexity: :high,
        score: 87.5,
        completed_at: DateTime.utc_now(),
        status: :completed
      },
      %{
        id: "eval_002", 
        model: "Claude-3.5-Sonnet",
        provider: "Anthropic",
        repository: "ecto",
        task_type: "database",
        complexity: :medium,
        score: 92.3,
        completed_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        status: :completed
      },
      %{
        id: "eval_003",
        model: "Gemini-Pro",
        provider: "Google",
        repository: "phoenix_live_view",
        task_type: "real_time_web", 
        complexity: :very_high,
        score: 78.9,
        completed_at: DateTime.add(DateTime.utc_now(), -7200, :second),
        status: :completed
      }
    ]

    socket
    |> assign(:evaluation_results, evaluation_results)
    |> assign(:filtered_results, evaluation_results)
    |> assign(:model_comparisons, generate_mock_comparisons())
    |> assign(:loading, false)
  end

  defp generate_mock_comparisons do
    %{
      score_by_model: %{
        "GPT-4" => 87.5,
        "Claude-3.5-Sonnet" => 92.3,
        "Gemini-Pro" => 78.9
      },
      score_by_repository: %{
        "phoenix" => %{"GPT-4" => 87.5, "Claude-3.5-Sonnet" => 89.2, "Gemini-Pro" => 82.1},
        "ecto" => %{"GPT-4" => 85.3, "Claude-3.5-Sonnet" => 92.3, "Gemini-Pro" => 76.8},
        "phoenix_live_view" => %{"GPT-4" => 89.7, "Claude-3.5-Sonnet" => 95.1, "Gemini-Pro" => 78.9}
      }
    }
  end

  defp apply_url_filters(socket, params) do
    model_filters = String.split(Map.get(params, "models", ""), ",", trim: true)
    task_filters = String.split(Map.get(params, "tasks", ""), ",", trim: true)

    socket
    |> assign(:model_filters, model_filters)
    |> assign(:task_filters, task_filters)
    |> update_filtered_results()
  end

  defp update_filtered_results(socket) do
    filtered_results = socket.assigns.evaluation_results
    |> filter_by_models(socket.assigns.model_filters)
    |> filter_by_tasks(socket.assigns.task_filters)

    assign(socket, :filtered_results, filtered_results)
  end

  defp filter_by_models(results, []), do: results
  defp filter_by_models(results, model_filters) do
    Enum.filter(results, fn result ->
      result.model in model_filters
    end)
  end

  defp filter_by_tasks(results, []), do: results
  defp filter_by_tasks(results, task_filters) do
    Enum.filter(results, fn result ->
      result.repository in task_filters or 
      to_string(result.task_type) in task_filters or
      to_string(result.complexity) in task_filters
    end)
  end

  defp build_filter_url(socket, filter_type, values) do
    current_params = %{
      "models" => Enum.join(socket.assigns.model_filters, ","),
      "tasks" => Enum.join(socket.assigns.task_filters, ",")
    }

    updated_params = case filter_type do
      :models -> Map.put(current_params, "models", Enum.join(values, ","))
      :tasks -> Map.put(current_params, "tasks", Enum.join(values, ","))
    end

    query_string = updated_params
    |> Enum.filter(fn {_k, v} -> v != "" end)
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode(v)}" end)
    |> Enum.join("&")

    if query_string != "" do
      "/dashboard?" <> query_string
    else
      "/dashboard"
    end
  end
end