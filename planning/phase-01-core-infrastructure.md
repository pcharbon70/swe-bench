# Phase 1: Core Infrastructure & Containerization

This foundational phase establishes the critical infrastructure for SWE-bench-Elixir, focusing on Docker-based containerization optimized for the BEAM VM, basic ExUnit test execution with structured result capture, and GitHub API integration for data collection. The architecture employs a three-layer Docker approach specifically adapted for Mix projects and BEAM compilation challenges, while implementing isolated environments for deterministic test execution. By the end of this phase, the system will successfully evaluate tasks from 5 initial Elixir repositories, providing a solid foundation for expansion.

## 1.1 Docker Containerization with BEAM VM Optimization

This section implements the three-layer Docker architecture designed specifically for BEAM VM and Mix ecosystem requirements. The containerization strategy addresses unique Elixir challenges including compiled .beam file management, incremental compilation cascades, and EPMD instance isolation. Each layer serves a distinct purpose: base runtime with system dependencies, environment-specific dependency compilation, and instance-specific code execution with patches applied.

### Tasks:
- [x] 1.1.1 Create base Docker image for Elixir/OTP
  - [x] 1.1.1.1 Configure Alpine Linux base with minimal footprint
  - [x] 1.1.1.2 Install Elixir 1.16 and Erlang/OTP 27
  - [x] 1.1.1.3 Add system dependencies (git, build-base, postgresql-client)
  - [x] 1.1.1.4 Configure EPMD for isolated instances
  - [x] 1.1.1.5 Set up locale and timezone for deterministic behavior

- [x] 1.1.2 Implement environment layer for dependencies
  - [x] 1.1.2.1 Create workspace directory structure
  - [x] 1.1.2.2 Configure Mix for offline dependency resolution
  - [x] 1.1.2.3 Install Hex and Rebar without network access
  - [x] 1.1.2.4 Implement dependency caching mechanism
  - [x] 1.1.2.5 Handle umbrella project dependency graphs

- [x] 1.1.3 Build instance layer for task execution
  - [x] 1.1.3.1 Apply code patches to specific commits
  - [x] 1.1.3.2 Manage incremental compilation state
  - [x] 1.1.3.3 Configure resource limits (4GB RAM, 4 CPU cores)
  - [x] 1.1.3.4 Implement 300-second execution timeout
  - [x] 1.1.3.5 Handle compilation artifact cleanup

- [x] 1.1.4 Create advanced container orchestration module
  - [x] 1.1.4.1 Implement container lifecycle management
  - [x] 1.1.4.2 Add volume mounting for code injection
  - [x] 1.1.4.3 Configure network isolation per evaluation
  - [x] 1.1.4.4 Implement basic container pooling for performance
  - [x] 1.1.4.5 Add cleanup and garbage collection
  - [x] 1.1.4.6 Implement container pool pre-warming strategy
  - [x] 1.1.4.7 Create container reuse mechanisms with state clearing
  - [x] 1.1.4.8 Build pool size auto-scaling based on demand
  - [x] 1.1.4.9 Add health checks for pooled containers
  - [x] 1.1.4.10 Implement container checkout/checkin system with timeouts

### Unit Tests:
- [x] 1.1.5 Test Docker image build process
- [x] 1.1.6 Test dependency installation without network
- [x] 1.1.7 Test patch application on various repository structures
- [x] 1.1.8 Test resource limit enforcement
- [x] 1.1.9 Test container isolation between evaluations
- [x] 1.1.10 Test umbrella project handling
- [x] 1.1.11 Test compilation artifact management

## 1.2 ExUnit Test Runner with Result Capture

This section develops the core test execution engine that integrates deeply with ExUnit to capture structured test results. The system handles both synchronous and asynchronous test execution, manages ExUnit's concurrent test runner for deterministic results, and extracts detailed failure information for evaluation. Custom formatters provide granular visibility into test outcomes, including timing, failure reasons, and assertion types.

### Tasks:
- [x] 1.2.1 Create ExUnit custom formatter
  - [x] 1.2.1.1 Implement GenServer-based formatter
  - [x] 1.2.1.2 Capture test module, name, and state
  - [x] 1.2.1.3 Extract failure messages and stacktraces
  - [x] 1.2.1.4 Identify assertion types from failures
  - [x] 1.2.1.5 Record test execution timing

- [x] 1.2.2 Implement test execution orchestrator
  - [x] 1.2.2.1 Configure Mix test environment variables
  - [x] 1.2.2.2 Force synchronous execution for determinism
  - [x] 1.2.2.3 Preserve async test semantics through process isolation
  - [x] 1.2.2.4 Handle test timeouts and infinite loops
  - [x] 1.2.2.5 Capture compilation errors during test runs

- [x] 1.2.3 Build test result analyzer
  - [x] 1.2.3.1 Parse FAIL_TO_PASS test transitions
  - [x] 1.2.3.2 Verify PASS_TO_PASS test stability
  - [x] 1.2.3.3 Detect test flakiness and non-determinism
  - [x] 1.2.3.4 Calculate test coverage metrics
  - [x] 1.2.3.5 Generate structured JSON reports

- [x] 1.2.4 Create test isolation mechanism
  - [x] 1.2.4.1 Reset application state between tests
  - [x] 1.2.4.2 Clear ETS tables and process registry
  - [x] 1.2.4.3 Handle database transaction rollbacks
  - [x] 1.2.4.4 Manage GenServer state cleanup
  - [x] 1.2.4.5 Ensure supervisor tree restart

### Unit Tests:
- [x] 1.2.5 Test custom formatter output accuracy
- [x] 1.2.6 Test failure extraction and categorization
- [x] 1.2.7 Test async vs sync execution handling
- [x] 1.2.8 Test timeout and infinite loop detection
- [x] 1.2.9 Test result JSON serialization
- [x] 1.2.10 Test state isolation between test runs
- [x] 1.2.11 Test coverage calculation accuracy

## 1.3 GitHub API Integration for Data Collection

This section implements the GitHub API client for collecting repository data, issues, and pull requests. The integration handles rate limiting, pagination, and authentication while building the foundation for the three-stage data collection pipeline. Special attention is given to Elixir-specific repository patterns, including umbrella projects and Hex package metadata extraction.

### Tasks:
- [x] 1.3.1 Implement GitHub API client
  - [x] 1.3.1.1 Configure Tentacat or custom HTTP client
  - [x] 1.3.1.2 Implement OAuth authentication flow
  - [x] 1.3.1.3 Handle rate limiting with exponential backoff
  - [x] 1.3.1.4 Implement pagination for large result sets
  - [x] 1.3.1.5 Add request caching for efficiency

- [x] 1.3.2 Create repository analyzer
  - [x] 1.3.2.1 Fetch repository metadata and statistics
  - [x] 1.3.2.2 Analyze commit history and activity
  - [x] 1.3.2.3 Extract Hex.pm package information
  - [x] 1.3.2.4 Identify umbrella project structure
  - [x] 1.3.2.5 Calculate test coverage from CI badges

- [x] 1.3.3 Build issue and PR collector
  - [x] 1.3.3.1 Fetch closed issues with linked PRs
  - [x] 1.3.3.2 Extract PR diff and patch content
  - [x] 1.3.3.3 Identify test file modifications
  - [x] 1.3.3.4 Parse PR review comments for context
  - [x] 1.3.3.5 Track function and module changes

- [x] 1.3.4 Implement data persistence layer
  - [x] 1.3.4.1 Design Ecto schemas for repositories
  - [x] 1.3.4.2 Create schemas for issues and PRs
  - [x] 1.3.4.3 Store task instances with metadata
  - [x] 1.3.4.4 Implement data deduplication
  - [x] 1.3.4.5 Add indexing for efficient queries

### Unit Tests:
- [x] 1.3.5 Test API authentication and rate limiting
- [x] 1.3.6 Test pagination handling for large datasets
- [x] 1.3.7 Test repository metadata extraction
- [x] 1.3.8 Test issue-PR relationship detection
- [x] 1.3.9 Test diff parsing and patch extraction
- [x] 1.3.10 Test data persistence and retrieval
- [x] 1.3.11 Test umbrella project detection

## 1.4 Mix Project Management System

This section develops the Mix project management infrastructure that handles isolated environments, dependency resolution, and compilation orchestration. The system manages Mix.env configurations, handles lockfile restoration, and ensures deterministic builds across evaluations. Special consideration is given to umbrella applications with inter-app dependencies and complex compilation orders.

### Tasks:
- [x] 1.4.1 Create Mix environment isolator
  - [x] 1.4.1.1 Configure MIX_ENV for test execution
  - [x] 1.4.1.2 Set MIX_HOME and HEX_HOME paths
  - [x] 1.4.1.3 Enable deterministic compilation flags
  - [x] 1.4.1.4 Manage Mix.Config deprecated warnings
  - [x] 1.4.1.5 Handle runtime configuration loading

- [x] 1.4.2 Implement dependency manager
  - [x] 1.4.2.1 Parse and restore mix.lock files
  - [x] 1.4.2.2 Cache Hex packages locally
  - [x] 1.4.2.3 Handle git-based dependencies
  - [x] 1.4.2.4 Resolve version conflicts
  - [x] 1.4.2.5 Manage private package repositories

- [x] 1.4.3 Build compilation orchestrator
  - [x] 1.4.3.1 Determine compilation order for umbrella apps
  - [x] 1.4.3.2 Handle incremental compilation
  - [x] 1.4.3.3 Detect and resolve circular dependencies
  - [x] 1.4.3.4 Manage protocol consolidation
  - [x] 1.4.3.5 Cache compilation artifacts

- [x] 1.4.4 Create project structure analyzer
  - [x] 1.4.4.1 Detect project type (standard/umbrella/poncho)
  - [x] 1.4.4.2 Map application dependencies
  - [x] 1.4.4.3 Identify test file locations
  - [x] 1.4.4.4 Parse configuration files
  - [x] 1.4.4.5 Extract build tool requirements

### Unit Tests:
- [x] 1.4.5 Test environment variable isolation
- [x] 1.4.6 Test dependency resolution accuracy
- [x] 1.4.7 Test umbrella project compilation order
- [x] 1.4.8 Test lockfile restoration
- [x] 1.4.9 Test compilation artifact caching
- [x] 1.4.10 Test project type detection
- [x] 1.4.11 Test circular dependency handling

## 1.5 Initial Repository Setup and Validation

This section establishes the initial set of 5 repositories for proof-of-concept validation, ensuring each repository meets quality criteria for benchmarking. The selection focuses on well-maintained projects with comprehensive test suites, clear issue descriptions, and active development. Each repository undergoes validation to ensure compatibility with the evaluation infrastructure.

### Tasks:
- [x] 1.5.1 Select and configure Phoenix Framework
  - [x] 1.5.1.1 Clone repository at stable version
  - [x] 1.5.1.2 Verify test suite completeness
  - [x] 1.5.1.3 Analyze issue-PR patterns
  - [x] 1.5.1.4 Extract 10 sample task instances
  - [x] 1.5.1.5 Validate Docker execution

- [x] 1.5.2 Set up Ecto repository
  - [x] 1.5.2.1 Configure database adapters for testing
  - [x] 1.5.2.2 Handle schema migrations in containers
  - [x] 1.5.2.3 Verify query-based test execution
  - [x] 1.5.2.4 Extract 10 sample task instances
  - [x] 1.5.2.5 Test isolation with database state

- [x] 1.5.3 Configure Jason JSON library
  - [x] 1.5.3.1 Set up pure Elixir test environment
  - [x] 1.5.3.2 Verify parser test coverage
  - [x] 1.5.3.3 Extract encoding/decoding tasks
  - [x] 1.5.3.4 Generate 10 task instances
  - [x] 1.5.3.5 Validate performance benchmarks

- [x] 1.5.4 Add Tesla HTTP client
  - [x] 1.5.4.1 Configure middleware test setup
  - [x] 1.5.4.2 Handle mock adapter configuration
  - [x] 1.5.4.3 Extract adapter-specific tasks
  - [x] 1.5.4.4 Create 10 task instances
  - [x] 1.5.4.5 Test with various HTTP scenarios

- [x] 1.5.5 Include Credo static analyzer
  - [x] 1.5.5.1 Set up AST analysis environment
  - [x] 1.5.5.2 Configure custom check testing
  - [x] 1.5.5.3 Extract linting rule tasks
  - [x] 1.5.5.4 Generate 10 task instances
  - [x] 1.5.5.5 Validate check execution

### Unit Tests:
- [x] 1.5.6 Test repository cloning and setup
- [x] 1.5.7 Test task instance extraction accuracy
- [x] 1.5.8 Test cross-repository compatibility
- [x] 1.5.9 Test database-dependent repositories
- [x] 1.5.10 Test pure Elixir library evaluation
- [x] 1.5.11 Test task instance validation

## 1.6 GenStage Pipeline Architecture

This section implements the GenStage-based pipeline architecture that enables parallel task evaluation with backpressure control. The pipeline transforms the sequential evaluation process into a high-throughput system capable of processing hundreds of tasks per hour. By implementing producer-consumer stages with proper supervision, the system achieves both performance and reliability goals while maintaining deterministic evaluation results.

### Tasks:
- [x] 1.6.1 Implement GenStage producer for task instances
  - [x] 1.6.1.1 Create TaskProducer GenStage module
  - [x] 1.6.1.2 Implement demand-based task fetching from database
  - [x] 1.6.1.3 Add task prioritization and ordering logic
  - [x] 1.6.1.4 Handle producer state management and recovery
  - [x] 1.6.1.5 Implement batch optimization for repository grouping

- [x] 1.6.2 Create LLM patch fetcher stage
  - [x] 1.6.2.1 Build ProducerConsumer for LLM API calls
  - [x] 1.6.2.2 Implement parallel patch fetching with rate limiting
  - [x] 1.6.2.3 Add retry logic with exponential backoff
  - [x] 1.6.2.4 Cache LLM responses for reuse
  - [x] 1.6.2.5 Handle API failures and timeout scenarios

- [x] 1.6.3 Build container evaluation stage
  - [x] 1.6.3.1 Create ConsumerProducer for container execution
  - [x] 1.6.3.2 Integrate with container pool for parallel evaluation
  - [x] 1.6.3.3 Implement container health monitoring
  - [x] 1.6.3.4 Add evaluation timeout and resource management
  - [x] 1.6.3.5 Handle container failures and restarts

- [x] 1.6.4 Implement result analysis stage
  - [x] 1.6.4.1 Build Consumer for test result analysis
  - [x] 1.6.4.2 Process FAIL_TO_PASS transitions in parallel
  - [x] 1.6.4.3 Calculate scoring metrics concurrently
  - [x] 1.6.4.4 Stream results to database without blocking
  - [x] 1.6.4.5 Generate real-time progress notifications

- [x] 1.6.5 Create pipeline supervisor with restart strategies
  - [x] 1.6.5.1 Design supervision tree for pipeline stages
  - [x] 1.6.5.2 Implement stage restart strategies (one_for_one, rest_for_one)
  - [x] 1.6.5.3 Add circuit breakers for failing stages
  - [x] 1.6.5.4 Create pipeline health monitoring
  - [x] 1.6.5.5 Implement graceful shutdown procedures

- [x] 1.6.6 Configure backpressure and flow control
  - [x] 1.6.6.1 Set optimal buffer sizes for each stage
  - [x] 1.6.6.2 Implement adaptive concurrency control
  - [x] 1.6.6.3 Add memory pressure monitoring
  - [x] 1.6.6.4 Configure stage subscription options
  - [x] 1.6.6.5 Implement load balancing across consumers

- [x] 1.6.7 Implement batch optimization strategies
  - [x] 1.6.7.1 Create BatchOptimizer module for task grouping
  - [x] 1.6.7.2 Group tasks by repository for cache efficiency
  - [x] 1.6.7.3 Implement intelligent batch sizing
  - [x] 1.6.7.4 Add batch timeout handling
  - [x] 1.6.7.5 Optimize for container reuse patterns

### Unit Tests:
- [x] 1.6.8 Test GenStage producer demand handling
- [x] 1.6.9 Test pipeline backpressure mechanisms
- [x] 1.6.10 Test stage failure and recovery
- [x] 1.6.11 Test batch optimization logic
- [x] 1.6.12 Test concurrent evaluation throughput
- [x] 1.6.13 Test pipeline supervision tree
- [x] 1.6.14 Test flow control under load

## 1.7 Advanced Container Pool Management

This section enhances the container pooling system with sophisticated management capabilities including pre-warming, health monitoring, and dynamic scaling. The pool maintains a ready set of containers for immediate use, dramatically reducing evaluation latency while optimizing resource utilization. Advanced features like container recycling and state clearing ensure both performance and isolation guarantees.

### Tasks:
- [ ] 1.7.1 Implement container pool supervisor
  - [ ] 1.7.1.1 Create PoolSupervisor with dynamic child management
  - [ ] 1.7.1.2 Implement pool size configuration and limits
  - [ ] 1.7.1.3 Add container lifecycle event handling
  - [ ] 1.7.1.4 Create pool metrics collection
  - [ ] 1.7.1.5 Implement pool draining for maintenance

- [ ] 1.7.2 Build container pre-warming system
  - [ ] 1.7.2.1 Create base container images for each repository
  - [ ] 1.7.2.2 Implement warm container queue management
  - [ ] 1.7.2.3 Add predictive pre-warming based on usage patterns
  - [ ] 1.7.2.4 Optimize container startup time
  - [ ] 1.7.2.5 Implement repository-specific warming strategies

- [ ] 1.7.3 Create container health monitoring
  - [ ] 1.7.3.1 Implement periodic health checks for pooled containers
  - [ ] 1.7.3.2 Add memory and CPU usage monitoring
  - [ ] 1.7.3.3 Detect and remove unhealthy containers
  - [ ] 1.7.3.4 Monitor container age and usage count
  - [ ] 1.7.3.5 Implement container refresh policies

- [ ] 1.7.4 Build checkout/checkin system
  - [ ] 1.7.4.1 Create GenServer for pool management
  - [ ] 1.7.4.2 Implement fair container allocation
  - [ ] 1.7.4.3 Add checkout timeout and retry logic
  - [ ] 1.7.4.4 Handle stuck container detection
  - [ ] 1.7.4.5 Implement priority-based allocation

- [ ] 1.7.5 Implement dynamic pool scaling
  - [ ] 1.7.5.1 Monitor pool utilization metrics
  - [ ] 1.7.5.2 Implement auto-scaling algorithms
  - [ ] 1.7.5.3 Add scale-up and scale-down policies
  - [ ] 1.7.5.4 Handle resource constraints gracefully
  - [ ] 1.7.5.5 Implement predictive scaling based on patterns

### Unit Tests:
- [ ] 1.7.6 Test container pool initialization
- [ ] 1.7.7 Test pre-warming strategies
- [ ] 1.7.8 Test health check mechanisms
- [ ] 1.7.9 Test checkout/checkin concurrency
- [ ] 1.7.10 Test dynamic scaling behavior
- [ ] 1.7.11 Test pool recovery from failures
- [ ] 1.7.12 Test resource limit enforcement

## 1.8 Phase 1 Integration Tests

### Integration Tests:
- [ ] 1.8.1 End-to-end Docker container lifecycle
  - [ ] Test complete build, run, and cleanup cycle
  - [ ] Verify resource limit enforcement
  - [ ] Validate isolation between concurrent evaluations
  
- [ ] 1.8.2 Complete test execution pipeline
  - [ ] Test patch application and compilation
  - [ ] Verify test result capture and analysis
  - [ ] Validate FAIL_TO_PASS transition detection

- [ ] 1.8.3 GitHub data collection workflow
  - [ ] Test repository analysis and selection
  - [ ] Verify issue-PR linking accuracy
  - [ ] Validate task instance generation

- [ ] 1.8.4 Mix project handling across repositories
  - [ ] Test standard, umbrella, and poncho projects
  - [ ] Verify dependency resolution
  - [ ] Validate compilation orchestration

- [ ] 1.8.5 Multi-repository evaluation suite
  - [ ] Test all 5 configured repositories
  - [ ] Verify 50 task instances (10 per repo)
  - [ ] Validate result consistency and determinism

- [ ] 1.8.6 GenStage pipeline integration
  - [ ] Test end-to-end pipeline flow with all stages
  - [ ] Verify backpressure handling under load
  - [ ] Validate throughput improvements (target: 300+ tasks/hour)
  - [ ] Test pipeline recovery from stage failures
  - [ ] Measure resource utilization efficiency

- [ ] 1.8.7 Container pool integration
  - [ ] Test pool pre-warming effectiveness
  - [ ] Verify container reuse and state isolation
  - [ ] Validate dynamic scaling under varying loads
  - [ ] Test pool recovery from container failures
  - [ ] Measure latency reduction from pooling

- [ ] 1.8.8 Performance and scalability validation
  - [ ] Measure baseline sequential throughput
  - [ ] Measure GenStage pipeline throughput
  - [ ] Compare resource utilization (CPU, memory, containers)
  - [ ] Validate 10-20x throughput improvement
  - [ ] Establish production performance metrics

---

## Phase Dependencies

**Prerequisites:**
- Docker and Docker Compose installation
- Elixir 1.16+ and Erlang/OTP 27+
- PostgreSQL for data persistence
- GitHub API access token
- 16GB RAM minimum for container operations

**Provides Foundation For:**
- Phase 2: Elixir-Specific Evaluation Engine
- Phase 3: Data Collection Pipeline
- Phase 4: Advanced Capabilities
- All subsequent phases rely on this containerization and test execution infrastructure

**Key Outputs:**
- Docker images optimized for BEAM VM evaluation
- ExUnit test runner with structured result capture
- GitHub API integration with 5 repository configurations
- Mix project management system
- 50 validated task instances ready for benchmarking
- Performance baseline metrics

**Success Criteria:**
- All 5 repositories successfully evaluated
- 100% task instance validation pass rate
- Test execution determinism verified
- Container resource limits enforced
- Sequential evaluation throughput ≥ 10 tasks/hour (baseline)
- GenStage pipeline throughput ≥ 300 tasks/hour (with pooling)
- Container pool maintaining 80%+ warm container availability
- Pipeline backpressure handling validated under load
- 10-20x throughput improvement demonstrated