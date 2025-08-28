# Web Interface Guide

This guide explains the Phoenix LiveView-based web interface that provides real-time access to evaluation results, model comparisons, and administrative capabilities.

## Architecture Overview

The web interface is built on **Phoenix LiveView** with **real-time event streaming**, providing a modern, responsive experience without traditional APIs.

## Interface Architecture

### System Components

```mermaid
graph TB
    subgraph "Public Interface"
        A[Dashboard LiveView]
        B[Results Table Component]
        C[Model Comparison Component] 
        D[Filter Panel Component]
    end
    
    subgraph "Admin Interface"
        E[Admin.EvaluationLive]
        F[Evaluation Form Component]
        G[Progress Tracker Component]
        H[Log Streamer Component]
    end
    
    subgraph "Real-Time Layer"
        I[Phoenix.PubSub]
        J[WebSocket Connections]
        K[Event Broadcasting]
    end
    
    subgraph "Authentication Layer"
        L[Ash Authentication]
        M[Role-Based Access]
        N[Session Management]
    end
    
    A --> I
    E --> I
    I --> J
    J --> K
    
    E --> L
    L --> M
    M --> N
    
    style A fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style E fill:#ef4444,stroke:#dc2626,stroke-width:2px
    style I fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

## Public Dashboard

### Dashboard LiveView (`lib/swe_bench_web/live/dashboard_live.ex`)

**Purpose**: Public access to evaluation results with advanced filtering

```mermaid
graph TD
    A[User Access] --> B[Dashboard Mount]
    B --> C[Subscribe to Events]
    C --> D[Load Initial Data]
    D --> E[Render Interface]
    
    E --> F[Results Table]
    E --> G[Model Comparison]
    E --> H[Filter Panel]
    
    subgraph "Real-Time Updates"
        I[PubSub Events]
        J[LiveView Updates]
        K[Component Refresh]
    end
    
    I --> J
    J --> K
    K --> F
    K --> G
    K --> H
    
    style E fill:#10b981,stroke:#059669,stroke-width:2px
```

**Key Features**:
- **No Authentication Required**: Public access to all results and visualizations
- **Real-Time Updates**: Live result updates as evaluations complete
- **Advanced Filtering**: Dual model+task filtering with preset combinations
- **Interactive Charts**: Dynamic visualizations with real-time data binding

### User Experience Flow

```mermaid
sequenceDiagram
    participant U as User
    participant D as Dashboard
    participant F as Filter Panel
    participant C as Chart Component
    participant E as Event Stream
    
    U->>D: Access /dashboard
    D->>U: Render dashboard
    
    U->>F: Select model filters
    F->>D: Update filters
    D->>C: Refresh charts
    C->>U: Updated visualizations
    
    E->>D: New evaluation result
    D->>C: Live update
    C->>U: Real-time chart refresh
```

## Advanced Filtering System

### Dual Model+Task Filtering

The filtering system enables precise analysis by combining model and task filters:

```mermaid
graph LR
    A[User Selection] --> B[Filter Panel]
    B --> C[Model Filter]
    B --> D[Task Filter]
    
    C --> E[Model Selection]
    D --> F[Task Categories]
    
    E --> G[Combined Filter]
    F --> G
    G --> H[Real-Time Update]
    H --> I[Chart Refresh]
    
    subgraph "Model Options"
        E1[GPT-4]
        E2[Claude-3.5-Sonnet]
        E3[Gemini-Pro]
    end
    
    subgraph "Task Categories"  
        F1[Repository Filter]
        F2[Complexity Filter]
        F3[Task Type Filter]
    end
    
    E --> E1
    E --> E2
    E --> E3
    
    F --> F1
    F --> F2
    F --> F3
    
    style G fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

### Filter Implementation

**Filter Panel Component** (`lib/swe_bench_web/components/dashboard/filter_panel.ex`):

```elixir
def handle_event("update_model_filter", %{"models" => selected_models}, socket) do
  # Update model filters and notify parent
  send(self(), {:filter_models, %{"models" => selected_models}})
  {:noreply, socket}
end

def handle_event("apply_preset", %{"preset" => preset_id}, socket) do
  # Apply filter preset
  preset = find_preset(preset_id)
  send_filter_updates(preset.models, preset.tasks)
  {:noreply, socket}
end
```

## Admin Interface

### Admin Evaluation Interface

**Purpose**: Secure evaluation submission and monitoring for administrators

```mermaid
graph TD
    A[Admin Login] --> B[Role Verification]
    B --> C[Admin Dashboard]
    C --> D[Evaluation Form]
    C --> E[Progress Tracker]
    C --> F[Log Streamer]
    
    subgraph "Evaluation Submission"
        D1[Model Selection]
        D2[Repository Selection] 
        D3[Advanced Options]
        D4[Form Validation]
    end
    
    D --> D1
    D --> D2
    D --> D3
    D --> D4
    
    subgraph "Real-Time Monitoring"
        E1[Progress Bars]
        E2[Status Indicators]
        E3[Cancellation Controls]
        E4[Duration Tracking]
    end
    
    E --> E1
    E --> E2
    E --> E3
    E --> E4
    
    style B fill:#ef4444,stroke:#dc2626,stroke-width:2px
    style C fill:#f59e0b,stroke:#d97706,stroke-width:2px
```

### Admin Components

#### 1. Evaluation Form (`lib/swe_bench_web/components/admin/evaluation_form.ex`)

**Features**:
- **Model Selection**: Comprehensive LLM model picker with provider categorization
- **Repository Selection**: Available repository selection from 17+ repositories
- **Advanced Options**: Phase 4 capability toggles (distributed, concurrent, performance)
- **Real-Time Validation**: Client-side validation with immediate feedback

#### 2. Progress Tracker (`lib/swe_bench_web/components/admin/progress_tracker.ex`)

**Features**:
- **Live Progress**: Animated progress bars with status indicators
- **Detailed Information**: Expandable evaluation details with stage tracking
- **Cancellation Control**: Admin ability to cancel running evaluations
- **Duration Tracking**: Real-time duration and completion estimates

#### 3. Log Streamer (`lib/swe_bench_web/components/admin/log_streamer.ex`)

**Features**:
- **Terminal Interface**: Professional terminal-style log display
- **Real-Time Filtering**: Dynamic log filtering by level and search terms
- **Auto-Scroll**: Optional automatic scrolling with manual override
- **Search Capability**: Live search through log messages and sources

## Real-Time Communication

### Phoenix.PubSub Integration

```mermaid
graph TD
    A[Evaluation Engine] --> B[Event Coordinator]
    B --> C[PubSub Broadcasting]
    
    C --> D[evaluations:progress]
    C --> E[evaluations:results]
    C --> F[system:health]
    C --> G[datasets:updates]
    
    D --> H[Admin Dashboard]
    E --> I[Public Dashboard]
    F --> H
    G --> I
    
    subgraph "WebSocket Connections"
        J[Admin WebSocket]
        K[Public WebSocket] 
    end
    
    H --> J
    I --> K
    
    style C fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

### Event Types

**Evaluation Events**:
- `evaluation_submitted`: New evaluation queued
- `progress_update`: Real-time progress information
- `test_executed`: Individual test completion
- `evaluation_completed`: Final results available

**System Events**:
- `system_health`: Health monitoring updates
- `maintenance_notice`: System maintenance notifications
- `dataset_updated`: New task instances or repository changes

### WebSocket Lifecycle

```mermaid
sequenceDiagram
    participant U as User
    participant L as LiveView
    participant P as PubSub
    participant E as Event Source
    
    U->>L: Connect to Dashboard
    L->>P: Subscribe to channels
    P->>L: Subscription confirmed
    
    E->>P: Broadcast event
    P->>L: Event delivery
    L->>U: Real-time update
    
    Note over L,P: Connection maintained
    
    alt Connection Lost
        L->>P: Automatic reconnection
        P->>L: Missed events replay
        L->>U: Seamless recovery
    end
```

## Authentication and Authorization

### Role-Based Access

```mermaid
graph LR
    A[User Request] --> B{Authentication}
    B -->|Authenticated| C{Role Check}
    B -->|Not Authenticated| D[Public Access]
    
    C -->|Admin| E[Full Access]
    C -->|Researcher| F[Limited Access]
    C -->|User| G[Read Access]
    
    D --> H[Results Viewing Only]
    E --> I[Evaluation Submission]
    E --> J[System Administration]
    F --> K[Analysis Tools]
    G --> L[Personal Dashboard]
    
    style E fill:#ef4444,stroke:#dc2626,stroke-width:2px
    style D fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
```

### Access Control Matrix

| Feature | Public | Researcher | Admin |
|---------|--------|------------|-------|
| View Results | ✅ | ✅ | ✅ |
| Filter/Charts | ✅ | ✅ | ✅ |
| Submit Evaluations | ❌ | ❌ | ✅ |
| View Logs | ❌ | ❌ | ✅ |
| User Management | ❌ | ❌ | ✅ |
| System Settings | ❌ | ❌ | ✅ |

## Component Development

### Creating New Components

**LiveView Component Template**:
```elixir
defmodule SweBenchWeb.Components.MyComponent do
  use SweBenchWeb, :live_component
  
  @impl true
  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> prepare_data()
    
    {:ok, socket}
  end
  
  @impl true  
  def handle_event("my_event", params, socket) do
    # Handle user interactions
    {:noreply, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <!-- Component template -->
    """
  end
end
```

### Real-Time Integration

**Adding PubSub Subscription**:
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(SweBench.PubSub, "my_channel")
  end
  
  {:ok, socket}
end

def handle_info({:my_event, data}, socket) do
  socket = update_component_data(socket, data)
  {:noreply, socket}
end
```

## Performance Considerations

### LiveView Optimization

- **Minimal DOM Updates**: Efficient LiveView rendering with targeted updates
- **Component Caching**: Smart component state caching for performance
- **Event Debouncing**: Debounced user inputs for optimal server interaction
- **Connection Pooling**: WebSocket connection optimization

### Monitoring Integration

The web interface is fully instrumented with telemetry:

```elixir
:telemetry.execute([:swe_bench_web, :dashboard, :view], %{
  user_count: 1,
  load_time: duration
}, %{
  user_role: :public,
  filters_applied: socket.assigns.filters
})
```

## Deployment Considerations

### Production Configuration

```elixir
config :swe_bench_web, SweBenchWeb.Endpoint,
  http: [port: 4000],
  url: [host: "swe-bench.example.com", port: 443, scheme: "https"],
  check_origin: ["https://swe-bench.example.com"],
  websocket: [
    timeout: 45_000,
    transport_log: false,
    compress: true
  ]
```

### CDN Integration

Static assets and chart data can be optimized with CDN:

- **Asset Pipeline**: Optimized CSS/JS bundling with Phoenix
- **Image Optimization**: Chart export caching for performance
- **Global Distribution**: Edge caching for worldwide access

This web interface architecture provides a modern, real-time, and scalable user experience while maintaining security and performance at enterprise scale.