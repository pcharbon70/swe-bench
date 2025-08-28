defmodule SweBenchWeb.Components.Admin.EvaluationForm do
  @moduledoc """
  Admin-only evaluation submission form component.

  Provides secure evaluation submission interface with model selection,
  repository selection, and real-time validation.
  """

  use SweBenchWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:form_data, %{})
      |> assign(:validation_errors, %{})
      |> assign(:submitting, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_form", %{"evaluation" => form_params}, socket) do
    # Validate form inputs
    validation_result = validate_evaluation_form(form_params)
    
    socket =
      socket
      |> assign(:form_data, form_params)
      |> assign(:validation_errors, validation_result.errors)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_evaluation", %{"evaluation" => form_params}, socket) do
    case validate_evaluation_form(form_params) do
      %{valid: true} ->
        socket = assign(socket, :submitting, true)
        
        # Send to parent LiveView for actual submission
        send(self(), {:submit_evaluation, form_params})
        
        # Reset form
        socket =
          socket
          |> assign(:form_data, %{})
          |> assign(:validation_errors, %{})
          |> assign(:submitting, false)

        {:noreply, socket}
      
      %{valid: false, errors: errors} ->
        socket = assign(socket, :validation_errors, errors)
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-change="validate_form" phx-submit="submit_evaluation" phx-target={@myself}>
      <div class="p-6 space-y-6">
        <!-- Model Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            LLM Model
          </label>
          <select 
            name="evaluation[model]" 
            value={@form_data["model"]}
            class={[
              "w-full rounded border focus:border-blue-500 focus:ring-blue-500",
              input_border_class(@validation_errors["model"])
            ]}
            required
          >
            <option value="">Select a model...</option>
            <%= for model <- @available_models do %>
              <option value={model.id}>
                <%= model.name %> (<%= model.provider %>)
              </option>
            <% end %>
          </select>
          <.field_error errors={@validation_errors["model"]} />
        </div>

        <!-- Repository Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Repository
          </label>
          <select 
            name="evaluation[repository]" 
            value={@form_data["repository"]}
            class={[
              "w-full rounded border focus:border-blue-500 focus:ring-blue-500",
              input_border_class(@validation_errors["repository"])
            ]}
            required
          >
            <option value="">Select a repository...</option>
            <%= for repo <- @available_repositories do %>
              <option value={repo}>
                <%= format_repository_name(repo) %>
              </option>
            <% end %>
          </select>
          <.field_error errors={@validation_errors["repository"]} />
        </div>

        <!-- Task Type Selection -->
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Task Type (Optional)
          </label>
          <select 
            name="evaluation[task_type]" 
            value={@form_data["task_type"]}
            class="w-full rounded border border-gray-300 focus:border-blue-500 focus:ring-blue-500"
          >
            <option value="">All available tasks</option>
            <option value="web_framework">Web Framework</option>
            <option value="database">Database</option>
            <option value="real_time_web">Real-time Web</option>
            <option value="data_pipeline">Data Pipeline</option>
            <option value="performance">Performance</option>
          </select>
        </div>

        <!-- Complexity Filter -->
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Complexity Level (Optional)
          </label>
          <div class="grid grid-cols-2 gap-2">
            <%= for complexity <- ["low", "medium", "high", "very_high"] do %>
              <label class="flex items-center">
                <input 
                  type="checkbox" 
                  name="evaluation[complexity][]"
                  value={complexity}
                  checked={complexity in (@form_data["complexity"] || [])}
                  class="rounded border-gray-300 text-blue-600"
                />
                <span class="ml-2 text-sm text-gray-700 dark:text-gray-300">
                  <%= String.capitalize(String.replace(complexity, "_", " ")) %>
                </span>
              </label>
            <% end %>
          </div>
        </div>

        <!-- Advanced Options -->
        <div>
          <details class="group">
            <summary class="cursor-pointer text-sm font-medium text-gray-700 dark:text-gray-300">
              Advanced Options
            </summary>
            <div class="mt-4 space-y-4 pl-4 border-l-2 border-gray-200 dark:border-gray-700">
              <div>
                <label class="flex items-center">
                  <input 
                    type="checkbox" 
                    name="evaluation[include_distributed]"
                    checked={@form_data["include_distributed"]}
                    class="rounded border-gray-300 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700 dark:text-gray-300">
                    Include distributed evaluation
                  </span>
                </label>
              </div>
              
              <div>
                <label class="flex items-center">
                  <input 
                    type="checkbox" 
                    name="evaluation[include_concurrent]"
                    checked={@form_data["include_concurrent"]}
                    class="rounded border-gray-300 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700 dark:text-gray-300">
                    Include concurrent analysis
                  </span>
                </label>
              </div>
              
              <div>
                <label class="flex items-center">
                  <input 
                    type="checkbox" 
                    name="evaluation[include_performance]"
                    checked={@form_data["include_performance"]}
                    class="rounded border-gray-300 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700 dark:text-gray-300">
                    Include performance benchmarking
                  </span>
                </label>
              </div>
            </div>
          </details>
        </div>

        <!-- Submit Button -->
        <div class="pt-4">
          <button 
            type="submit"
            disabled={@submitting or not form_valid?(@validation_errors)}
            class={[
              "w-full px-4 py-2 text-sm font-medium rounded-md transition-colors",
              submit_button_classes(@submitting, form_valid?(@validation_errors))
            ]}
          >
            <%= if @submitting do %>
              <div class="flex items-center justify-center">
                <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                Submitting...
              </div>
            <% else %>
              Submit Evaluation
            <% end %>
          </button>
        </div>
      </div>
    </form>
    """
  end

  # Helper components and functions

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

  defp validate_evaluation_form(form_params) do
    errors = %{}
    
    # Validate model
    errors = if Map.get(form_params, "model", "") == "" do
      Map.put(errors, "model", ["Model is required"])
    else
      errors
    end
    
    # Validate repository
    errors = if Map.get(form_params, "repository", "") == "" do
      Map.put(errors, "repository", ["Repository is required"])
    else
      errors
    end
    
    %{
      valid: map_size(errors) == 0,
      errors: errors
    }
  end

  defp form_valid?(validation_errors) do
    map_size(validation_errors) == 0
  end

  defp input_border_class(nil), do: "border-gray-300 dark:border-gray-600"
  defp input_border_class([]), do: "border-gray-300 dark:border-gray-600"
  defp input_border_class(_errors), do: "border-red-300 dark:border-red-600"

  defp submit_button_classes(true, _valid) do
    "bg-gray-400 text-white cursor-not-allowed"
  end

  defp submit_button_classes(false, true) do
    "bg-blue-600 hover:bg-blue-700 text-white cursor-pointer"
  end

  defp submit_button_classes(false, false) do
    "bg-gray-400 text-white cursor-not-allowed"
  end

  defp format_repository_name(repo_name) do
    repo_name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end