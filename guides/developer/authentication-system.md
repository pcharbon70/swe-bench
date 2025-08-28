# Authentication System Guide

This guide explains the comprehensive authentication and authorization system that provides secure access control with admin/public separation and enterprise-grade security features.

## Security Architecture

### Multi-Tier Access Control

```mermaid
graph TB
    A[User Request] --> B[Authentication Gateway]
    B --> C{User Type}
    
    C -->|Public| D[Public Access]
    C -->|Researcher| E[Limited Access]
    C -->|Admin| F[Full Access]
    
    subgraph "Public Capabilities"
        D1[View Results]
        D2[Filter/Charts] 
        D3[Model Comparisons]
    end
    
    subgraph "Researcher Capabilities"
        E1[Analysis Tools]
        E2[Export Data]
        E3[Limited Quotas]
    end
    
    subgraph "Admin Capabilities"  
        F1[Submit Evaluations]
        F2[System Monitoring]
        F3[User Management]
        F4[Audit Logs]
    end
    
    D --> D1
    D --> D2  
    D --> D3
    
    E --> E1
    E --> E2
    E --> E3
    
    F --> F1
    F --> F2
    F --> F3
    F --> F4
    
    style D fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style E fill:#f59e0b,stroke:#d97706,stroke-width:2px
    style F fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

## Core Components

### 1. Authorization Framework (`lib/swe_bench/accounts/authorization.ex`)

**Purpose**: Role-based permission system with clear capability definitions

```mermaid
graph LR
    A[User] --> B[Role Determination]
    B --> C[Permission Check]
    C --> D{Authorized?}
    
    D -->|Yes| E[Grant Access]
    D -->|No| F[Deny Access]
    
    subgraph "Role Definitions"
        G[Admin: Unlimited]
        H[Researcher: 10/month]
        I[Public: Read-only]
    end
    
    B --> G
    B --> H
    B --> I
    
    F --> J[Audit Log]
    E --> K[Action Tracking]
    
    style D fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

**Permission Matrix**:
```elixir
@user_roles %{
  admin: %{
    can_submit_evaluations: true,
    can_view_system_logs: true,
    can_access_admin_interface: true,
    evaluation_quota: :unlimited
  },
  researcher: %{
    can_submit_evaluations: false,
    evaluation_quota: 10  # 10 evaluations per month
  },
  public: %{
    can_submit_evaluations: false,
    evaluation_quota: 0   # Read-only access
  }
}
```

### 2. Session Manager (`lib/swe_bench/accounts/session_manager.ex`)

**Purpose**: Secure session management with analytics and monitoring

```mermaid
graph TD
    A[User Login] --> B[Session Creation]
    B --> C[Session Storage]
    C --> D[Activity Tracking]
    
    D --> E[Session Validation]
    E --> F{Valid?}
    F -->|Yes| G[Extend Session]
    F -->|No| H[Session Cleanup]
    
    G --> I[Analytics Update]
    H --> J[Audit Event]
    
    subgraph "Session Data"
        K[Session ID]
        L[User Info]
        M[Creation Time]
        N[Last Activity]
        O[Expiration]
    end
    
    C --> K
    C --> L
    C --> M
    C --> N
    C --> O
    
    style B fill:#10b981,stroke:#059669,stroke-width:2px
```

**Session Features**:
- **Secure IDs**: Cryptographically secure session identifiers
- **Analytics**: Session duration, login methods, and activity patterns
- **Automatic Cleanup**: Expired session cleanup with configurable retention
- **Multi-Session**: Support for multiple concurrent sessions per user

### 3. Audit Logger (`lib/swe_bench/accounts/audit_logger.ex`)

**Purpose**: Comprehensive audit trail for security compliance

```mermaid
graph LR
    A[Security Event] --> B[Event Classification]
    B --> C[Severity Assignment]
    C --> D[Audit Storage]
    D --> E[Real-Time Broadcasting]
    
    subgraph "Event Categories"
        F[Authentication]
        G[Authorization]
        H[Admin Actions]
        I[Security Events]
    end
    
    B --> F
    B --> G
    B --> H
    B --> I
    
    subgraph "Severity Levels"
        J[High: Failed Login]
        K[Medium: Role Change]
        L[Low: Session Created]
        M[Info: User Action]
    end
    
    C --> J
    C --> K
    C --> L
    C --> M
    
    style D fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
    style E fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

### 4. Usage Limiter (`lib/swe_bench/accounts/usage_limiter.ex`)

**Purpose**: Fair resource allocation through tier-based quotas

```mermaid
graph TD
    A[Evaluation Request] --> B[User Identification]
    B --> C[Quota Check]
    C --> D{Within Limits?}
    
    D -->|Yes| E[Allow Evaluation]
    D -->|No| F[Deny Request]
    
    E --> G[Record Usage]
    F --> H[Quota Exceeded Event]
    
    G --> I[Update Sliding Windows]
    I --> J[Analytics Update]
    
    subgraph "Quota Types"
        K[Hourly Limits]
        L[Daily Limits]
        M[Monthly Limits]
        N[Concurrent Limits]
    end
    
    C --> K
    C --> L
    C --> M
    C --> N
    
    style D fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

## Authentication Flow

### User Authentication Process

```mermaid
sequenceDiagram
    participant U as User
    participant W as Web Interface
    participant A as Auth System
    participant S as Session Manager
    participant L as Audit Logger
    
    U->>W: Login Request
    W->>A: Validate Credentials
    A->>S: Create Session
    S->>L: Log Session Event
    L->>W: Authentication Success
    W->>U: Redirect to Dashboard
    
    loop Session Validation
        U->>W: Page Request
        W->>S: Validate Session
        S->>W: Session Status
        alt Valid Session
            W->>U: Serve Content
        else Invalid Session
            W->>U: Redirect to Login
        end
    end
```

### Role Assignment and Verification

```elixir
# Role determination
def get_user_role(user) do
  case user do
    %{role: role} when is_atom(role) -> role
    %{"role" => role} when is_binary(role) -> String.to_existing_atom(role)
    nil -> :public
    _ -> :public
  end
end

# Permission checking
def authorized?(user, action) do
  role = get_user_role(user)
  permissions = get_role_permissions(role)
  Map.get(permissions, action, false)
end
```

## Security Features

### Session Security

**Session Data Structure**:
```elixir
%{
  session_id: "crypto_secure_id",
  user_id: user.id,
  user_role: :admin,
  created_at: DateTime.utc_now(),
  expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
  ip_address: "192.168.1.100", 
  user_agent: "Browser/Version",
  login_method: :oauth,
  status: :active
}
```

### Audit Event Structure

**Audit Entry Format**:
```elixir
%{
  id: "unique_audit_id",
  category: :authentication,
  event_type: :user_login,
  user_id: user.id,
  severity: :low,
  timestamp: DateTime.utc_now(),
  ip_address: "192.168.1.100",
  metadata: %{session_id: "session_id", login_method: :oauth}
}
```

## Usage Limiting

### Quota Management

```mermaid
graph LR
    A[User Action] --> B[Usage Tracker]
    B --> C[Sliding Windows]
    C --> D[Quota Calculation]
    D --> E{Within Limits?}
    
    E -->|Yes| F[Allow Action]
    E -->|No| G[Block Action]
    
    F --> H[Update Counters]
    G --> I[Quota Event]
    
    subgraph "Time Windows"
        J[Hourly: 2 evals]
        K[Daily: 10 evals]
        L[Monthly: 50 evals]
        M[Concurrent: 1 eval]
    end
    
    C --> J
    C --> K
    C --> L
    C --> M
    
    style E fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

### Tier-Based Limits

**Usage Tiers**:
```elixir
@usage_tiers %{
  public: %{
    evaluations_per_hour: 0,
    evaluations_per_month: 0,
    concurrent_evaluations: 0
  },
  researcher: %{
    evaluations_per_hour: 2,
    evaluations_per_day: 10, 
    evaluations_per_month: 50,
    concurrent_evaluations: 1
  },
  admin: %{
    evaluations_per_hour: :unlimited,
    evaluations_per_day: :unlimited,
    evaluations_per_month: :unlimited,
    concurrent_evaluations: :unlimited
  }
}
```

## Integration with Web Interface

### LiveView Authentication

```elixir
# In LiveView modules
on_mount {SweBenchWeb.LiveUserAuth, :live_user_required}  # Admin routes
on_mount {SweBenchWeb.LiveUserAuth, :live_user_optional}  # Public routes

# Role-based rendering
def render(assigns) do
  ~H"""
  <%= if @current_user && @current_user.role == :admin do %>
    <.admin_interface />
  <% else %>
    <.public_interface />
  <% end %>
  """
end
```

### Component Authorization

```elixir
def update(assigns, socket) do
  # Check user permissions for component features
  user = assigns[:current_user]
  
  socket = 
    socket
    |> assign(assigns)
    |> assign(:can_submit, Authorization.can_submit_evaluation?(user))
    |> assign(:can_view_logs, Authorization.can_view_logs?(user))
  
  {:ok, socket}
end
```

## Configuration

### Authentication Configuration

```elixir
config :swe_bench, :authentication,
  session_timeout_minutes: 60,
  max_sessions_per_user: 5,
  audit_logging_enabled: true,
  usage_limiting_enabled: true,
  
  # OAuth providers
  github_client_id: "github_client_id",
  google_client_id: "google_client_id"
```

### Security Settings

```elixir
config :swe_bench, :security,
  password_min_length: 12,
  session_security: :high,
  audit_retention_days: 365,
  failed_login_lockout: true,
  ip_whitelist_enabled: false
```

This authentication system provides enterprise-grade security while maintaining user-friendly access patterns and comprehensive audit capabilities for compliance and monitoring.