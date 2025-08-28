# Pipeline Architecture Guide

This guide explains the core evaluation pipeline architecture that processes AI-generated code submissions through comprehensive analysis and scoring.

## Overview

The SWE-bench evaluation pipeline is built on **GenStage** for backpressure-aware processing, ensuring efficient resource utilization and reliable evaluation delivery at scale.

## Pipeline Flow

### High-Level Processing Flow

```mermaid
graph TD
    A[Task Instance] --> B[Task Producer]
    B --> C[Patch Fetcher]
    C --> D[Container Evaluator]
    D --> E[Analysis Parallelizer]
    E --> F[Result Analyzer]
    F --> G[Result Streamer]
    
    subgraph "Analysis Types"
        E1[Static Analysis]
        E2[Pattern Analysis] 
        E3[Functional Analysis]
        E4[OTP Validation]
        E5[Performance Analysis]
    end
    
    E --> E1
    E --> E2
    E --> E3
    E --> E4
    E --> E5
    
    style B fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px
    style D fill:#f59e0b,stroke:#d97706,stroke-width:2px
    style E fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

## Core Pipeline Components

### 1. Task Producer (`lib/swe_bench/pipeline/task_producer.ex`)

**Purpose**: Generates evaluation tasks from repository configurations

```mermaid
graph LR
    A[Repository Config] --> B[Task Extractor]
    B --> C[Validation Framework]
    C --> D[Task Instance]
    D --> E[Pipeline Queue]
    
    subgraph "Task Generation"
        B1[Issue Analysis]
        B2[Patch Extraction]
        B3[Test Validation]
    end
    
    B --> B1
    B --> B2
    B --> B3
```

**Key Features**:
- Automated task extraction from GitHub repositories
- Validation framework ensuring task quality
- Intelligent batching for optimal pipeline throughput
- Integration with repository expansion system

### 2. Container Evaluator (`lib/swe_bench/pipeline/container_evaluator.ex`)

**Purpose**: Manages isolated code execution in containerized environments

```mermaid
graph TD
    A[Evaluation Request] --> B[Container Pool]
    B --> C[Container Acquisition]
    C --> D[Environment Setup]
    D --> E[Code Execution]
    E --> F[Test Running]
    F --> G[Result Collection]
    G --> H[Container Release]
    
    subgraph "Container Pool Management"
        B1[Advanced Pool Manager]
        B2[Health Monitor]
        B3[Scaling Engine]
    end
    
    B --> B1
    B --> B2
    B --> B3
    
    style C fill:#10b981,stroke:#059669,stroke-width:2px
    style E fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

**Key Features**:
- Advanced container pool with intelligent scaling
- Health monitoring and automatic container replacement  
- Resource optimization with container reuse strategies
- Isolation guarantees for secure code execution

### 3. Analysis Parallelizer (`lib/swe_bench/pipeline/analysis_parallelizer.ex`)

**Purpose**: Coordinates parallel analysis across multiple dimensions

```mermaid
graph LR
    A[Evaluation Result] --> B[Analysis Coordinator]
    
    B --> C[Static Analysis]
    B --> D[Pattern Analysis]
    B --> E[Functional Analysis]
    B --> F[OTP Validation]
    B --> G[Performance Analysis]
    
    C --> H[Result Aggregator]
    D --> H
    E --> H
    F --> H
    G --> H
    
    H --> I[Combined Analysis Result]
    
    subgraph "Parallel Processing"
        C1[Credo Integration]
        D1[AST Parser]
        E1[Purity Checker]
        F1[Behavior Validation]
        G1[Benchee Integration]
    end
    
    C --> C1
    D --> D1
    E --> E1
    F --> F1
    G --> G1
```

**Analysis Types**:
- **Static Analysis**: Code quality, style, and complexity analysis
- **Pattern Analysis**: Elixir-specific pattern usage and idiomatic code
- **Functional Analysis**: Functional programming adherence and purity
- **OTP Validation**: Proper use of OTP behaviors and supervision
- **Performance Analysis**: Benchmarking and optimization opportunities

## Advanced Pipeline Features

### 1. Intelligent Caching (`lib/swe_bench/pipeline/intelligent_cache.ex`)

```mermaid
graph TB
    A[Cache Request] --> B{Cache Hit?}
    B -->|Yes| C[Return Cached Result]
    B -->|No| D[Process Request]
    D --> E[Store in Cache]
    E --> F[Return Result]
    
    subgraph "Cache Layers"
        G[Memory Cache]
        H[Distributed Cache]
        I[Persistent Cache]
    end
    
    C --> G
    E --> G
    G --> H
    H --> I
    
    style B fill:#fbbf24,stroke:#f59e0b,stroke-width:2px
```

**Features**:
- Multi-layer caching with memory, distributed, and persistent layers
- Intelligent invalidation based on repository and evaluation changes
- Performance optimization reducing duplicate evaluation overhead
- Integration with advanced pool management for cache warming

### 2. Adaptive Throttle (`lib/swe_bench/pipeline/adaptive_throttle.ex`)

```mermaid
graph LR
    A[System Load] --> B[Throttle Controller]
    B --> C[Concurrency Adjustment]
    C --> D[Resource Allocation]
    D --> E[Pipeline Flow Control]
    
    subgraph "Adaptation Triggers"
        F[CPU Usage]
        G[Memory Pressure]
        H[Queue Depth]
        I[Error Rate]
    end
    
    A --> F
    A --> G
    A --> H
    A --> I
    
    style B fill:#8b5cf6,stroke:#7c3aed,stroke-width:2px
```

**Adaptive Features**:
- Dynamic concurrency adjustment based on system load
- Resource-aware throttling with intelligent backpressure
- Queue depth management for optimal throughput
- Error rate monitoring with automatic scaling adjustments

### 3. Batch Optimizer (`lib/swe_bench/pipeline/batch_optimizer.ex`)

**Purpose**: Optimizes evaluation batching for maximum efficiency

- **Dynamic Batching**: Adjusts batch sizes based on repository complexity
- **Priority Scheduling**: Prioritizes evaluations based on user tier and urgency  
- **Resource Optimization**: Groups similar evaluations for efficient resource usage
- **Load Distribution**: Balances load across available container resources

## Configuration and Tuning

### Pipeline Configuration

Key configuration parameters for pipeline optimization:

```elixir
config :swe_bench, :pipeline,
  # GenStage configuration
  producer_concurrency: 5,
  consumer_concurrency: 10,
  
  # Container pool settings
  min_pool_size: 3,
  max_pool_size: 20,
  scaling_threshold: 0.8,
  
  # Performance tuning
  batch_size: 10,
  timeout_multiplier: 1.5,
  cache_enabled: true,
  
  # Advanced features
  adaptive_throttling: true,
  intelligent_batching: true,
  parallel_analysis: true
```

### Monitoring Integration

The pipeline is fully instrumented with telemetry events:

```mermaid
graph LR
    A[Pipeline Stages] --> B[Telemetry Events]
    B --> C[Metrics Collection]
    C --> D[Monitoring Dashboard]
    
    subgraph "Telemetry Events"
        E[task_producer.start/stop]
        F[container_evaluator.start/stop]
        G[analysis_parallelizer.start/stop]
        H[result_analyzer.start/stop]
    end
    
    B --> E
    B --> F
    B --> G
    B --> H
    
    style C fill:#10b981,stroke:#059669,stroke-width:2px
```

## Error Handling and Recovery

### Fault Tolerance

```mermaid
graph TD
    A[Pipeline Error] --> B{Error Type}
    B -->|Transient| C[Retry Logic]
    B -->|Resource| D[Adaptive Scaling]
    B -->|Critical| E[Circuit Breaker]
    
    C --> F[Exponential Backoff]
    F --> G[Retry Attempt]
    G --> H{Success?}
    H -->|Yes| I[Continue Processing]
    H -->|No| J[Dead Letter Queue]
    
    D --> K[Resource Reallocation]
    K --> L[Load Shedding]
    
    E --> M[Graceful Degradation]
    M --> N[Partial Results]
    
    style E fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

### Recovery Mechanisms
- **Automatic Retry**: Exponential backoff for transient failures
- **Circuit Breaker**: Protection against cascading failures
- **Graceful Degradation**: Partial results when full analysis fails
- **Dead Letter Queue**: Failed evaluation handling and investigation

## Performance Optimization

### Advanced Features

1. **Parallel Analysis**: Multiple analysis dimensions processed concurrently
2. **Container Reuse**: Efficient container lifecycle management
3. **Intelligent Caching**: Multi-layer caching with smart invalidation
4. **Adaptive Throttling**: Dynamic resource allocation based on system state
5. **Batch Optimization**: Efficient grouping of similar evaluations

### Scalability Patterns

- **Horizontal Scaling**: Additional worker nodes for increased throughput
- **Vertical Scaling**: Resource allocation optimization within nodes  
- **Geographic Distribution**: Multi-region deployment for global accessibility
- **Edge Computing**: Edge evaluation nodes for reduced latency

## Integration Points

### Phase 4 Advanced Capabilities

The pipeline integrates seamlessly with Phase 4 advanced capabilities:

- **Distributed Testing**: Multi-node evaluation coordination
- **Hot Code Reloading**: Zero-downtime pipeline updates
- **Performance Benchmarking**: Benchee integration for detailed analysis
- **Concurrent Evaluation**: Race condition and deadlock detection
- **Partial Credit Scoring**: Multi-dimensional evaluation scoring

### Phase 5 Production Features

Full integration with production infrastructure:

- **Real-Time Events**: Pipeline events streamed to web interface
- **Web Interface**: Progress monitoring and result visualization
- **Authentication**: Role-based access to evaluation submission
- **Monitoring**: Comprehensive observability and alerting integration

This pipeline architecture provides the foundation for scalable, reliable, and comprehensive evaluation of AI-generated Elixir code while maintaining excellent performance and operational characteristics.