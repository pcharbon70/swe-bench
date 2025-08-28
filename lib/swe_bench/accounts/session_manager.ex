defmodule SweBench.Accounts.SessionManager do
  @moduledoc """
  Comprehensive session management with analytics and monitoring.

  Handles secure session storage, timeout management, user tracking,
  and session analytics for enhanced security and monitoring.
  """

  use GenServer
  require Logger

  alias SweBench.Accounts.{Authorization, AuditLogger}

  defstruct [
    :config,
    :active_sessions,
    :session_analytics,
    :cleanup_timer
  ]

  @session_timeout_minutes 60
  @cleanup_interval_minutes 15

  @doc """
  Starts the session manager with the given configuration.
  """
  def start_link(config \\ []) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Creates a new user session.
  """
  def create_session(user, session_info \\ %{}) do
    GenServer.call(__MODULE__, {:create_session, user, session_info})
  end

  @doc """
  Validates and refreshes an existing session.
  """
  def validate_session(session_id) do
    GenServer.call(__MODULE__, {:validate_session, session_id})
  end

  @doc """
  Ends a user session.
  """
  def end_session(session_id) do
    GenServer.cast(__MODULE__, {:end_session, session_id})
  end

  @doc """
  Gets active session information for a user.
  """
  def get_user_sessions(user_id) do
    GenServer.call(__MODULE__, {:get_user_sessions, user_id})
  end

  @doc """
  Returns session analytics and statistics.
  """
  def get_session_analytics do
    GenServer.call(__MODULE__, :get_session_analytics)
  end

  @doc """
  Extends session timeout for active session.
  """
  def extend_session(session_id) do
    GenServer.cast(__MODULE__, {:extend_session, session_id})
  end

  @impl true
  def init(config) do
    session_config = build_session_config(config)
    
    state = %__MODULE__{
      config: session_config,
      active_sessions: %{},
      session_analytics: initialize_analytics(),
      cleanup_timer: schedule_cleanup()
    }

    Logger.info("Accounts.SessionManager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, user, session_info}, _from, state) do
    session_id = generate_session_id()
    
    session_data = %{
      session_id: session_id,
      user_id: user.id,
      user_role: Authorization.get_user_role(user),
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      expires_at: calculate_expiration(),
      ip_address: Map.get(session_info, :ip_address),
      user_agent: Map.get(session_info, :user_agent),
      login_method: Map.get(session_info, :login_method, :password),
      status: :active
    }
    
    # Store session
    new_sessions = Map.put(state.active_sessions, session_id, session_data)
    
    # Update analytics
    new_analytics = update_session_analytics(state.session_analytics, :session_created, session_data)
    
    # Log session creation
    AuditLogger.log_session_event(:session_created, user.id, %{
      session_id: session_id,
      ip_address: session_data.ip_address,
      login_method: session_data.login_method
    })

    new_state = %{state |
      active_sessions: new_sessions,
      session_analytics: new_analytics
    }

    {:reply, {:ok, session_id}, new_state}
  end

  @impl true
  def handle_call({:validate_session, session_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      
      session_data ->
        case validate_session_expiration(session_data) do
          {:ok, :valid} ->
            # Update last activity
            updated_session = Map.put(session_data, :last_activity, DateTime.utc_now())
            new_sessions = Map.put(state.active_sessions, session_id, updated_session)
            
            new_state = %{state | active_sessions: new_sessions}
            {:reply, {:ok, session_data}, new_state}
          
          {:error, :expired} ->
            # Remove expired session
            new_sessions = Map.delete(state.active_sessions, session_id)
            new_analytics = update_session_analytics(state.session_analytics, :session_expired, session_data)
            
            new_state = %{state |
              active_sessions: new_sessions,
              session_analytics: new_analytics
            }
            
            {:reply, {:error, :session_expired}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:get_user_sessions, user_id}, _from, state) do
    user_sessions = state.active_sessions
    |> Enum.filter(fn {_session_id, session_data} ->
        session_data.user_id == user_id
    end)
    |> Enum.map(fn {session_id, session_data} ->
        Map.put(session_data, :session_id, session_id)
    end)

    {:reply, user_sessions, state}
  end

  @impl true
  def handle_call(:get_session_analytics, _from, state) do
    {:reply, state.session_analytics, state}
  end

  @impl true
  def handle_cast({:end_session, session_id}, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:noreply, state}
      
      session_data ->
        # Log session end
        AuditLogger.log_session_event(:session_ended, session_data.user_id, %{
          session_id: session_id,
          duration_minutes: calculate_session_duration(session_data)
        })
        
        # Remove session
        new_sessions = Map.delete(state.active_sessions, session_id)
        new_analytics = update_session_analytics(state.session_analytics, :session_ended, session_data)
        
        new_state = %{state |
          active_sessions: new_sessions,
          session_analytics: new_analytics
        }
        
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:extend_session, session_id}, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:noreply, state}
      
      session_data ->
        updated_session = %{session_data |
          last_activity: DateTime.utc_now(),
          expires_at: calculate_expiration()
        }
        
        new_sessions = Map.put(state.active_sessions, session_id, updated_session)
        new_state = %{state | active_sessions: new_sessions}
        
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup_expired_sessions, state) do
    # Clean up expired sessions
    {active_sessions, expired_sessions} = partition_expired_sessions(state.active_sessions)
    
    # Log expired sessions
    Enum.each(expired_sessions, fn {session_id, session_data} ->
      AuditLogger.log_session_event(:session_expired, session_data.user_id, %{
        session_id: session_id,
        expired_at: DateTime.utc_now()
      })
    end)
    
    # Update analytics
    new_analytics = Enum.reduce(expired_sessions, state.session_analytics, fn {_id, session_data}, analytics ->
      update_session_analytics(analytics, :session_expired, session_data)
    end)
    
    # Schedule next cleanup
    cleanup_timer = schedule_cleanup()
    
    new_state = %{state |
      active_sessions: active_sessions,
      session_analytics: new_analytics,
      cleanup_timer: cleanup_timer
    }

    Logger.debug("Cleaned up #{length(expired_sessions)} expired sessions")
    {:noreply, new_state}
  end

  # Private functions

  defp build_session_config(config) do
    default_config()
    |> Map.merge(Enum.into(config, %{}))
  end

  defp default_config do
    %{
      session_timeout_minutes: @session_timeout_minutes,
      cleanup_interval_minutes: @cleanup_interval_minutes,
      max_sessions_per_user: 5,
      persistent_sessions: true,
      session_analytics_enabled: true
    }
  end

  defp initialize_analytics do
    %{
      total_sessions_created: 0,
      total_sessions_ended: 0,
      total_sessions_expired: 0,
      active_session_count: 0,
      average_session_duration_minutes: 0.0,
      login_methods: %{password: 0, oauth: 0, magic_link: 0},
      sessions_by_role: %{admin: 0, public: 0, researcher: 0},
      peak_concurrent_sessions: 0
    }
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp calculate_expiration do
    DateTime.add(DateTime.utc_now(), @session_timeout_minutes * 60, :second)
  end

  defp validate_session_expiration(session_data) do
    case DateTime.compare(DateTime.utc_now(), session_data.expires_at) do
      :lt -> {:ok, :valid}
      _ -> {:error, :expired}
    end
  end

  defp partition_expired_sessions(sessions) do
    now = DateTime.utc_now()
    
    sessions
    |> Enum.split_with(fn {_session_id, session_data} ->
        DateTime.compare(now, session_data.expires_at) == :lt
    end)
    |> then(fn {active, expired} ->
        {Enum.into(active, %{}), expired}
    end)
  end

  defp calculate_session_duration(session_data) do
    DateTime.diff(DateTime.utc_now(), session_data.created_at, :minute)
  end

  defp update_session_analytics(analytics, event_type, session_data) do
    case event_type do
      :session_created ->
        login_method = Map.get(session_data, :login_method, :password)
        user_role = Map.get(session_data, :user_role, :public)
        new_active_count = analytics.active_session_count + 1
        
        %{analytics |
          total_sessions_created: analytics.total_sessions_created + 1,
          active_session_count: new_active_count,
          peak_concurrent_sessions: max(analytics.peak_concurrent_sessions, new_active_count),
          login_methods: Map.update(analytics.login_methods, login_method, 1, &(&1 + 1)),
          sessions_by_role: Map.update(analytics.sessions_by_role, user_role, 1, &(&1 + 1))
        }
      
      :session_ended ->
        duration = calculate_session_duration(session_data)
        total_ended = analytics.total_sessions_ended + 1
        
        %{analytics |
          total_sessions_ended: total_ended,
          active_session_count: max(0, analytics.active_session_count - 1),
          average_session_duration_minutes: 
            (analytics.average_session_duration_minutes * (total_ended - 1) + duration) / total_ended
        }
      
      :session_expired ->
        %{analytics |
          total_sessions_expired: analytics.total_sessions_expired + 1,
          active_session_count: max(0, analytics.active_session_count - 1)
        }
      
      _ ->
        analytics
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_sessions, @cleanup_interval_minutes * 60 * 1000)
  end
end