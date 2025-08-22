defmodule SweBench.Issues.DiffParser do
  @moduledoc """
  PR diff parsing and test modification detection.

  Parses GitHub PR diffs to identify code changes, test file modifications,
  and categorize changes for evaluation task generation.
  """

  require Logger

  @doc """
  Parses a PR diff and extracts test file modifications.
  """
  def parse_diff_for_test_modifications(diff_content) when is_binary(diff_content) do
    diff_content
    |> String.split("\n")
    |> extract_file_changes()
    |> filter_test_files()
    |> categorize_test_changes()
  end

  def parse_diff_for_test_modifications(_), do: %{test_files: [], changes: []}

  @doc """
  Extracts all modified files from a diff.
  """
  def extract_modified_files(diff_content) when is_binary(diff_content) do
    diff_content
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "diff --git"))
    |> Enum.map(&extract_file_path_from_diff_line/1)
    |> Enum.filter(& &1)
  end

  def extract_modified_files(_), do: []

  @doc """
  Categorizes changes by type (added, modified, deleted).
  """
  def categorize_changes(diff_content) when is_binary(diff_content) do
    lines = String.split(diff_content, "\n")

    %{
      added_files: extract_added_files(lines),
      modified_files: extract_modified_files(diff_content),
      deleted_files: extract_deleted_files(lines),
      additions: count_additions(lines),
      deletions: count_deletions(lines)
    }
  end

  def categorize_changes(_),
    do: %{added_files: [], modified_files: [], deleted_files: [], additions: 0, deletions: 0}

  @doc """
  Identifies if changes affect test files specifically.
  """
  def affects_test_files?(diff_content) when is_binary(diff_content) do
    test_files = parse_diff_for_test_modifications(diff_content)
    length(test_files.test_files) > 0
  end

  def affects_test_files?(_), do: false

  # Private helper functions

  defp extract_file_changes(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce([], &process_diff_line(&1, &2, lines))
    |> Enum.reverse()
  end

  defp process_diff_line({line, index}, acc, lines) do
    if String.starts_with?(line, "diff --git") do
      file_path = extract_file_path_from_diff_line(line)
      change_lines = extract_change_lines_for_file(lines, index)
      add_file_change_if_valid(file_path, change_lines, acc)
    else
      acc
    end
  end

  defp add_file_change_if_valid(nil, _change_lines, acc), do: acc
  defp add_file_change_if_valid(path, change_lines, acc), do: [{path, change_lines} | acc]

  defp extract_file_path_from_diff_line(line) do
    case Regex.run(~r/diff --git a\/(.+) b\/(.+)/, line) do
      [_, _old_path, new_path] -> new_path
      _ -> nil
    end
  end

  defp extract_change_lines_for_file(lines, start_index) do
    lines
    |> Enum.drop(start_index + 1)
    |> Enum.take_while(fn line ->
      not String.starts_with?(line, "diff --git")
    end)
    |> Enum.filter(fn line ->
      String.starts_with?(line, "+") or String.starts_with?(line, "-")
    end)
  end

  defp filter_test_files(file_changes) do
    file_changes
    |> Enum.filter(fn {file_path, _changes} ->
      test_file?(file_path)
    end)
  end

  defp test_file?(file_path) when is_binary(file_path) do
    String.contains?(file_path, "test") or
      String.ends_with?(file_path, "_test.exs") or
      String.starts_with?(file_path, "test/") or
      String.contains?(file_path, "/test/")
  end

  defp test_file?(_), do: false

  defp categorize_test_changes(test_file_changes) do
    changes =
      Enum.map(test_file_changes, fn {file_path, change_lines} ->
        %{
          file: file_path,
          additions: count_additions(change_lines),
          deletions: count_deletions(change_lines),
          net_changes: count_additions(change_lines) - count_deletions(change_lines),
          change_type: determine_change_type(change_lines)
        }
      end)

    %{
      test_files: Enum.map(test_file_changes, fn {file_path, _} -> file_path end),
      changes: changes
    }
  end

  defp extract_added_files(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "new file mode"))
    |> Enum.map(fn _line ->
      # Would need to correlate with previous diff --git line
      # Simplified for now
      nil
    end)
    |> Enum.filter(& &1)
  end

  defp extract_deleted_files(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "deleted file mode"))
    |> Enum.map(fn _line ->
      # Would need to correlate with previous diff --git line
      # Simplified for now
      nil
    end)
    |> Enum.filter(& &1)
  end

  defp count_additions(lines) when is_list(lines) do
    lines
    |> Enum.count(fn line ->
      String.starts_with?(line, "+") and not String.starts_with?(line, "+++")
    end)
  end

  defp count_additions(_), do: 0

  defp count_deletions(lines) when is_list(lines) do
    lines
    |> Enum.count(fn line ->
      String.starts_with?(line, "-") and not String.starts_with?(line, "---")
    end)
  end

  defp count_deletions(_), do: 0

  defp determine_change_type(change_lines) do
    additions = count_additions(change_lines)
    deletions = count_deletions(change_lines)

    cond do
      additions > 0 and deletions == 0 -> :addition
      additions == 0 and deletions > 0 -> :deletion
      additions > 0 and deletions > 0 -> :modification
      true -> :no_change
    end
  end
end
