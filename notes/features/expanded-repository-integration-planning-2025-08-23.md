# Expanded Repository Integration (Phase 2.6) - Planning Document

**Date:** 2025-08-23  
**Phase:** 2.6 - Expanded Repository Integration (15 Total)  
**Status:** Planning Complete - Ready for Implementation

## Problem Statement

The current SWE-bench-Elixir evaluation system supports 5 repositories (Phoenix, Ecto, Jason, Tesla, Credo) with basic configurations. Phase 2.6 requires expanding to 15 total repositories to provide comprehensive coverage of the Elixir ecosystem, including:

- **High-complexity repositories** requiring specialized testing setups (Phoenix LiveView, Oban, Broadway)
- **Specialized domain libraries** (Nx numerical computing, Membrane multimedia, Absinthe GraphQL)
- **Development tooling** (Benchee performance testing, ExDoc documentation, Guardian authentication)
- **Email and messaging** (Bamboo email delivery)

Each new repository presents unique challenges:
- Phoenix LiveView: JavaScript asset compilation, WebSocket testing, browser automation
- Oban: PostgreSQL setup, job queue testing, time-based scenarios
- Broadway: Message queue mocks, producer-consumer testing, backpressure handling
- Domain-specific libraries: Specialized dependencies and testing requirements

The expansion must integrate seamlessly with existing systems: pattern analysis, OTP validation, static analysis (Credo/Dialyzer), functional programming scoring, and umbrella project support.

## Solution Overview

### High-Level Approach

1. **Repository Configuration Framework Extension**
   - Extend existing `@supported_repositories` configuration with specialized repository types
   - Implement repository-specific configuration modules for complex setups
   - Add database schema extensions for storing repository-specific metadata

2. **Specialized Testing Infrastructure**
   - WebSocket testing framework for Phoenix LiveView
   - Time-based scenario handling for Oban job processing
   - Message queue mocking system for Broadway data pipelines
   - Browser automation integration for UI-dependent tests

3. **Dependency Management Enhancement**
   - Conflict detection and resolution across diverse dependencies
   - Repository-specific environment isolation
   - Dependency caching and optimization for performance

4. **Integration with Existing Analysis Systems**
   - Ensure all new repositories work with pattern matching analysis
   - Validate OTP behavior compliance across all repository types
   - Extend static analysis coverage to new repository patterns
   - Apply functional programming scoring to all repository types

### Key Design Decisions

1. **Modular Configuration Architecture**: Each repository type gets its own configuration module inheriting from a base configuration
2. **Progressive Rollout**: Implement repositories in complexity order (low → medium → high)
3. **Backward Compatibility**: All existing repositories continue to work without changes
4. **Performance Optimization**: Implement intelligent caching and parallel processing for the expanded repository set

## Agent Consultations Performed

**Note**: Direct agent consultation was not available during planning. The following expertise areas were considered based on codebase analysis:

### Elixir Expert Considerations
- **Repository Configuration Patterns**: Analyzed existing `SweBench.RepositorySetup.RepositoryManager` patterns
- **Dependency Management**: Reviewed `SweBench.MixProjectManager` for dependency handling strategies
- **Testing Infrastructure**: Examined `SweBench.TestRunner` for extensibility points
- **Integration Patterns**: Studied static analysis and evaluation pipeline integration points

### Research Agent Considerations  
- **Repository Selection Criteria**: Based on Elixir ecosystem popularity, diversity, and evaluation value
- **Task Extraction Strategies**: Analyzed existing `SweBench.RepositorySetup.TaskExtractor` patterns
- **Evaluation Methodologies**: Reviewed how diverse project types can contribute to comprehensive evaluation

### Senior Engineer Review Considerations
- **System Architecture**: Analyzed integration points with existing infrastructure
- **Performance Impact**: Considered resource requirements for expanded repository set
- **Maintainability**: Designed modular, extensible architecture for future repository additions

## Technical Details

### File Structure and Locations

#### New Files to Create
```
lib/swe_bench/repositories/
├── configurations/
│   ├── base_configuration.ex              # Base configuration module
│   ├── phoenix_liveview_configuration.ex  # LiveView-specific setup
│   ├── oban_configuration.ex              # Job processing setup
│   ├── broadway_configuration.ex          # Data pipeline setup
│   ├── benchee_configuration.ex           # Performance testing setup
│   ├── exdoc_configuration.ex             # Documentation setup
│   ├── bamboo_configuration.ex            # Email library setup
│   ├── guardian_configuration.ex          # Authentication setup
│   ├── absinthe_configuration.ex          # GraphQL setup
│   ├── nx_configuration.ex                # Numerical computing setup
│   └── membrane_configuration.ex          # Multimedia framework setup
├── testing_frameworks/
│   ├── websocket_tester.ex               # WebSocket testing utilities
│   ├── job_queue_tester.ex               # Job queue testing utilities
│   ├── message_queue_mocker.ex           # Message queue mocking
│   └── browser_automation.ex             # Browser testing integration
└── dependency_resolver.ex                 # Enhanced dependency management
```

#### Files to Modify
```
lib/swe_bench/repository_setup/repository_manager.ex  # Extend @supported_repositories
lib/swe_bench/repositories/repository.ex              # Add new metadata fields
lib/swe_bench/static_analysis/                        # Extend for new repository types
priv/repo/migrations/                                  # Add repository metadata schema
test/swe_bench/repositories/                          # New test suites
```

### Database Schema Extensions

#### New Repository Metadata Fields
```elixir
# In repository.ex attributes
attribute :repository_type, :string do
  constraints one_of: ["standard", "umbrella", "liveview", "job_processor", "data_pipeline", "performance", "documentation", "email", "auth", "graphql", "numerical", "multimedia"]
end

attribute :testing_requirements, :map do
  default %{}
  # Examples:
  # %{websocket_testing: true, browser_automation: true}  # LiveView
  # %{job_queue_testing: true, time_based_scenarios: true}  # Oban  
  # %{message_queue_mocking: true, backpressure_testing: true}  # Broadway
end

attribute :specialized_dependencies, {:array, :string} do
  default []
  # Examples: ["nodejs", "postgresql", "redis", "chrome-driver"]
end

attribute :performance_profile, :map do
  default %{}
  # %{cpu_intensive: true, memory_intensive: false, io_intensive: true}
end
```

### Integration Points

#### With Existing Pattern Analysis System
- All new repositories will be analyzed by `SweBench.PatternAnalysis`
- No changes needed to core pattern matching logic
- Repository-specific patterns may be added to quality scoring

#### With OTP Validation Framework  
- `SweBench.PatternAnalysis.OtpValidator` applies to all repositories
- Job processors (Oban) get enhanced GenServer validation
- Data pipelines (Broadway) get specialized process supervision analysis

#### With Static Analysis Integration
- `SweBench.StaticAnalysis` applies Credo/Dialyzer to all new repositories
- Repository-specific Credo configurations for specialized patterns
- Enhanced PLT management for diverse dependency sets

#### With Functional Programming Scoring
- `SweBench.FunctionalAnalysis` applies to all repository types
- Specialized scoring for numerical computing patterns (Nx)
- Enhanced pipeline analysis for data processing libraries

### Dependencies and Requirements

#### New System Dependencies
```elixir
# In mix.exs
{:broadway, "~> 1.0", only: [:dev, :test]},      # For Broadway testing
{:oban, "~> 2.17", only: [:dev, :test]},         # For Oban testing  
{:phoenix_live_view, "~> 0.20", only: [:dev, :test]}, # For LiveView testing
{:benchee, "~> 1.3", only: [:dev, :test]},       # For Benchee configuration
{:ex_doc, "~> 0.31", only: [:dev, :test]},       # For ExDoc testing
{:bamboo, "~> 2.3", only: [:dev, :test]},        # For Bamboo testing
{:guardian, "~> 2.3", only: [:dev, :test]},      # For Guardian testing  
{:absinthe, "~> 1.7", only: [:dev, :test]},      # For Absinthe testing
{:nx, "~> 0.7", only: [:dev, :test]},            # For Nx testing
{:membrane_core, "~> 1.0", only: [:dev, :test]}, # For Membrane testing
{:wallaby, "~> 0.30", only: [:test]},            # Browser automation
{:mock, "~> 0.3", only: [:test]}                 # Enhanced mocking capabilities
```

#### External System Requirements
```bash
# Required for comprehensive testing
- Node.js 18+ (Phoenix LiveView asset compilation)
- Chrome/Chromium + ChromeDriver (Browser automation)
- PostgreSQL 14+ (Enhanced for Oban testing)
- Redis 7+ (Message queue mocking)
```

## Success Criteria

### Quantitative Metrics
- **Repository Coverage**: Successfully configure and validate all 15 repositories
- **Task Extraction**: Extract minimum 15 tasks per repository (225 total tasks)
- **Analysis Coverage**: All repositories pass pattern analysis, OTP validation, static analysis
- **Performance**: Maintain evaluation throughput ≥ 50 tasks/hour despite 3x repository increase
- **Quality Scores**: All repositories achieve quality score ≥ 70 in validation
- **Test Coverage**: Achieve ≥ 95% test coverage for new repository configuration modules

### Qualitative Success Indicators
- **Seamless Integration**: New repositories integrate with existing analysis systems without breaking changes
- **Specialized Testing**: WebSocket, job queue, and message queue testing work correctly
- **Dependency Isolation**: No conflicts between repository-specific dependencies
- **Maintainability**: Configuration system is extensible for future repository additions
- **Documentation**: Comprehensive configuration documentation for each repository type

### Verification Methods
1. **Integration Testing**: Each repository passes full evaluation pipeline
2. **Performance Benchmarking**: System maintains acceptable performance under expanded load
3. **Cross-Repository Compatibility**: No interference between different repository types
4. **Task Quality Assessment**: Generated tasks meet evaluation standards across all repositories
5. **Error Handling**: Graceful degradation when specialized requirements aren't met

## Implementation Plan

### Phase 1: Foundation (Days 1-3)
1. **Base Configuration Framework**
   - Create `BaseConfiguration` module
   - Implement repository type system
   - Add database schema migrations
   - Update repository resource with new fields

2. **Testing Infrastructure Foundation**  
   - Implement `WebSocketTester` for LiveView
   - Create `JobQueueTester` for Oban
   - Build `MessageQueueMocker` for Broadway
   - Set up browser automation framework

3. **Enhanced Dependency Management**
   - Implement conflict detection
   - Add repository-specific environment isolation
   - Create dependency caching system

### Phase 2: Low-Complexity Repositories (Days 4-6)
1. **Standard Libraries** (Benchee, ExDoc, Bamboo)
   - Implement configuration modules
   - Add repository definitions to manager
   - Extract and validate task instances
   - Integration testing with analysis systems

2. **Authentication and GraphQL** (Guardian, Absinthe)
   - Handle authentication-specific testing patterns
   - GraphQL schema validation and testing
   - Specialized task extraction for these domains

### Phase 3: High-Complexity Repositories (Days 7-10)
1. **Phoenix LiveView Configuration**
   - JavaScript asset compilation pipeline
   - WebSocket testing integration
   - Browser automation setup
   - Real-time feature testing validation

2. **Oban Job Processor Configuration**
   - PostgreSQL setup with Oban tables
   - Job queue testing framework
   - Time-based test scenarios
   - Retry mechanism validation

3. **Broadway Data Pipeline Configuration**
   - Message queue mocking integration
   - Producer-consumer testing setup
   - Backpressure scenario handling
   - Flow control validation

### Phase 4: Specialized Libraries (Days 11-13)
1. **Numerical Computing** (Nx)
   - Handle numerical computation patterns
   - Performance-sensitive testing
   - Mathematical operation validation

2. **Multimedia Framework** (Membrane)
   - Media processing pipeline testing
   - Stream handling validation
   - Resource-intensive operation testing

### Phase 5: Integration and Optimization (Days 14-16)
1. **System Integration Testing**
   - End-to-end pipeline testing with all 15 repositories
   - Performance optimization and bottleneck resolution
   - Memory usage optimization for expanded repository set

2. **Quality Assurance and Documentation**
   - Comprehensive test suite completion
   - Configuration documentation
   - Performance benchmarking and optimization
   - Final integration testing

### Phase 6: Validation and Deployment (Days 17-18)
1. **Comprehensive Validation**
   - All repositories pass quality thresholds
   - Task extraction meets minimum requirements
   - Analysis systems work correctly across all types
   - Performance meets success criteria

2. **Documentation and Handover**
   - Complete implementation documentation
   - Configuration guides for each repository type
   - Troubleshooting guides
   - Future expansion guidelines

## Notes/Considerations

### Edge Cases and Risk Mitigation

1. **Dependency Conflicts**
   - **Risk**: Different repositories requiring incompatible versions of same dependency
   - **Mitigation**: Repository-specific containers, version pinning, conflict detection

2. **Resource Intensive Operations**
   - **Risk**: Numerical computing, multimedia processing overwhelming system resources
   - **Mitigation**: Resource limits, queueing, intelligent scheduling

3. **External Service Dependencies**
   - **Risk**: Tests requiring external services (databases, message queues) failing
   - **Mitigation**: Docker Compose integration, service health checking, graceful degradation

4. **Browser Automation Instability**
   - **Risk**: WebSocket and browser testing being flaky
   - **Mitigation**: Retry mechanisms, timeout handling, headless mode configuration

### Future Improvements

1. **Dynamic Repository Addition**
   - Configuration system designed to support runtime repository addition
   - Plugin architecture for community-contributed repository configurations

2. **Advanced Performance Optimization**
   - Repository affinity grouping for better container reuse
   - Intelligent caching based on dependency similarity
   - Parallel analysis pipeline optimization

3. **Enhanced Specialization**
   - Domain-specific quality metrics (performance for Benchee, documentation for ExDoc)
   - Repository-type-specific pattern analysis enhancements
   - Custom evaluation criteria per repository category

### Integration Testing Strategy

1. **Repository Isolation Testing**
   - Each repository configuration tested in isolation
   - Verify no side effects on existing repositories

2. **Cross-Repository Compatibility**
   - Test combinations of repositories in same evaluation run
   - Ensure no resource conflicts or interference

3. **Analysis System Integration**
   - Verify pattern analysis works across all repository types
   - Confirm OTP validation applies appropriately
   - Validate static analysis integration
   - Test functional programming scoring accuracy

4. **Performance Impact Assessment**
   - Baseline performance testing with original 5 repositories
   - Progressive performance testing as repositories are added
   - Optimization point identification and resolution

### Monitoring and Observability

1. **Repository-Specific Metrics**
   - Success rates per repository type
   - Average analysis time per repository category
   - Resource utilization patterns

2. **Quality Metrics Tracking**
   - Task extraction success rates
   - Analysis coverage percentages
   - Quality score distributions

3. **System Health Monitoring**
   - Memory usage trends with expanded repository set
   - CPU utilization during diverse repository testing
   - I/O patterns for different repository types

---

**Implementation Status**: Planning Complete - Ready for Implementation  
**Estimated Implementation Time**: 18 days  
**Resource Requirements**: 32GB RAM, 8+ CPU cores, 500GB storage  
**Dependencies**: All external system requirements documented above