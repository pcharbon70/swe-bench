# SWE-bench-Elixir: Architectural Overview

This guide provides a comprehensive overview of the SWE-bench-Elixir system architecture, designed to help developers understand how all components work together to provide automated evaluation of AI-generated code for the Elixir ecosystem.

## System Purpose

SWE-bench-Elixir is a comprehensive benchmarking platform that evaluates AI models' ability to generate correct, efficient, and idiomatic Elixir code. The system provides:

- **Automated evaluation** of AI-generated solutions against real-world Elixir tasks
- **Advanced analysis** including performance, concurrency, and architectural quality assessment
- **Real-time web interface** for researchers and administrators to monitor and analyze results
- **Comprehensive metrics** for AI model comparison and research insights

## High-Level Architecture

```mermaid
graph TB
    subgraph "Phase 1-3: Core Infrastructure"
        A[Container Management] --> B[Test Runner]
        B --> C[Repository Setup]
        C --> D[Pipeline Processing]
    end
    
    subgraph "Phase 4: Advanced Capabilities"
        E[Distributed Testing] --> F[Hot Code Reloading]
        F --> G[Performance Benchmarking]
        G --> H[Partial Credit Scoring]
        H --> I[Concurrent Evaluation]
        I --> J[Repository Expansion]
        J --> K[Integration Testing]
    end
    
    subgraph "Phase 5: Production Interface"
        L[Web Interface] --> M[Real-Time Events]
        M --> N[LiveView Components]
        N --> O[Authentication]
        O --> P[Monitoring]
        P --> Q[Integration Tests]
        Q --> R[Infrastructure]
    end
    
    D --> E
    K --> L
    R --> S[Production Ready System]
    
    style S fill:#4ade80,stroke:#16a34a,stroke-width:3px
```

## System Layers

### 1. **Core Infrastructure Layer (Phases 1-3)**

The foundation provides essential evaluation capabilities:

```mermaid
graph LR
    A[Repository Setup] --> B[Container Management]
    B --> C[Test Execution]
    C --> D[Result Analysis]
    D --> E[Quality Assessment]
    
    subgraph "Core Components"
        B1[Advanced Pool Manager]
        B2[Container Builder] 
        B3[Isolation System]
    end
    
    B --> B1
    B --> B2
    B --> B3
```

- **Container Management**: Isolated execution environments for safe code evaluation
- **Repository Setup**: Automated repository configuration and task extraction
- **Test Runner**: Comprehensive test execution with multiple frameworks
- **Pipeline Processing**: GenStage-based evaluation pipeline with intelligent caching

### 2. **Advanced Capabilities Layer (Phase 4)**

Sophisticated evaluation features for comprehensive analysis:

```mermaid
graph TD
    A[Distributed Testing] --> B[Multi-Node Clusters]
    C[Hot Code Reloading] --> D[Zero-Downtime Upgrades]
    E[Performance Benchmarking] --> F[Benchee Integration]
    G[Partial Credit Scoring] --> H[Multi-Dimensional Analysis]
    I[Concurrent Evaluation] --> J[Race Condition Detection]
    K[Repository Expansion] --> L[30+ Repository Support]
    
    B --> M[Advanced Analysis]
    D --> M
    F --> M
    H --> M
    J --> M
    L --> M
    
    style M fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

### 3. **Production Interface Layer (Phase 5)**

User-facing interfaces and production infrastructure:

```mermaid
graph TB
    subgraph "User Interface"
        A[Public Dashboard] --> B[Admin Interface]
        B --> C[Real-Time Updates]
    end
    
    subgraph "Backend Services"
        D[Event Streaming] --> E[Authentication]
        E --> F[Session Management]
        F --> G[Audit Logging]
    end
    
    subgraph "Operations"
        H[Monitoring] --> I[Alerting]
        I --> J[Distributed Tracing]
        J --> K[Structured Logging]
    end
    
    A --> D
    C --> D
    G --> H
    
    style A fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style B fill:#ef4444,stroke:#dc2626,stroke-width:2px
    style H fill:#10b981,stroke:#059669,stroke-width:2px
```

## Component Interaction Flow

### Evaluation Lifecycle

```mermaid
sequenceDiagram
    participant A as Admin User
    participant W as Web Interface
    participant E as Event Coordinator
    participant P as Evaluation Pipeline
    participant D as Database
    participant M as Monitoring
    
    A->>W: Submit Evaluation
    W->>E: Broadcast submission event
    W->>P: Queue evaluation
    P->>D: Store evaluation record
    P->>M: Record metrics
    
    loop Progress Updates
        P->>E: Progress events
        E->>W: Real-time updates
        W->>A: Live progress display
    end
    
    P->>E: Completion event
    E->>W: Final results
    W->>A: Results visualization
    P->>M: Final metrics
```

### Real-Time Data Flow

```mermaid
graph LR
    A[Evaluation Engine] --> B[Event Coordinator]
    B --> C[PubSub Channels]
    
    C --> D[Admin Dashboard]
    C --> E[Public Dashboard]
    C --> F[Monitoring System]
    
    subgraph "Event Channels"
        C1[evaluations:progress]
        C2[evaluations:results] 
        C3[system:health]
        C4[datasets:updates]
    end
    
    C --> C1
    C --> C2
    C --> C3
    C --> C4
    
    style B fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

## Technology Stack

### Backend Infrastructure
- **Language**: Elixir with OTP supervision trees
- **Web Framework**: Phoenix with LiveView for real-time interfaces
- **Database**: PostgreSQL with Ash Framework for data layer
- **Real-Time**: Phoenix.PubSub for event streaming
- **Authentication**: Ash Authentication with role-based access control

### Evaluation Infrastructure  
- **Containerization**: Docker for isolated evaluation environments
- **Orchestration**: Advanced container pool management with scaling
- **Testing**: ExUnit with custom test runners and analyzers
- **Analysis**: Custom static analysis with Credo and Dialyzer integration

### Production Infrastructure
- **Deployment**: Kubernetes with horizontal pod autoscaling
- **Load Balancing**: NGINX Ingress with SSL/TLS termination
- **Monitoring**: Prometheus/Grafana with custom metrics
- **Tracing**: OpenTelemetry with Jaeger for distributed tracing
- **CI/CD**: GitHub Actions with automated testing and deployment

## Key Design Principles

### 1. **Security First**
- **Role-based access control** with admin/public separation
- **Comprehensive audit logging** for security compliance
- **Session management** with timeout and security monitoring
- **Container isolation** for safe code execution

### 2. **Real-Time Everything**
- **Phoenix.PubSub** for instant updates across all interfaces
- **LiveView components** for responsive user experiences
- **WebSocket connections** for efficient bidirectional communication
- **Event sourcing** for complete audit trails and replay capabilities

### 3. **Scalability and Performance**
- **GenStage pipeline** for backpressure-aware evaluation processing
- **Container pooling** for efficient resource utilization
- **Intelligent caching** for evaluation result optimization
- **Horizontal scaling** with Kubernetes orchestration

### 4. **Comprehensive Analysis**
- **Multi-dimensional scoring** beyond simple pass/fail metrics
- **Advanced capabilities** including distributed, concurrent, and performance analysis
- **Repository diversity** with 30+ Elixir ecosystem repositories
- **Flexible filtering** for precise model and task analysis

## Data Flow Architecture

### Evaluation Processing Pipeline

```mermaid
graph TD
    A[Task Instance] --> B[Repository Setup]
    B --> C[Container Acquisition]
    C --> D[Code Execution]
    D --> E[Test Running]
    E --> F[Result Analysis]
    
    F --> G[Static Analysis]
    F --> H[Performance Analysis]
    F --> I[Concurrent Analysis]
    F --> J[Pattern Analysis]
    
    G --> K[Scoring Engine]
    H --> K
    I --> K
    J --> K
    
    K --> L[Result Storage]
    L --> M[Real-Time Broadcasting]
    M --> N[Web Interface Updates]
    
    style K fill:#f59e0b,stroke:#d97706,stroke-width:2px
```

### User Interface Architecture

```mermaid
graph TB
    subgraph "Public Access (No Auth)"
        A[Dashboard] --> B[Results List]
        A --> C[Interactive Charts]
        A --> D[Model Comparison]
        A --> E[Filter Interface]
    end
    
    subgraph "Admin Access (Auth Required)"
        F[Admin Dashboard] --> G[Evaluation Submission]
        F --> H[Progress Monitoring]
        F --> I[System Logs]
        F --> J[User Management]
    end
    
    subgraph "Real-Time Layer"
        K[Phoenix.PubSub] --> L[WebSocket Connections]
        L --> A
        L --> F
    end
    
    subgraph "Backend Services"
        M[Event Coordinator] --> K
        N[Session Manager] --> O[Auth System]
        P[Audit Logger] --> Q[Security Events]
    end
    
    G --> M
    O --> F
    Q --> M
    
    style A fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style F fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

## Repository and Model Support

### Supported Repositories (17+ Currently)

```mermaid
graph TD
    subgraph "Core Libraries (5)"
        A1[Phoenix] 
        A2[Ecto]
        A3[Jason]
        A4[Tesla]
        A5[Credo]
    end
    
    subgraph "Expanded Libraries (10)"
        B1[Phoenix LiveView]
        B2[Oban]
        B3[Broadway]
        B4[Benchee]
        B5[ExDoc]
        B6[Bamboo]
        B7[Guardian]
        B8[Absinthe]
        B9[Nx]
        B10[Membrane]
    end
    
    subgraph "Production Applications (2)"
        C1[Plausible Analytics]
        C2[Changelog.com]
    end
    
    A1 --> D[Evaluation Pipeline]
    B1 --> D
    C1 --> D
    
    style D fill:#10b981,stroke:#059669,stroke-width:2px
```

### Supported LLM Models

- **OpenAI**: GPT-4, GPT-3.5-Turbo
- **Anthropic**: Claude-3.5-Sonnet, Claude-3-Haiku  
- **Google**: Gemini-Pro, Gemini-1.5-Flash
- **Extensible**: Framework supports additional model providers

## Performance Characteristics

### System Metrics
- **Throughput**: 100+ evaluations per hour
- **Response Time**: <500ms P95 for web interface
- **Concurrent Users**: 1000+ simultaneous connections
- **System Availability**: 99.9% uptime SLA target

### Resource Utilization
- **Memory**: <32GB peak usage with intelligent allocation
- **CPU**: <80% sustained usage with container optimization
- **Storage**: Efficient dataset management with compression
- **Network**: Optimized WebSocket communication with compression

## Security Model

### Access Control

```mermaid
graph LR
    A[Public Users] --> B[Read-Only Access]
    B --> C[Results Dashboard]
    B --> D[Model Comparisons]
    B --> E[Chart Visualizations]
    
    F[Admin Users] --> G[Full Access]
    G --> H[Evaluation Submission]
    G --> I[System Monitoring]
    G --> J[User Management]
    G --> K[Audit Logs]
    
    L[Researcher Users] --> M[Limited Access]
    M --> N[Result Analysis]
    M --> O[Limited Quotas]
    
    style A fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style F fill:#ef4444,stroke:#dc2626,stroke-width:2px
    style L fill:#f59e0b,stroke:#d97706,stroke-width:2px
```

### Security Features
- **Authentication**: Multi-method auth with OAuth2 and password-based
- **Authorization**: Role-based access with fine-grained permissions
- **Session Management**: Secure sessions with analytics and timeout handling
- **Audit Logging**: Comprehensive audit trails for compliance and security

## Deployment Architecture

### Production Infrastructure

```mermaid
graph TB
    subgraph "Load Balancer"
        A[NGINX Ingress]
        A --> B[SSL/TLS Termination]
        B --> C[Request Routing]
    end
    
    subgraph "Application Layer"
        D[Phoenix Application Pods]
        E[LiveView Services]
        F[Background Workers]
    end
    
    subgraph "Data Layer"
        G[PostgreSQL Primary]
        H[PostgreSQL Replica]
        I[Redis Cache]
    end
    
    subgraph "Infrastructure Services"
        J[Monitoring Stack]
        K[Log Aggregation]
        L[Backup Systems]
    end
    
    C --> D
    C --> E
    D --> G
    E --> G
    F --> G
    G --> H
    
    D --> I
    E --> I
    
    D --> J
    E --> J
    F --> J
    
    style A fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
    style G fill:#10b981,stroke:#059669,stroke-width:2px
```

## Development Workflow

### Code Organization

The codebase is organized into clear functional domains:

- **`lib/swe_bench/`**: Core evaluation engine and business logic
- **`lib/swe_bench_web/`**: Web interface with LiveView components
- **`test/`**: Comprehensive test suites including integration tests
- **`guides/`**: Developer documentation and architectural guides

### Key Patterns

1. **GenServer Architecture**: All major components use GenServer for state management
2. **Supervision Trees**: Proper OTP supervision for fault tolerance
3. **Phoenix LiveView**: Real-time web interfaces without traditional APIs
4. **Event Sourcing**: Comprehensive event streaming for audit and replay
5. **Container Isolation**: Safe code execution in isolated environments

## Getting Started

### For New Developers

1. **Read the Guides**: Start with individual component guides in this directory
2. **Understand the Pipeline**: Review `pipeline-architecture.md` for evaluation flow
3. **Explore Components**: Check component-specific guides for detailed implementation
4. **Run Tests**: Execute the comprehensive test suite for validation
5. **Check Integration**: Review Phase 5 integration tests for system understanding

### For Contributors

1. **Follow Patterns**: Maintain existing architectural patterns and conventions
2. **Add Tests**: Comprehensive test coverage is required for all changes
3. **Update Guides**: Update relevant guides when adding new features
4. **Check Quality**: All code must pass strict Credo analysis
5. **Integration Testing**: Ensure changes work with existing integration tests

## Next Steps

Continue reading the detailed component guides:

- **[Pipeline Architecture](./pipeline-architecture.md)**: Evaluation pipeline and processing
- **[Container Management](./container-management.md)**: Isolation and execution environments
- **[Web Interface](./web-interface.md)**: LiveView components and real-time features
- **[Authentication System](./authentication-system.md)**: Security and access control
- **[Monitoring Infrastructure](./monitoring-infrastructure.md)**: Observability and alerting
- **[Real-Time Events](./real-time-events.md)**: Event streaming and PubSub architecture

This architecture enables comprehensive, secure, and scalable evaluation of AI-generated Elixir code with modern web interfaces and enterprise-grade operational capabilities.