# Container Management Guide

This guide explains the sophisticated container management system that provides secure, isolated execution environments for AI-generated code evaluation.

## Overview

The container management system ensures **safe execution** of untrusted AI-generated code while maintaining **high performance** and **resource efficiency** through advanced pooling and scaling strategies.

## Architecture

### Container Lifecycle

```mermaid
graph TD
    A[Container Request] --> B[Pool Manager]
    B --> C{Available Container?}
    C -->|Yes| D[Acquire Existing]
    C -->|No| E[Create New Container]
    
    D --> F[Environment Setup]
    E --> F
    F --> G[Code Execution]
    G --> H[Result Collection]
    H --> I[Container Cleanup]
    I --> J[Return to Pool]
    
    subgraph "Container Pool"
        K[Active Containers]
        L[Warm Containers]
        M[Cool Containers]
    end
    
    J --> K
    K --> L
    L --> M
    M -->|Timeout| N[Container Termination]
    
    style B fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style G fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

## Core Components

### 1. Advanced Pool Manager (`lib/swe_bench/container/advanced_pool/pool_manager.ex`)

**Purpose**: Intelligent container pool management with predictive scaling

```mermaid
graph LR
    A[Pool Manager] --> B[Container Allocation]
    A --> C[Health Monitoring]
    A --> D[Scaling Decisions]
    
    B --> E[Resource Optimization]
    C --> F[Performance Metrics]
    D --> G[Capacity Planning]
    
    subgraph "Scaling Strategies"
        H[Predictive Scaling]
        I[Reactive Scaling]  
        J[Scheduled Scaling]
    end
    
    D --> H
    D --> I
    D --> J
    
    style A fill:#10b981,stroke:#059669,stroke-width:2px
```

**Key Features**:
- **Predictive Scaling**: ML-based container demand forecasting
- **Health Monitoring**: Continuous container health assessment
- **Resource Optimization**: Efficient memory and CPU allocation
- **Performance Metrics**: Detailed container performance analytics

**Configuration Example**:
```elixir
config :swe_bench, :advanced_pool,
  min_pool_size: 5,
  max_pool_size: 50,
  target_utilization: 0.8,
  scaling_factor: 1.5,
  health_check_interval: 30_000,
  container_timeout: 300_000
```

### 2. Scaling Engine (`lib/swe_bench/container/advanced_pool/scaling_engine.ex`)

**Purpose**: Automated scaling decisions based on demand and performance

```mermaid
graph TD
    A[Demand Metrics] --> B[Scaling Engine]
    B --> C{Scale Up?}
    B --> D{Scale Down?}
    
    C -->|Yes| E[Create Containers]
    D -->|Yes| F[Remove Containers]
    
    E --> G[Health Validation]
    F --> H[Graceful Shutdown]
    
    subgraph "Scaling Triggers"
        I[Queue Depth > Threshold]
        J[Utilization > 80%]
        K[Response Time > SLA]
        L[Error Rate Increase]
    end
    
    A --> I
    A --> J
    A --> K
    A --> L
    
    style B fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

**Scaling Algorithms**:
- **Reactive Scaling**: Based on current queue depth and utilization
- **Predictive Scaling**: ML models predicting future demand
- **Time-based Scaling**: Scheduled scaling for known traffic patterns
- **Error-driven Scaling**: Scaling adjustments based on failure rates

### 3. Health Monitor (`lib/swe_bench/container/advanced_pool/health_monitor.ex`)

**Purpose**: Continuous container health assessment and maintenance

```mermaid
graph LR
    A[Container] --> B[Health Checks]
    B --> C[Resource Monitoring]
    C --> D[Performance Analysis]
    D --> E[Health Score]
    
    E --> F{Healthy?}
    F -->|Yes| G[Continue Operation]
    F -->|No| H[Container Replacement]
    
    subgraph "Health Metrics"
        I[CPU Usage]
        J[Memory Usage]
        K[Response Time]
        L[Error Rate]
    end
    
    C --> I
    C --> J
    C --> K
    C --> L
    
    style E fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

## Container Security

### Isolation Strategy

```mermaid
graph TB
    subgraph "Host System"
        A[Host Kernel]
        B[Container Runtime]
    end
    
    subgraph "Container Isolation"
        C[Process Namespace]
        D[Network Namespace] 
        E[Filesystem Namespace]
        F[User Namespace]
    end
    
    subgraph "Security Layers"
        G[AppArmor/SELinux]
        H[Resource Limits]
        I[Network Policies]
        J[File Access Control]
    end
    
    B --> C
    B --> D
    B --> E
    B --> F
    
    C --> G
    D --> I
    E --> J
    F --> H
    
    style G fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

### Security Features

1. **Process Isolation**: Complete process namespace separation
2. **Network Isolation**: Controlled network access with policies
3. **Filesystem Protection**: Read-only base filesystem with controlled writes
4. **Resource Limits**: CPU, memory, and I/O limits preventing resource exhaustion
5. **User Namespace**: Non-root execution with privilege dropping

## Container Types

### Repository-Specific Containers

Different repositories require specialized container configurations:

```mermaid
graph TD
    A[Repository Type] --> B{Container Spec}
    
    B -->|Standard| C[Basic Elixir Container]
    B -->|Database| D[PostgreSQL + Elixir]
    B -->|LiveView| E[Node.js + Elixir + Browser]
    B -->|Production| F[Complex Dependencies]
    
    subgraph "Standard Container"
        C1[Elixir Runtime]
        C2[Basic Dependencies]
        C3[Test Framework]
    end
    
    subgraph "Production Container"
        F1[Elixir Runtime]
        F2[ClickHouse Database]
        F3[Media Processing]
        F4[Complex Test Suite]
    end
    
    C --> C1
    C --> C2
    C --> C3
    
    F --> F1
    F --> F2
    F --> F3
    F --> F4
    
    style C fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style F fill:#f59e0b,stroke:#d97706,stroke-width:2px
```

### Container Specifications

**Standard Repository Container**:
```yaml
image: elixir:1.15-alpine
memory: 2GB
cpu: 1 core
timeout: 5 minutes
dependencies: [postgresql-client, git]
```

**Production Application Container**:
```yaml
image: elixir:1.15-alpine
memory: 8GB
cpu: 4 cores  
timeout: 15 minutes
dependencies: [clickhouse-client, ffmpeg, imagemagick]
services: [postgresql, redis, clickhouse]
```

## Performance Optimization

### Container Reuse Strategy

```mermaid
graph LR
    A[Container Lifecycle] --> B[Creation Cost]
    B --> C[Warm Pool Strategy]
    C --> D[Reuse Optimization]
    
    subgraph "Optimization Techniques"
        E[Image Caching]
        F[Layer Optimization]
        G[Dependency Preloading]
        H[State Preservation]
    end
    
    C --> E
    C --> F
    C --> G
    C --> H
    
    style C fill:#10b981,stroke:#059669,stroke-width:2px
```

**Optimization Strategies**:
- **Image Caching**: Pre-built images with common dependencies
- **Layer Optimization**: Efficient Docker layer structure
- **Warm Pools**: Pre-warmed containers for immediate availability
- **State Preservation**: Maintaining container state between evaluations

### Resource Efficiency

```mermaid
graph TB
    A[Resource Request] --> B[Resource Allocator]
    B --> C[CPU Allocation]
    B --> D[Memory Allocation]
    B --> E[Storage Allocation]
    
    C --> F[CPU Shares]
    D --> G[Memory Limits]
    E --> H[Disk Quotas]
    
    F --> I[Performance Monitoring]
    G --> I
    H --> I
    
    I --> J{Optimization Needed?}
    J -->|Yes| K[Resource Reallocation]
    J -->|No| L[Continue Operation]
    
    K --> B
    
    style B fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

## Integration with Evaluation Pipeline

### Pipeline Integration

```mermaid
sequenceDiagram
    participant P as Pipeline
    participant PM as Pool Manager
    participant C as Container
    participant HM as Health Monitor
    participant SM as Scaling Engine
    
    P->>PM: Request Container
    PM->>C: Acquire/Create Container
    C->>PM: Container Ready
    PM->>P: Return Container Handle
    
    P->>C: Execute Evaluation
    C->>P: Return Results
    
    P->>PM: Release Container
    PM->>HM: Health Check
    HM->>PM: Health Status
    
    alt Unhealthy Container
        PM->>C: Terminate Container
        PM->>SM: Update Capacity
        SM->>PM: Scaling Decision
    else Healthy Container
        PM->>C: Return to Pool
    end
```

### Performance Metrics

The container system provides detailed metrics for optimization:

- **Container Utilization**: CPU, memory, and I/O usage per container
- **Pool Efficiency**: Container reuse rates and warming effectiveness
- **Scaling Performance**: Scaling decision accuracy and timing
- **Resource Optimization**: Cost per evaluation and efficiency metrics

## Configuration Examples

### Development Configuration
```elixir
config :swe_bench, :container,
  pool_manager: SweBench.Container.AdvancedPool.PoolManager,
  min_pool_size: 2,
  max_pool_size: 5,
  container_timeout: 60_000,
  health_check_interval: 30_000
```

### Production Configuration
```elixir
config :swe_bench, :container,
  pool_manager: SweBench.Container.AdvancedPool.PoolManager,
  min_pool_size: 10,
  max_pool_size: 100,
  container_timeout: 300_000,
  health_check_interval: 15_000,
  scaling_enabled: true,
  predictive_scaling: true,
  monitoring_enabled: true
```

## Troubleshooting

### Common Issues

1. **Container Startup Delays**
   - **Cause**: Image pulling or dependency installation
   - **Solution**: Pre-built images with cached dependencies

2. **Resource Exhaustion**
   - **Cause**: Insufficient container pool size
   - **Solution**: Adaptive scaling configuration adjustment

3. **Memory Leaks**
   - **Cause**: Container state not properly cleaned
   - **Solution**: Enhanced container lifecycle management

### Debugging Tools

- **Container Logs**: Detailed logging for container lifecycle events
- **Health Metrics**: Real-time container health and performance data
- **Pool Statistics**: Container pool utilization and efficiency metrics
- **Scaling Analytics**: Scaling decision history and effectiveness

## Advanced Features

### Container Warming

Pre-warming containers for immediate availability:

```elixir
# Warm containers for expected load
SweBench.Container.AdvancedPool.PoolManager.warm_pool([
  {repository: "phoenix", count: 5},
  {repository: "ecto", count: 3},
  {repository: "plausible_analytics", count: 2}
])
```

### Custom Container Configurations

Repository-specific container customization:

```elixir
defmodule MyApp.CustomContainerConfig do
  use SweBench.Container.Config
  
  def container_spec("my_repository") do
    %{
      image: "custom/elixir-extended:latest",
      memory: "4GB",
      cpu: "2",
      environment: %{
        "CUSTOM_VAR" => "value"
      },
      volumes: [
        "custom-data:/data"
      ]
    }
  end
end
```

This container management system provides the foundation for secure, scalable, and efficient evaluation of AI-generated code while maintaining excellent performance characteristics and operational reliability.