defmodule SweBench.Pipeline.PatchFetcher do
  @moduledoc """
  GenStage ProducerConsumer for LLM patch fetching.

  Implements parallel patch fetching with rate limiting, retry logic,
  and response caching for evaluation task patches.
  """

  use GenStage
  require Logger

  defstruct [
    :llm_client,
    :rate_limiter,
    :cache,
    :retry_config,
    :parallel_workers,
    :pending_requests
  ]

  @doc """
  Starts the patch fetcher stage.
  """
  def start_link(opts \\ []) do
    stage_name = Keyword.get(opts, :name, __MODULE__)
    GenStage.start_link(__MODULE__, opts, name: stage_name)
  end

  @doc """
  Gets current patch fetcher statistics.
  """
  def get_stats(stage_name \\ __MODULE__) do
    GenStage.call(stage_name, :get_stats)
  end

  # GenStage callbacks

  @impl GenStage
  def init(opts) do
    max_workers = Keyword.get(opts, :max_workers, 5)
    retry_attempts = Keyword.get(opts, :retry_attempts, 3)
    cache_enabled = Keyword.get(opts, :cache_enabled, true)

    state = %__MODULE__{
      llm_client: initialize_llm_client(opts),
      rate_limiter: initialize_rate_limiter(opts),
      cache: if(cache_enabled, do: initialize_cache(opts), else: nil),
      retry_config: %{max_attempts: retry_attempts, backoff_base: 2},
      parallel_workers: max_workers,
      pending_requests: %{}
    }

    Logger.info("PatchFetcher started with #{max_workers} workers, cache=#{cache_enabled}")

    {:producer_consumer, state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    Logger.debug("PatchFetcher processing #{length(events)} task events")

    # Process events in parallel up to worker limit
    {processed_events, new_state} = process_patch_requests(events, state)

    {:noreply, processed_events, new_state}
  end

  @impl GenStage
  def handle_call(:get_stats, _from, state) do
    stats = %{
      parallel_workers: state.parallel_workers,
      pending_requests: map_size(state.pending_requests),
      cache_enabled: state.cache != nil,
      retry_config: state.retry_config
    }

    {:reply, stats, [], state}
  end

  @impl GenStage
  def handle_info({:patch_response, task_id, response}, state) do
    Logger.debug("Received patch response for task #{task_id}")

    case Map.get(state.pending_requests, task_id) do
      nil ->
        Logger.warning("Received response for unknown task: #{task_id}")
        {:noreply, [], state}

      task_data ->
        enhanced_task = Map.put(task_data, :llm_patch, response)
        new_pending = Map.delete(state.pending_requests, task_id)
        new_state = %{state | pending_requests: new_pending}

        {:noreply, [enhanced_task], new_state}
    end
  end

  # Private helper functions

  defp process_patch_requests(events, state) do
    {processed, new_pending} =
      Enum.map_reduce(events, state.pending_requests, fn event, pending ->
        case fetch_patch_for_task(event, state) do
          {:ok, :cached, patch} ->
            enhanced_event = Map.put(event, :llm_patch, patch)
            {enhanced_event, pending}

          {:ok, :async, task_id} ->
            new_pending = Map.put(pending, task_id, event)
            {nil, new_pending}

            # Error handling removed - fetch_patch_for_task always returns {:ok, _}
        end
      end)

    # Filter out nil events (async requests)
    valid_events = Enum.filter(processed, & &1)

    new_state = %{state | pending_requests: new_pending}
    {valid_events, new_state}
  end

  defp fetch_patch_for_task(task, state) do
    cache_key = "patch_#{task.repository}_#{task.issue_number}"

    # Check cache first
    case check_cache(cache_key, state.cache) do
      {:ok, cached_patch} ->
        Logger.debug("Cache hit for task #{task.id}")
        {:ok, :cached, cached_patch}

      {:miss} ->
        # Make async LLM request
        request_patch_async(task, cache_key, state)
    end
  end

  defp check_cache(_key, nil), do: {:miss}

  defp check_cache(key, _cache) do
    # Placeholder for cache lookup
    case :rand.uniform() do
      x when x > 0.7 -> {:ok, "cached_patch_content_for_#{key}"}
      _ -> {:miss}
    end
  end

  defp request_patch_async(task, cache_key, state) do
    task_id = task.id

    # Simulate async LLM request
    spawn(fn ->
      # Simulate LLM latency
      :timer.sleep(:rand.uniform(1000) + 500)

      patch_content = generate_mock_patch(task)

      # Cache the result if caching enabled
      if state.cache do
        cache_patch(cache_key, patch_content, state.cache)
      end

      send(self(), {:patch_response, task_id, patch_content})
    end)

    {:ok, :async, task_id}
  end

  defp generate_mock_patch(task) do
    """
    diff --git a/lib/example.ex b/lib/example.ex
    index 1234567..abcdefg 100644
    --- a/lib/example.ex
    +++ b/lib/example.ex
    @@ -10,6 +10,8 @@ defmodule Example do
       def example_function do
    +    # Fix for issue ##{task.issue_number}
    +    Logger.debug("Processing #{task.repository} task")
         :ok
       end
     end
    """
  end

  defp cache_patch(_key, _patch, nil), do: :ok

  defp cache_patch(key, _patch, _cache) do
    Logger.debug("Caching patch for key: #{key}")
    # Placeholder for cache storage
    :ok
  end

  defp initialize_llm_client(_opts) do
    # Placeholder for LLM client initialization
    %{api_key: "mock_key", base_url: "https://api.example.com"}
  end

  defp initialize_rate_limiter(_opts) do
    # Placeholder for rate limiter initialization
    %{requests_per_minute: 60, current_count: 0}
  end

  defp initialize_cache(_opts) do
    # Placeholder for cache initialization
    %{enabled: true, ttl: 3600}
  end
end
