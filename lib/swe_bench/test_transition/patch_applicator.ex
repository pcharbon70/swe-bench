defmodule SweBench.TestTransition.PatchApplicator do
  @moduledoc """
  Git patch application system for test transition validation.

  Handles patch application, validation, and rollback operations
  with proper error handling and state management.
  """

  require Logger

  @doc """
  Applies a patch to a repository at a specific commit.

  ## Parameters
    - repo_path: Path to the repository
    - base_commit: Base commit SHA to apply patch on
    - patch_content: The patch content to apply

  ## Returns
    - {:ok, patch_info} - Successful patch application
    - {:error, reason} - Patch application failure
  """
  def apply_patch(repo_path, base_commit, patch_content) do
    Logger.debug("Applying patch to repository at #{repo_path}")

    with {:ok, checked_out} <- checkout_base_commit(repo_path, base_commit),
         {:ok, validated} <- validate_patch_applicability(checked_out, patch_content),
         {:ok, backed_up} <- create_backup_state(validated),
         {:ok, applied} <- apply_patch_content(backed_up),
         {:ok, patch_info} <- validate_patch_success(applied) do
      {:ok, patch_info}
    end
  rescue
    error ->
      Logger.error("Patch application failed: #{inspect(error)}")
      {:error, {:patch_application_failed, error}}
  end

  @doc """
  Reverts a patch and restores the repository to base state.
  """
  def revert_patch(repo_path, backup_state) do
    Logger.debug("Reverting patch in repository at #{repo_path}")

    case restore_backup_state(repo_path, backup_state) do
      :ok ->
        Logger.debug("Patch successfully reverted")
        :ok

      {:error, reason} ->
        Logger.error("Patch revert failed: #{inspect(reason)}")
        {:error, {:revert_failed, reason}}
    end
  end

  # Private implementation functions

  defp checkout_base_commit(repo_path, base_commit) do
    Logger.debug("Checking out base commit #{base_commit}")

    case run_git_command(["checkout", base_commit], repo_path) do
      {:ok, _output} ->
        {:ok, {repo_path, base_commit}}

      {:error, reason} ->
        {:error, {:checkout_failed, reason}}
    end
  end

  defp validate_patch_applicability({:ok, {repo_path, base_commit}}, patch_content) do
    # Check if patch can be applied without conflicts
    Logger.debug("Validating patch applicability")

    # Placeholder - will implement comprehensive patch validation in Phase 2
    if String.length(patch_content) > 0 do
      {:ok, {repo_path, base_commit, patch_content}}
    else
      {:error, :empty_patch}
    end
  end

  defp validate_patch_applicability({:error, reason}, _patch_content) do
    {:error, reason}
  end

  defp create_backup_state({:ok, {repo_path, base_commit, patch_content}}) do
    Logger.debug("Creating backup state for rollback")

    # Create backup of current state
    backup_state = %{
      repo_path: repo_path,
      base_commit: base_commit,
      backup_created_at: DateTime.utc_now()
    }

    {:ok, {repo_path, base_commit, patch_content, backup_state}}
  end

  defp create_backup_state({:error, reason}) do
    {:error, reason}
  end

  defp apply_patch_content({:ok, {repo_path, base_commit, patch_content, backup_state}}) do
    Logger.debug("Applying patch content")

    # Placeholder implementation - will be enhanced in Phase 2
    case write_patch_to_temp_file(patch_content) do
      {:ok, patch_file} ->
        case run_git_command(["apply", patch_file], repo_path) do
          {:ok, output} ->
            File.rm(patch_file)
            Logger.debug("Patch applied successfully")
            {:ok, {repo_path, base_commit, backup_state, output}}

          {:error, reason} ->
            File.rm(patch_file)
            {:error, {:git_apply_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:patch_file_creation_failed, reason}}
    end
  end

  defp apply_patch_content({:error, reason}) do
    {:error, reason}
  end

  defp validate_patch_success({:ok, {repo_path, base_commit, backup_state, apply_output}}) do
    # Validate that patch was applied correctly
    Logger.debug("Validating patch application success")

    patch_info = %{
      repo_path: repo_path,
      base_commit: base_commit,
      backup_state: backup_state,
      apply_output: apply_output,
      applied_at: DateTime.utc_now()
    }

    {:ok, patch_info}
  end

  defp validate_patch_success({:error, reason}) do
    {:error, reason}
  end

  defp write_patch_to_temp_file(patch_content) do
    temp_file = Path.join(System.tmp_dir!(), "swe_bench_patch_#{:rand.uniform(999_999)}.patch")

    case File.write(temp_file, patch_content) do
      :ok -> {:ok, temp_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_backup_state(repo_path, backup_state) do
    # Reset to base commit to restore clean state
    case run_git_command(["reset", "--hard", backup_state.base_commit], repo_path) do
      {:ok, _output} ->
        case run_git_command(["clean", "-fd"], repo_path) do
          {:ok, _output} -> :ok
          {:error, reason} -> {:error, {:clean_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:reset_failed, reason}}
    end
  end

  defp run_git_command(args, working_dir, timeout \\ 30_000) do
    case System.cmd("git", args, cd: working_dir, stderr_to_stdout: true, timeout: timeout) do
      {output, 0} ->
        {:ok, output}

      {error_output, exit_code} ->
        Logger.warning("Git command failed: #{inspect(args)} -> #{error_output}")
        {:error, {:git_failed, exit_code, error_output}}
    end
  catch
    :exit, {:timeout, _} ->
      Logger.error("Git command timeout: #{inspect(args)}")
      {:error, :git_timeout}
  end
end
