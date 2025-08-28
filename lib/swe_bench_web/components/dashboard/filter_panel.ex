defmodule SweBenchWeb.Components.Dashboard.FilterPanel do
  @moduledoc """
  Advanced dual filtering panel for model and task selection.

  Provides interactive filtering controls for LLM models and task categories
  with real-time graph updates and filter presets.
  """

  use SweBenchWeb, :live_component

  @available_models [
    %{id: "gpt-4", name: "GPT-4", provider: "OpenAI", color: "green"},
    %{id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: "OpenAI", color: "green"},
    %{id: "claude-3-5-sonnet", name: "Claude-3.5-Sonnet", provider: "Anthropic", color: "blue"},
    %{id: "claude-3-haiku", name: "Claude-3-Haiku", provider: "Anthropic", color: "blue"},
    %{id: "gemini-pro", name: "Gemini-Pro", provider: "Google", color: "yellow"},
    %{id: "gemini-flash", name: "Gemini-1.5-Flash", provider: "Google", color: "yellow"}
  ]

  @available_repositories [
    %{id: "phoenix", name: "Phoenix", category: "Web Framework"},
    %{id: "ecto", name: "Ecto", category: "Database"},
    %{id: "phoenix_live_view", name: "Phoenix LiveView", category: "Real-time Web"},
    %{id: "oban", name: "Oban", category: "Job Processing"},
    %{id: "broadway", name: "Broadway", category: "Data Pipeline"},
    %{id: "absinthe", name: "Absinthe", category: "GraphQL"}
  ]

  @complexity_levels [
    %{id: "low", name: "Low", color: "green"},
    %{id: "medium", name: "Medium", color: "yellow"},
    %{id: "high", name: "High", color: "orange"},
    %{id: "very_high", name: "Very High", color: "red"}
  ]

  @filter_presets [
    %{
      id: "top_3_models",
      name: "Top 3 Models",
      models: ["gpt-4", "claude-3-5-sonnet", "gemini-pro"],
      tasks: []
    },
    %{
      id: "phoenix_tasks_only",
      name: "Phoenix Tasks Only",
      models: [],
      tasks: ["phoenix", "phoenix_live_view"]
    },
    %{
      id: "high_complexity",
      name: "High Complexity Only",
      models: [],
      tasks: ["high", "very_high"]
    },
    %{
      id: "anthropic_vs_openai",
      name: "Anthropic vs OpenAI",
      models: ["gpt-4", "claude-3-5-sonnet"],
      tasks: []
    }
  ]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:available_models, @available_models)
      |> assign(:available_repositories, @available_repositories)
      |> assign(:complexity_levels, @complexity_levels)
      |> assign(:filter_presets, @filter_presets)
      |> assign(:expanded_sections, %{models: false, tasks: false})

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)
    
    socket =
      update(socket, :expanded_sections, fn sections ->
        Map.update(sections, section_atom, true, &(!&1))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_preset", %{"preset" => preset_id}, socket) do
    preset = Enum.find(@filter_presets, &(&1.id == preset_id))
    
    if preset do
      send_update(self(), SweBenchWeb.DashboardLive, %{
        model_filters: preset.models,
        task_filters: preset.tasks
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_model_filter", %{"models" => selected_models}, socket) do
    send(self(), {:filter_models, %{"models" => selected_models}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_task_filter", %{"tasks" => selected_tasks}, socket) do
    send(self(), {:filter_tasks, %{"tasks" => selected_tasks}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    send(self(), {:clear_filters, %{}})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              Filter Results
            </h3>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              Filter by model and task categories for targeted analysis
            </p>
          </div>
          
          <button
            phx-click="clear_all_filters"
            phx-target={@myself}
            class="px-3 py-1 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
          >
            Clear All
          </button>
        </div>
      </div>
      
      <div class="p-6 space-y-6">
        <!-- Filter Presets -->
        <div>
          <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-3">Quick Filters</h4>
          <div class="flex flex-wrap gap-2">
            <%= for preset <- @filter_presets do %>
              <button
                phx-click="apply_preset"
                phx-value-preset={preset.id}
                phx-target={@myself}
                class="px-3 py-1 text-sm bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-300 rounded-md transition-colors"
              >
                <%= preset.name %>
              </button>
            <% end %>
          </div>
        </div>

        <!-- Model Filters -->
        <div>
          <button
            phx-click="toggle_section"
            phx-value-section="models"
            phx-target={@myself}
            class="flex items-center justify-between w-full text-left"
          >
            <h4 class="text-sm font-medium text-gray-900 dark:text-white">
              Model Selection 
              <%= if @model_filters != [] do %>
                <span class="ml-2 px-2 py-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300 rounded-full">
                  <%= length(@model_filters) %> selected
                </span>
              <% end %>
            </h4>
            <svg class={["w-5 h-5 text-gray-400", rotation_class(@expanded_sections.models)]} fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
          
          <%= if @expanded_sections.models do %>
            <div class="mt-3 space-y-2">
              <%= for model <- @available_models do %>
                <label class="flex items-center">
                  <input 
                    type="checkbox" 
                    name="models[]" 
                    value={model.id}
                    checked={model.id in @model_filters}
                    phx-change="update_model_filter"
                    phx-target={@myself}
                    class="rounded border-gray-300 text-blue-600 shadow-sm focus:border-blue-300 focus:ring focus:ring-blue-200 focus:ring-opacity-50"
                  />
                  <span class="ml-3 text-sm">
                    <span class="font-medium text-gray-900 dark:text-white">
                      <%= model.name %>
                    </span>
                    <span class={["ml-2 px-2 py-1 text-xs rounded", "bg-#{model.color}-100 text-#{model.color}-800"]}>
                      <%= model.provider %>
                    </span>
                  </span>
                </label>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Task Category Filters -->
        <div>
          <button
            phx-click="toggle_section"
            phx-value-section="tasks"
            phx-target={@myself}
            class="flex items-center justify-between w-full text-left"
          >
            <h4 class="text-sm font-medium text-gray-900 dark:text-white">
              Task Categories
              <%= if @task_filters != [] do %>
                <span class="ml-2 px-2 py-1 text-xs bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300 rounded-full">
                  <%= length(@task_filters) %> selected
                </span>
              <% end %>
            </h4>
            <svg class={["w-5 h-5 text-gray-400", rotation_class(@expanded_sections.tasks)]} fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
          
          <%= if @expanded_sections.tasks do %>
            <div class="mt-3 space-y-4">
              <!-- Repository Filter -->
              <div>
                <h5 class="text-xs font-medium text-gray-700 dark:text-gray-300 uppercase tracking-wider mb-2">
                  Repositories
                </h5>
                <div class="space-y-2">
                  <%= for repo <- @available_repositories do %>
                    <label class="flex items-center">
                      <input 
                        type="checkbox" 
                        name="tasks[]" 
                        value={repo.id}
                        checked={repo.id in @task_filters}
                        phx-change="update_task_filter"
                        phx-target={@myself}
                        class="rounded border-gray-300 text-green-600 shadow-sm"
                      />
                      <span class="ml-3 text-sm">
                        <span class="font-medium text-gray-900 dark:text-white">
                          <%= repo.name %>
                        </span>
                        <span class="ml-1 text-xs text-gray-500 dark:text-gray-400">
                          (<%= repo.category %>)
                        </span>
                      </span>
                    </label>
                  <% end %>
                </div>
              </div>

              <!-- Complexity Filter -->
              <div>
                <h5 class="text-xs font-medium text-gray-700 dark:text-gray-300 uppercase tracking-wider mb-2">
                  Complexity
                </h5>
                <div class="space-y-2">
                  <%= for complexity <- @complexity_levels do %>
                    <label class="flex items-center">
                      <input 
                        type="checkbox" 
                        name="tasks[]" 
                        value={complexity.id}
                        checked={complexity.id in @task_filters}
                        phx-change="update_task_filter"
                        phx-target={@myself}
                        class="rounded border-gray-300 shadow-sm"
                      />
                      <span class="ml-3 text-sm">
                        <span class={["font-medium", "text-#{complexity.color}-700 dark:text-#{complexity.color}-300"]}>
                          <%= complexity.name %>
                        </span>
                      </span>
                    </label>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp rotation_class(true), do: "transform rotate-180"
  defp rotation_class(false), do: ""
end