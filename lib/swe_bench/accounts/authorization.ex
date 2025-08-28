defmodule SweBench.Accounts.Authorization do
  @moduledoc """
  Role-based authorization framework for SWE-bench system.

  Provides admin/public role separation with clear permissions for
  evaluation execution, result access, and system administration.
  """

  @doc """
  Defines user roles and their capabilities.
  """
  def user_roles do
    %{
      admin: %{
        can_submit_evaluations: true,
        can_cancel_evaluations: true,
        can_view_system_logs: true,
        can_access_admin_interface: true,
        can_manage_users: true,
        can_view_system_health: true,
        can_modify_system_settings: true,
        evaluation_quota: :unlimited
      },
      public: %{
        can_submit_evaluations: false,
        can_cancel_evaluations: false,
        can_view_system_logs: false,
        can_access_admin_interface: false,
        can_manage_users: false,
        can_view_system_health: false,
        can_modify_system_settings: false,
        evaluation_quota: 0
      },
      researcher: %{
        can_submit_evaluations: false,
        can_cancel_evaluations: false,
        can_view_system_logs: false,
        can_access_admin_interface: false,
        can_manage_users: false,
        can_view_system_health: false,
        can_modify_system_settings: false,
        evaluation_quota: 10  # 10 evaluations per month
      }
    }
  end

  @doc """
  Checks if a user has permission to perform a specific action.
  """
  def authorized?(user, action) when is_atom(action) do
    case get_user_role(user) do
      nil -> false
      role -> 
        permissions = get_role_permissions(role)
        Map.get(permissions, action, false)
    end
  end

  @doc """
  Checks if a user can submit evaluations.
  """
  def can_submit_evaluation?(user) do
    authorized?(user, :can_submit_evaluations)
  end

  @doc """
  Checks if a user can access admin interfaces.
  """
  def can_access_admin?(user) do
    authorized?(user, :can_access_admin_interface)
  end

  @doc """
  Checks if a user can view system logs.
  """
  def can_view_logs?(user) do
    authorized?(user, :can_view_system_logs)
  end

  @doc """
  Gets the user's evaluation quota.
  """
  def get_evaluation_quota(user) do
    case get_user_role(user) do
      nil -> 0
      role ->
        permissions = get_role_permissions(role)
        Map.get(permissions, :evaluation_quota, 0)
    end
  end

  @doc """
  Determines if a user is an admin.
  """
  def admin_user?(user) do
    get_user_role(user) == :admin
  end

  @doc """
  Determines if a user is public (unauthenticated).
  """
  def public_user?(user) do
    user == nil or get_user_role(user) == :public
  end

  @doc """
  Gets user role from user struct or assigns.
  """
  def get_user_role(nil), do: :public
  def get_user_role(%{role: role}) when is_atom(role), do: role
  def get_user_role(%{"role" => role}) when is_binary(role), do: String.to_existing_atom(role)
  def get_user_role(user) when is_map(user) do
    # Check if role is stored in a different field
    cond do
      Map.has_key?(user, :user_role) -> user.user_role
      Map.has_key?(user, "user_role") -> user["user_role"]
      true -> :public  # Default to public if no role found
    end
  rescue
    _ -> :public
  end
  def get_user_role(_), do: :public

  @doc """
  Gets permissions for a specific role.
  """
  def get_role_permissions(role) do
    user_roles()
    |> Map.get(role, %{})
  end

  @doc """
  Creates authorization context for LiveView components.
  """
  def create_auth_context(user) do
    role = get_user_role(user)
    permissions = get_role_permissions(role)
    
    %{
      user: user,
      role: role,
      permissions: permissions,
      authenticated: user != nil,
      admin: admin_user?(user)
    }
  end

  @doc """
  Validates if user can access a specific LiveView route.
  """
  def can_access_route?(user, route_path) do
    cond do
      String.starts_with?(route_path, "/admin") -> can_access_admin?(user)
      String.starts_with?(route_path, "/dashboard") -> true  # Public access
      route_path == "/" -> true  # Home page public
      true -> true  # Default public access
    end
  end

  @doc """
  Filters data based on user permissions.
  """
  def filter_data_for_user(data, user, data_type) do
    case {get_user_role(user), data_type} do
      {:admin, _} ->
        # Admin gets full access
        data
      
      {:researcher, :evaluation_results} ->
        # Researchers get results but no sensitive data
        filter_sensitive_fields(data, [:internal_logs, :system_details])
      
      {:public, :evaluation_results} ->
        # Public gets basic results only
        filter_sensitive_fields(data, [:internal_logs, :system_details, :admin_metadata])
      
      {_, :system_logs} ->
        # Only admin can see system logs
        if admin_user?(user), do: data, else: []
      
      {_, :system_health} ->
        # Only admin can see detailed health
        if admin_user?(user), do: data, else: basic_health_info(data)
      
      _ ->
        data
    end
  end

  # Private functions

  defp filter_sensitive_fields(data, fields_to_remove) when is_map(data) do
    Map.drop(data, fields_to_remove)
  end

  defp filter_sensitive_fields(data, fields_to_remove) when is_list(data) do
    Enum.map(data, fn item -> filter_sensitive_fields(item, fields_to_remove) end)
  end

  defp filter_sensitive_fields(data, _fields_to_remove), do: data

  defp basic_health_info(health_data) when is_map(health_data) do
    Map.take(health_data, [:status, :uptime, :last_updated])
  end

  defp basic_health_info(_health_data), do: %{status: :unknown}
end