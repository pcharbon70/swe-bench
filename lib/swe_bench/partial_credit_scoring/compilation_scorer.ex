defmodule SweBench.PartialCreditScoring.CompilationScorer do
  @moduledoc """
  Scores compilation success and analyzes compilation errors.
  
  Evaluates whether generated code compiles successfully and categorizes
  compilation errors for detailed feedback. Provides 25% threshold scoring
  based on compilation achievement.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the compilation scorer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Scores compilation success for the given solution.
  """
  def score(solution_data, options \\ []) do
    GenServer.call(__MODULE__, {:score, solution_data, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("CompilationScorer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:score, solution_data, _options}, _from, state) do
    try do
      score_result = evaluate_compilation(solution_data, state.config)
      {:reply, {:ok, score_result}, state}
    rescue
      error ->
        Logger.error("Compilation scoring failed: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  # Private functions

  defp evaluate_compilation(solution_data, config) do
    # TODO: Implement actual compilation analysis
    # For now, return a basic score structure
    
    compilation_threshold = get_in(config, [:dimensions, :compilation, :threshold]) || 25
    
    # Mock compilation evaluation - replace with actual implementation
    compilation_successful = Map.get(solution_data, :compilation_successful, false)
    compilation_errors = Map.get(solution_data, :compilation_errors, [])
    
    score = if compilation_successful do
      100.0
    else
      # Partial credit based on error analysis
      error_count = length(compilation_errors)
      max(0.0, 100.0 - (error_count * 20.0))
    end

    %{
      score: score,
      threshold_met: score >= compilation_threshold,
      details: %{
        compilation_successful: compilation_successful,
        error_count: length(compilation_errors),
        errors: categorize_compilation_errors(compilation_errors),
        threshold: compilation_threshold
      }
    }
  end

  defp categorize_compilation_errors(errors) do
    # TODO: Implement sophisticated error categorization
    Enum.map(errors, fn error ->
      %{
        type: determine_error_type(error),
        message: to_string(error),
        severity: :error
      }
    end)
  end

  defp determine_error_type(error) when is_binary(error) do
    cond do
      String.contains?(error, "syntax") -> :syntax_error
      String.contains?(error, "type") -> :type_error
      String.contains?(error, "dependency") or String.contains?(error, "module") -> :missing_dependency
      String.contains?(error, "macro") -> :macro_error
      true -> :unknown_error
    end
  end

  defp determine_error_type(_error), do: :unknown_error
end