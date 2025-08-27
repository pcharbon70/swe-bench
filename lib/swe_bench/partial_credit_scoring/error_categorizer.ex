defmodule SweBench.PartialCreditScoring.ErrorCategorizer do
  @moduledoc """
  Categorizes and analyzes errors for comprehensive feedback.

  Provides hierarchical error classification and severity analysis
  to enable targeted improvement suggestions.
  """

  use GenServer
  require Logger

  defstruct [:config]

  @doc """
  Starts the error categorizer with the given configuration.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Categorizes errors from the given solution analysis.
  """
  def categorize_errors(errors, options \\ []) do
    GenServer.call(__MODULE__, {:categorize_errors, errors, options}, 30_000)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{config: config}
    Logger.info("ErrorCategorizer initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:categorize_errors, errors, _options}, _from, state) do
    categorized = perform_error_categorization(errors, state.config)
    {:reply, {:ok, categorized}, state}
  rescue
    error ->
      Logger.error("Error categorization failed: #{inspect(error)}")
      {:reply, {:error, error}, state}
  end

  # Private functions

  defp perform_error_categorization(errors, config) do
    error_categories = Map.get(config, :error_categories, %{})

    categorized =
      Enum.reduce(errors, %{}, fn error, acc ->
        category = determine_error_category(error)
        subcategory = determine_error_subcategory(error, category)
        severity = determine_error_severity(error)

        category_data = Map.get(acc, category, [])

        updated_data = [
          %{
            error: error,
            subcategory: subcategory,
            severity: severity,
            message: extract_error_message(error),
            location: extract_error_location(error)
          }
          | category_data
        ]

        Map.put(acc, category, updated_data)
      end)

    %{
      categorized_errors: categorized,
      summary: generate_error_summary(categorized),
      recommendations: generate_error_recommendations(categorized, error_categories)
    }
  end

  defp determine_error_category(error) when is_map(error) do
    error_type = Map.get(error, :type, :unknown)

    case error_type do
      type when type in [:syntax_error, :parse_error, :compilation_error] -> :compilation
      type when type in [:test_failure, :assertion_error, :timeout] -> :test
      type when type in [:runtime_error, :exception, :crash] -> :runtime
      type when type in [:logic_error, :incorrect_output] -> :logic
      _ -> :unknown
    end
  end

  defp determine_error_category(error) when is_binary(error) do
    cond do
      compilation_error?(error) -> :compilation
      test_error?(error) -> :test
      runtime_error?(error) -> :runtime
      logic_error?(error) -> :logic
      true -> :unknown
    end
  end

  defp compilation_error?(error), do: String.contains?(error, "syntax") or String.contains?(error, "parse")
  defp test_error?(error), do: String.contains?(error, "test") or String.contains?(error, "assert")
  defp runtime_error?(error), do: String.contains?(error, "runtime") or String.contains?(error, "exception")
  defp logic_error?(error), do: String.contains?(error, "logic") or String.contains?(error, "incorrect")

  defp determine_error_category(_error), do: :unknown

  defp determine_error_subcategory(error, :compilation) do
    message = extract_error_message(error)

    cond do
      String.contains?(message, "syntax") ->
        :syntax_error

      String.contains?(message, "type") ->
        :type_error

      String.contains?(message, "dependency") or String.contains?(message, "module") ->
        :missing_dependency

      String.contains?(message, "macro") ->
        :macro_error

      true ->
        :general_compilation_error
    end
  end

  defp determine_error_subcategory(error, :test) do
    message = extract_error_message(error)

    cond do
      String.contains?(message, "assertion") -> :assertion_failure
      String.contains?(message, "timeout") -> :timeout
      String.contains?(message, "setup") -> :setup_error
      String.contains?(message, "teardown") -> :teardown_error
      true -> :general_test_failure
    end
  end

  defp determine_error_subcategory(error, :runtime) do
    message = extract_error_message(error)

    cond do
      String.contains?(message, "exception") -> :exception
      String.contains?(message, "crash") -> :crash
      String.contains?(message, "infinite") or String.contains?(message, "loop") -> :infinite_loop
      String.contains?(message, "memory") -> :memory_error
      true -> :general_runtime_error
    end
  end

  defp determine_error_subcategory(error, :logic) do
    message = extract_error_message(error)

    cond do
      String.contains?(message, "output") -> :incorrect_output
      String.contains?(message, "edge") -> :edge_case_failure
      String.contains?(message, "algorithm") -> :algorithm_error
      String.contains?(message, "data") -> :data_structure_misuse
      true -> :general_logic_error
    end
  end

  defp determine_error_subcategory(_error, _category), do: :unknown

  defp determine_error_severity(error) do
    message = extract_error_message(error)

    cond do
      String.contains?(message, "critical") or String.contains?(message, "fatal") -> :critical
      String.contains?(message, "error") -> :major
      String.contains?(message, "warning") -> :minor
      true -> :minor
    end
  end

  defp extract_error_message(error) when is_map(error) do
    Map.get(error, :message, Map.get(error, :description, to_string(error)))
  end

  defp extract_error_message(error) when is_binary(error), do: error
  defp extract_error_message(error), do: to_string(error)

  defp extract_error_location(error) when is_map(error) do
    %{
      file: Map.get(error, :file),
      line: Map.get(error, :line),
      column: Map.get(error, :column)
    }
  end

  defp extract_error_location(_error), do: %{file: nil, line: nil, column: nil}

  defp generate_error_summary(categorized) do
    total_errors =
      categorized
      |> Enum.reduce(0, fn {_category, errors}, acc -> acc + length(errors) end)

    category_counts =
      categorized
      |> Enum.map(fn {category, errors} -> {category, length(errors)} end)
      |> Enum.into(%{})

    severity_counts =
      categorized
      |> Enum.reduce(%{critical: 0, major: 0, minor: 0}, fn {_category, errors}, acc ->
        Enum.reduce(errors, acc, fn error, inner_acc ->
          severity = Map.get(error, :severity, :minor)
          Map.update(inner_acc, severity, 1, &(&1 + 1))
        end)
      end)

    %{
      total_errors: total_errors,
      category_counts: category_counts,
      severity_counts: severity_counts
    }
  end

  defp generate_error_recommendations(categorized, _error_categories) do
    Enum.reduce(categorized, [], fn {category, _errors}, acc ->
      case category do
        :compilation ->
          ["Review syntax and type definitions" | acc]

        :test ->
          ["Examine test logic and expected outcomes" | acc]

        :runtime ->
          ["Add error handling and input validation" | acc]

        :logic ->
          ["Verify algorithm correctness and edge cases" | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end
end
