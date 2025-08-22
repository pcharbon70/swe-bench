defmodule SweBench.Pipeline.TaskProducer do
  @moduledoc """
  GenStage producer for evaluation task instances.

  Implements demand-based task fetching from database with task
  prioritization, ordering logic, and batch optimization.
  """

  use GenStage
  require Logger

  # alias SweBench.Tasks.Instance - for future database integration

  defstruct [
    :demand,
    :pending_tasks,
    :task_buffer,
    :batch_size,
    :repository_grouping,
    :priority_queue
  ]

  @doc """
  Starts the task producer.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current producer statistics.
  """
  def get_stats do
    GenStage.call(__MODULE__, :get_stats)
  end

  @doc """
  Reloads task queue with fresh tasks from database.
  """
  def reload_tasks do
    GenStage.cast(__MODULE__, :reload_tasks)
  end

  # GenStage callbacks

  @impl GenStage
  def init(opts) do
    batch_size = Keyword.get(opts, :batch_size, 10)
    enable_grouping = Keyword.get(opts, :repository_grouping, true)

    state = %__MODULE__{
      demand: 0,
      pending_tasks: [],
      task_buffer: [],
      batch_size: batch_size,
      repository_grouping: enable_grouping,
      priority_queue: :queue.new()
    }

    Logger.info("TaskProducer started with batch_size=#{batch_size}, grouping=#{enable_grouping}")

    # Schedule initial task loading
    send(self(), :load_initial_tasks)

    {:producer, state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, state) do
    Logger.debug("TaskProducer received demand: #{incoming_demand}")

    new_demand = state.demand + incoming_demand

    {events, new_state} = dispatch_events(%{state | demand: new_demand})

    {:noreply, events, new_state}
  end

  @impl GenStage
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pending_demand: state.demand,
      buffered_tasks: length(state.task_buffer),
      priority_queue_size: :queue.len(state.priority_queue),
      repository_grouping: state.repository_grouping,
      batch_size: state.batch_size
    }

    {:reply, stats, [], state}
  end

  @impl GenStage
  def handle_cast(:reload_tasks, state) do
    Logger.info("Reloading tasks from database")

    {:ok, tasks} = fetch_available_tasks()
    new_buffer = prioritize_and_group_tasks(tasks, state.repository_grouping)
    new_state = %{state | task_buffer: new_buffer}

    {events, final_state} = dispatch_events(new_state)
    {:noreply, events, final_state}
  end

  @impl GenStage
  def handle_info(:load_initial_tasks, state) do
    Logger.debug("Loading initial tasks")

    {:ok, tasks} = fetch_available_tasks()
    new_buffer = prioritize_and_group_tasks(tasks, state.repository_grouping)
    new_state = %{state | task_buffer: new_buffer}

    {events, final_state} = dispatch_events(new_state)
    {:noreply, events, final_state}
  end

  # Private helper functions

  defp dispatch_events(state) do
    {events_to_send, remaining_buffer} = take_events_for_demand(state.task_buffer, state.demand)

    new_demand = max(0, state.demand - length(events_to_send))
    new_state = %{state | demand: new_demand, task_buffer: remaining_buffer}

    if length(events_to_send) > 0 do
      Logger.debug("TaskProducer dispatching #{length(events_to_send)} events")
    end

    {events_to_send, new_state}
  end

  defp take_events_for_demand(buffer, demand) when demand <= 0, do: {[], buffer}
  defp take_events_for_demand([], _demand), do: {[], []}

  defp take_events_for_demand(buffer, demand) do
    {events, remaining} = Enum.split(buffer, demand)
    {events, remaining}
  end

  defp fetch_available_tasks do
    # Placeholder for actual database query
    # Would use Ash.Query to fetch pending task instances
    sample_tasks = [
      %{id: 1, repository: "phoenix", priority: :high, issue_number: 101, difficulty: :medium},
      %{id: 2, repository: "ecto", priority: :medium, issue_number: 201, difficulty: :low},
      %{id: 3, repository: "jason", priority: :low, issue_number: 301, difficulty: :low},
      %{id: 4, repository: "tesla", priority: :medium, issue_number: 401, difficulty: :medium},
      %{id: 5, repository: "credo", priority: :high, issue_number: 501, difficulty: :high}
    ]

    {:ok, sample_tasks}
  end

  defp prioritize_and_group_tasks(tasks, enable_grouping) do
    prioritized = Enum.sort_by(tasks, &task_priority_score/1, :desc)

    if enable_grouping do
      group_tasks_by_repository(prioritized)
    else
      prioritized
    end
  end

  defp task_priority_score(task) do
    base_score =
      case task.priority do
        :high -> 100
        :medium -> 50
        :low -> 10
      end

    difficulty_modifier =
      case task.difficulty do
        :high -> 20
        :medium -> 10
        :low -> 5
      end

    base_score + difficulty_modifier
  end

  defp group_tasks_by_repository(tasks) do
    tasks
    |> Enum.group_by(& &1.repository)
    |> Enum.flat_map(fn {_repo, repo_tasks} -> repo_tasks end)
  end
end
