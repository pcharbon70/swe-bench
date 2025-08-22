# GenStage Pipeline Architecture Planning

**Planning Date:** 2025-08-22  
**Feature:** Phase 1.6 - GenStage Pipeline Architecture  
**Context:** SWE-bench-Elixir evaluation system  
**Current Branch:** feature/phase-1.6-genstage-pipeline  

## Problem Statement

The current SWE-bench-Elixir system processes task evaluations sequentially, achieving approximately 10 tasks/hour baseline throughput. This sequential architecture presents several critical limitations:

### Throughput Limitations
- **Sequential bottleneck**: Each task waits for the previous one to complete fully before starting
- **Container underutilization**: Pre-warmed containers sit idle while tasks wait in queue
- **Resource waste**: CPU and memory resources are underutilized during single-threaded execution
- **Scaling constraints**: Cannot leverage multi-core systems effectively

### Latency Issues
- **Cold start delays**: Each evaluation includes container startup time even with pooling
- **Synchronous dependencies**: GitHub API calls, LLM patch fetching, and container execution block each other
- **Database bottlenecks**: Result analysis and storage creates pipeline stalls

### Reliability Concerns
- **Single point of failure**: One failing task can block the entire evaluation queue
- **No fault isolation**: Container failures affect subsequent task execution
- **Limited error recovery**: No automatic retry or circuit breaker mechanisms

### Scalability Impact Analysis
- **Current state**: 10 tasks/hour baseline (insufficient for large-scale evaluation)
- **Target requirement**: 300+ tasks/hour with reliable error recovery
- **Resource efficiency**: Need to achieve 10-20x throughput improvement
- **Cost optimization**: Maximize container pool utilization and minimize idle time

## Solution Overview

Implement a GenStage-based pipeline architecture that transforms the sequential evaluation process into a high-throughput, fault-tolerant system. The solution employs four specialized stages with backpressure control and sophisticated supervision.

### GenStage Architecture Design

#### Pipeline Flow Design
```
Task Producer → Patch Fetcher → Container Evaluator → Result Analyzer
    (DB)           (LLM API)      (Container Pool)      (Analysis & DB)
     |                 |               |                    |
[Demand-based]  [Rate-limited]  [Pool-integrated]    [Parallel processing]
[Task batching] [Retry logic]   [Health monitoring]   [Streaming results]
```

#### Stage Design Decisions

**1. TaskProducer (GenStage Producer)**
- **Purpose**: Demand-driven task fetching from database with intelligent batching
- **Concurrency**: Single producer with configurable buffer (default: 50 tasks)
- **Optimization**: Repository-based batching for container cache efficiency
- **Features**: Priority queuing, failure retry scheduling, demand backpressure

**2. PatchFetcher (ProducerConsumer)**
- **Purpose**: LLM API integration for patch generation with rate limiting
- **Concurrency**: 3-5 parallel fetchers (respecting API limits)
- **Optimization**: Response caching, exponential backoff, request batching
- **Features**: Circuit breaker for API failures, cache-first fetching

**3. ContainerEvaluator (ConsumerProducer)**
- **Purpose**: Test execution in pooled containers with health monitoring
- **Concurrency**: 8-12 parallel evaluators (based on container pool size)
- **Integration**: Deep integration with existing Container.Pool system
- **Features**: Container health checks, timeout handling, resource monitoring

**4. ResultAnalyzer (Consumer)**
- **Purpose**: Parallel result analysis with database streaming
- **Concurrency**: 4-6 parallel analyzers for CPU-intensive analysis
- **Optimization**: Streaming database writes, concurrent analysis
- **Features**: Real-time progress notifications, analysis caching

### Agent Consultations Performed

#### Research Agent Consultation
**Focus Areas Researched:**
1. **GenStage Producer-Consumer Patterns**: Demand-driven architecture with backpressure
2. **Backpressure Management**: Memory and CPU constraint handling in BEAM VM
3. **Pipeline Supervision**: Fault tolerance with one_for_one and rest_for_one strategies
4. **Batch Optimization**: Container-based workload grouping for cache efficiency
5. **Adaptive Concurrency**: Flow balancing across heterogeneous stages

**Key Insights:**
- GenStage's demand-driven model naturally provides backpressure control
- ProducerConsumer stages are ideal for transformation with rate limiting
- Batch sizing should be adaptive based on downstream capacity
- Supervision trees require careful restart strategy selection

#### Elixir Expert Consultation
**OTP Architecture Guidance:**
1. **GenStage Integration**: Database integration patterns with Ecto for task fetching
2. **Supervision Tree Design**: Multi-layer supervision with stage restart isolation
3. **BEAM VM Optimization**: Process scheduling and memory management for 300+ concurrent processes
4. **Buffer Sizing**: Optimal buffer sizes based on stage processing characteristics
5. **Container Integration**: Seamless integration with existing Container.Pool GenServer

**Key Recommendations:**
- Use PartitionSupervisor for stage process distribution
- Implement custom demand dispatching for repository-based task grouping
- Configure process hibernation for memory efficiency during idle periods
- Design stage failure isolation to prevent cascade failures

#### Senior Engineer Consultation
**Scalability and Production Patterns:**
1. **Circuit Breaker Implementation**: Prevent cascade failures in multi-stage pipeline
2. **Monitoring and Observability**: Comprehensive metrics collection and alerting
3. **Dynamic Scaling**: Auto-scaling based on queue depth and processing metrics
4. **Resource Management**: Memory pressure monitoring and adaptive concurrency
5. **Production Deployment**: Rolling deployment strategies for pipeline updates

**Architecture Decisions:**
- Implement stage-specific health checks with configurable thresholds
- Use Telemetry events for comprehensive pipeline monitoring
- Design graceful degradation for partial stage failures
- Implement circuit breakers at external dependency boundaries

## Technical Details

### Stage Module Architecture

#### 1. SweBench.Pipeline.TaskProducer

```elixir
defmodule SweBench.Pipeline.TaskProducer do
  use GenStage
  
  # Configuration
  @buffer_size 50
  @batch_size 10
  @demand_threshold 20
  
  # State management
  defstruct [
    :config,
    :batch_optimizer,
    :pending_tasks,
    :demand_count,
    :statistics
  ]
  
  # Key functions
  # - handle_demand/2: Fetch tasks based on downstream demand
  # - optimize_batches/2: Group tasks by repository for efficiency
  # - schedule_retry/3: Handle failed task rescheduling
end
```

#### 2. SweBench.Pipeline.PatchFetcher

```elixir
defmodule SweBench.Pipeline.PatchFetcher do
  use GenStage
  
  # Configuration
  @max_concurrency 5
  @rate_limit_window 60_000
  @cache_ttl 3_600_000
  
  # Integration with rate limiting and caching
  # - LLM API client with exponential backoff
  # - Cache-first lookup with SweBench.GitHub.Cache
  # - Circuit breaker for API failure handling
end
```

#### 3. SweBench.Pipeline.ContainerEvaluator

```elixir
defmodule SweBench.Pipeline.ContainerEvaluator do
  use GenStage
  
  # Deep integration with existing systems
  alias SweBench.Container.Pool
  alias SweBench.TestRunner
  
  # Configuration
  @max_concurrency 12
  @evaluation_timeout 300_000
  @health_check_interval 30_000
  
  # Container pool integration
  # - Container checkout/checkin with timeout
  # - Health monitoring and replacement
  # - Resource usage tracking
end
```

#### 4. SweBench.Pipeline.ResultAnalyzer

```elixir
defmodule SweBench.Pipeline.ResultAnalyzer do
  use GenStage
  
  # Configuration
  @max_concurrency 6
  @batch_write_size 20
  @analysis_timeout 60_000
  
  # Integration with existing analysis systems
  alias SweBench.TestRunner.Analyzer
  alias SweBench.Repo
  
  # Parallel processing with streaming writes
end
```

### Supervision Tree Design

```elixir
defmodule SweBench.Pipeline.Supervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    children = [
      # Stage registry for dynamic stage discovery
      {Registry, keys: :unique, name: SweBench.Pipeline.StageRegistry},
      
      # Pipeline stages with restart strategies
      {SweBench.Pipeline.TaskProducer, [name: :task_producer]},
      {PartitionSupervisor, 
       child_spec: SweBench.Pipeline.PatchFetcher,
       name: SweBench.Pipeline.PatchFetcherSupervisor,
       partitions: 5},
      {PartitionSupervisor,
       child_spec: SweBench.Pipeline.ContainerEvaluator, 
       name: SweBench.Pipeline.EvaluatorSupervisor,
       partitions: 12},
      {PartitionSupervisor,
       child_spec: SweBench.Pipeline.ResultAnalyzer,
       name: SweBench.Pipeline.AnalyzerSupervisor, 
       partitions: 6},
       
      # Pipeline health monitor
      {SweBench.Pipeline.HealthMonitor, opts},
      
      # Circuit breaker manager
      {SweBench.Pipeline.CircuitBreaker, opts}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Backpressure Configuration

#### Buffer Size Optimization
- **TaskProducer**: 50-task buffer with demand-based refill
- **PatchFetcher**: 20-request buffer with rate limit coordination
- **ContainerEvaluator**: 15-task buffer aligned with container pool size
- **ResultAnalyzer**: 30-result buffer for batch processing optimization

#### Adaptive Concurrency Control
```elixir
defmodule SweBench.Pipeline.ConcurrencyController do
  use GenServer
  
  # Monitor system resources
  # - Memory usage via :erlang.memory()
  # - CPU usage via :cpu_sup
  # - Container pool utilization
  
  # Adjust stage concurrency dynamically
  # - Scale up during low resource usage
  # - Scale down during memory pressure
  # - Implement hysteresis to prevent thrashing
end
```

#### Memory Pressure Monitoring
- **Thresholds**: Scale down at 80% memory usage, scale up below 60%
- **Monitoring interval**: 5-second resource checks
- **Response time**: 2-second maximum adjustment latency

### Stage Subscription Configuration

```elixir
# Pipeline wiring with subscription options
GenStage.sync_subscribe(patch_fetcher, to: task_producer, 
                       max_demand: 10, min_demand: 5)
GenStage.sync_subscribe(container_evaluator, to: patch_fetcher,
                       max_demand: 8, min_demand: 3)
GenStage.sync_subscribe(result_analyzer, to: container_evaluator,
                       max_demand: 15, min_demand: 8)
```

### Batch Optimization Implementation

#### Repository-Based Task Grouping
```elixir
defmodule SweBench.Pipeline.BatchOptimizer do
  # Group tasks by repository for container cache efficiency
  def optimize_batches(tasks, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 10)
    
    tasks
    |> Enum.group_by(&get_repository_key/1)
    |> Enum.flat_map(fn {_repo, repo_tasks} ->
         Enum.chunk_every(repo_tasks, batch_size)
       end)
  end
  
  # Cache-aware container allocation
  def assign_containers(batch, container_pools) do
    # Prefer containers with matching repository cache
    # Fall back to available containers from other pools
  end
end
```

#### Intelligent Batch Sizing
- **Repository batching**: Group same-repository tasks for cache efficiency
- **Container affinity**: Route batches to containers with warm caches
- **Timeout handling**: Smaller batches for time-sensitive tasks
- **Failure isolation**: Limit batch size to minimize failure blast radius

## Success Criteria

### Throughput Targets
- **Primary Goal**: Achieve 300+ task evaluations per hour
- **Performance Improvement**: Demonstrate 10-20x throughput increase over sequential baseline
- **Resource Efficiency**: Maintain 80%+ container pool utilization during peak load
- **Latency Reduction**: Reduce average task evaluation time from 6 minutes to <2 minutes

### Reliability Metrics
- **Pipeline Uptime**: 99.5% uptime during continuous operation
- **Error Recovery**: Automatic recovery from single-stage failures within 30 seconds
- **Fault Isolation**: Stage failures do not affect other stages' operation
- **Data Integrity**: 100% result accuracy compared to sequential evaluation

### Integration Requirements
- **Backward Compatibility**: Seamless integration with existing Phase 1.1-1.5 infrastructure
- **Container Pool Integration**: Full integration with SweBench.Container.Pool system
- **Database Performance**: No degradation in database write performance
- **API Compliance**: Respect all GitHub API and LLM service rate limits

### Scalability Validation
- **Concurrent Load**: Handle 50+ simultaneous task evaluations
- **Memory Management**: Stable memory usage under sustained load
- **CPU Utilization**: Optimal utilization of multi-core systems
- **Container Scaling**: Dynamic scaling based on workload demand

## Implementation Plan

### Phase 1: Core GenStage Implementation (Week 1)

#### Step 1.1: Add GenStage Dependencies
- Add `gen_stage` dependency to mix.exs
- Configure GenStage in application.ex supervision tree
- Set up stage registry for dynamic stage discovery

#### Step 1.2: Implement TaskProducer Stage
- Create SweBench.Pipeline.TaskProducer module with GenStage Producer behavior
- Implement demand-based task fetching from database using Ecto
- Add repository-based task grouping with BatchOptimizer module
- Configure buffer sizes and demand thresholds
- Add comprehensive logging and telemetry events

#### Step 1.3: Create Basic Pipeline Supervisor
- Implement SweBench.Pipeline.Supervisor with proper supervision tree
- Configure restart strategies (one_for_one for individual stages)
- Add pipeline registry for stage process discovery
- Implement graceful shutdown procedures

### Phase 2: Processing Stages Implementation (Week 2)

#### Step 2.1: Build PatchFetcher ProducerConsumer
- Create SweBench.Pipeline.PatchFetcher with ProducerConsumer behavior
- Integrate with existing SweBench.GitHub.Client and rate limiting
- Implement LLM API client with exponential backoff and circuit breaker
- Add response caching with configurable TTL
- Configure parallel fetcher processes (5 workers)

#### Step 2.2: Implement ContainerEvaluator ConsumerProducer  
- Create SweBench.Pipeline.ContainerEvaluator with deep Container.Pool integration
- Implement container checkout/checkin with timeout handling
- Add container health monitoring and automatic replacement
- Integrate with existing SweBench.TestRunner system
- Configure parallel evaluator processes (12 workers)

#### Step 2.3: Create ResultAnalyzer Consumer
- Build SweBench.Pipeline.ResultAnalyzer with Consumer behavior
- Integrate with existing SweBench.TestRunner.Analyzer
- Implement parallel result analysis with configurable concurrency
- Add batch database writes with streaming for performance
- Configure real-time progress notifications

### Phase 3: Advanced Features and Optimization (Week 3)

#### Step 3.1: Implement Adaptive Concurrency Control
- Create SweBench.Pipeline.ConcurrencyController GenServer
- Add memory pressure monitoring using :erlang.memory()
- Implement CPU usage tracking with :cpu_sup
- Build dynamic scaling algorithms with hysteresis
- Configure resource thresholds and adjustment intervals

#### Step 3.2: Add Circuit Breaker and Health Monitoring
- Implement SweBench.Pipeline.CircuitBreaker for external dependencies
- Create SweBench.Pipeline.HealthMonitor for comprehensive pipeline health
- Add stage-specific health checks with configurable thresholds
- Implement automatic recovery procedures and alerting
- Configure failure detection and cascade prevention

#### Step 3.3: Optimize Batch Processing
- Enhance BatchOptimizer with cache-aware container allocation
- Implement repository affinity routing for container reuse
- Add intelligent batch sizing based on task characteristics
- Configure batch timeout handling and failure isolation
- Optimize database batch operations for result storage

### Phase 4: Integration and Testing (Week 4)

#### Step 4.1: Pipeline Integration Testing
- Test end-to-end pipeline flow with all stages active
- Validate backpressure handling under various load conditions
- Test stage failure and recovery scenarios
- Verify container pool integration and resource management
- Validate result accuracy against sequential baseline

#### Step 4.2: Performance Optimization and Tuning
- Benchmark pipeline throughput under different configurations
- Optimize buffer sizes and concurrency levels
- Tune batch sizes for optimal cache efficiency
- Configure telemetry collection and monitoring dashboards
- Establish performance baselines and SLA targets

#### Step 4.3: Production Readiness
- Implement comprehensive logging and error reporting
- Add pipeline metrics collection and alerting
- Configure graceful shutdown and restart procedures
- Add configuration management for different environments
- Prepare deployment scripts and monitoring setup

### Phase 5: Documentation and Deployment (Week 5)

#### Step 5.1: Documentation and Runbooks
- Create comprehensive pipeline architecture documentation
- Write operational runbooks for common scenarios
- Document configuration parameters and tuning guidelines
- Prepare troubleshooting guides for production issues
- Create monitoring and alerting setup documentation

#### Step 5.2: Final Integration Testing
- Conduct comprehensive integration tests across all Phase 1 components
- Validate throughput improvements (target: 300+ tasks/hour)
- Test fault tolerance and recovery under production-like conditions
- Verify backward compatibility with existing systems
- Conduct performance regression testing

## Notes/Considerations

### Performance Optimization Strategies

#### BEAM VM Optimization
- **Process hibernation**: Configure idle processes to hibernate for memory efficiency
- **Scheduler utilization**: Ensure even distribution across BEAM scheduler threads
- **Memory management**: Use binary references for large data to avoid copying
- **Process messaging**: Minimize message copying with strategic data structure design

#### Container Pool Integration
- **Warm cache optimization**: Route tasks to containers with matching repository caches
- **Health check scheduling**: Stagger container health checks to avoid resource spikes
- **Pre-warming strategies**: Intelligent pre-warming based on task queue composition
- **Resource monitoring**: Track container resource usage for optimal pool sizing

#### Database Performance
- **Connection pooling**: Optimize database connection pool size for concurrent writes
- **Batch operations**: Use batch inserts for result storage to minimize database load
- **Index optimization**: Ensure proper indexing for task fetching queries
- **Query optimization**: Use prepared statements for frequently executed queries

### Error Recovery and Resilience

#### Stage-Level Recovery
- **Individual stage restart**: Isolate stage failures from pipeline operation
- **State reconstruction**: Rebuild stage state from persistent storage after restart
- **In-flight task handling**: Graceful handling of tasks in progress during stage restart
- **Circuit breaker coordination**: Coordinate circuit breakers across dependent stages

#### Pipeline-Level Recovery
- **Graceful degradation**: Continue operation with reduced capacity during partial failures
- **Automatic failover**: Switch to backup stages during extended outages
- **Data consistency**: Ensure result integrity during recovery scenarios
- **Progress tracking**: Maintain evaluation progress across pipeline restarts

#### External Dependency Resilience
- **API rate limiting**: Respect external API limits with exponential backoff
- **Cache fallback**: Use cached data during external service outages
- **Timeout handling**: Configure appropriate timeouts for all external calls
- **Health monitoring**: Continuous monitoring of external service health

### Monitoring and Observability

#### Metrics Collection
- **Pipeline throughput**: Tasks processed per hour across all stages
- **Stage-specific metrics**: Processing times, error rates, and queue depths per stage
- **Resource utilization**: CPU, memory, and container pool utilization
- **External dependency metrics**: API response times, error rates, and rate limit status

#### Alerting and Notification
- **Threshold-based alerts**: Alert on throughput degradation or error rate increases
- **Predictive alerting**: Alert on trends that may lead to future issues
- **Stage-specific notifications**: Different alert levels for different stage failures
- **Recovery notifications**: Automatic notifications when systems recover

#### Dashboard and Reporting
- **Real-time pipeline status**: Live view of pipeline health and performance
- **Historical trend analysis**: Long-term performance trends and optimization opportunities
- **Comparative analysis**: Performance comparison against baseline and targets
- **Capacity planning**: Resource utilization trends for infrastructure planning

### Deployment and Scaling Considerations

#### Rolling Deployment Strategy
- **Stage-by-stage deployment**: Deploy and validate each stage independently
- **Backward compatibility**: Ensure new stages can work with existing stages
- **Feature flags**: Use feature flags to enable/disable pipeline components
- **Rollback procedures**: Quick rollback procedures for problematic deployments

#### Horizontal Scaling
- **Stage partitioning**: Use PartitionSupervisor for horizontal stage scaling
- **Load balancing**: Distribute work evenly across stage partitions
- **Node coordination**: Coordinate pipeline across multiple nodes if needed
- **State management**: Design for stateless operation where possible

#### Configuration Management
- **Environment-specific configs**: Different configurations for dev/staging/production
- **Dynamic configuration**: Runtime configuration updates without restart
- **Configuration validation**: Validate configuration parameters at startup
- **Documentation**: Comprehensive documentation of all configuration options

This comprehensive planning document provides the foundation for implementing a high-throughput, fault-tolerant GenStage pipeline that will transform the SWE-bench-Elixir system from a sequential evaluation approach to a parallel, scalable architecture capable of processing 300+ tasks per hour while maintaining reliability and integration with all existing Phase 1 infrastructure components.