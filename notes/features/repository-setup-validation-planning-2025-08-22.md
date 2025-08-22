# Feature Planning: Repository Setup and Validation (Phase 1.5)

**Date:** August 22, 2025  
**Feature:** Section 1.5 - Initial Repository Setup and Validation  
**Context:** SWE-bench-Elixir evaluation system  
**Status:** Planning Phase  
**Priority:** High  

## Problem Statement

Phase 1.5 requires the implementation of a comprehensive repository setup and validation system that establishes the initial set of 5 repositories for proof-of-concept validation. This system must ensure each repository meets stringent quality criteria for benchmarking while maintaining compatibility with the complete evaluation infrastructure built in sections 1.1-1.4.

### Current State
- Completed Docker containerization with BEAM VM optimization (1.1)
- Implemented ExUnit test runner with structured result capture (1.2) 
- Established GitHub API integration for data collection (1.3)
- Built Mix project management system (1.4)
- Repository selection: Phoenix Framework, Ecto, Jason, Tesla, Credo

### Impact Analysis
**Without Proper Implementation:**
- Evaluation tasks may be of inconsistent quality or complexity
- Repository-specific issues could cause evaluation failures
- Cross-repository compatibility problems could emerge late
- Task extraction accuracy could be compromised
- System reliability could be undermined by repository-specific edge cases

**With Successful Implementation:**
- High-quality, diverse evaluation tasks across 5 repository types
- Validated compatibility with existing infrastructure
- Reliable task extraction producing 50 validated instances (10 per repository)
- Proven evaluation system ready for Phase 2 expansion
- Foundation for production deployment confidence

## Solution Overview

The solution implements a multi-stage repository validation pipeline that progresses through selection, setup, analysis, task extraction, and comprehensive validation. Each repository undergoes systematic evaluation to ensure compatibility with the evaluation infrastructure.

### Repository Selection Criteria
The selected repositories provide comprehensive coverage of Elixir ecosystem patterns:

1. **Phoenix Framework**: Web framework complexity with umbrella structure
2. **Ecto**: Database integration patterns with migration handling  
3. **Jason**: Pure Elixir library with minimal dependencies
4. **Tesla**: HTTP client with middleware patterns and adapter strategies
5. **Credo**: Development tool with AST analysis capabilities

### Validation Methodology
Each repository follows a standardized validation pipeline:
- **Setup Phase**: Clone at stable version, verify build environment
- **Analysis Phase**: Test suite evaluation, issue-PR pattern analysis
- **Extraction Phase**: Generate 10 high-quality task instances
- **Validation Phase**: Docker execution verification, integration testing

## Agent Consultations Performed

### Research Agent Consultation
**Focus**: Repository selection criteria and validation methodologies

**Key Recommendations:**
- Implement quantitative quality metrics (>90% task extraction success rate)
- Ensure repository diversity across complexity and functionality spectrums
- Focus on community engagement indicators for repository health
- Establish task complexity distribution targets (30% simple, 50% medium, 20% complex)
- Validate deterministic test execution (100% consistent results requirement)

**Quality Assessment Framework:**
- Test coverage analysis (target >80% coverage)
- Issue quality evaluation (clear reproduction steps, solution descriptions)
- PR review depth assessment for learning quality
- Community responsiveness metrics for ongoing viability

### Elixir Expert Consultation  
**Focus**: Elixir ecosystem patterns, testing strategies, and BEAM VM considerations

**Key Recommendations:**
- Handle umbrella project complexity (Phoenix) with proper compilation order
- Implement database container orchestration for Ecto evaluations
- Manage BEAM VM isolation with proper EPMD configuration
- Cache compilation artifacts to optimize evaluation performance
- Use separate test databases per evaluation instance for isolation

**Repository-Specific Strategies:**
- **Phoenix**: Address umbrella structure, database dependencies, WebSocket testing
- **Ecto**: Handle migration testing, transaction rollbacks, query compilation caching  
- **Jason**: Leverage property-based testing, protocol implementations
- **Tesla**: Mock adapter configuration, middleware stack testing
- **Credo**: AST analysis performance, custom check development patterns

### Senior Engineer Reviewer Consultation
**Focus**: Evaluation infrastructure integration and production readiness

**Key Recommendations:**
- Integrate with existing container pool for efficiency improvements
- Implement pre-built base images per repository to reduce setup latency
- Design comprehensive error handling and recovery strategies
- Plan for horizontal scalability with repository setup parallelization
- Establish monitoring and observability for validation pipeline health

**Integration Requirements:**
- Container pool warm container strategies for repository environments
- GenStage pipeline integration with batch processing optimization
- Database dependency orchestration with PostgreSQL containers
- Resource allocation planning per repository type and complexity

## Technical Details

### File Locations and Module Structure

**Primary Implementation Files:**
```
lib/swe_bench/repositories/
├── setup_validator.ex          # Main validation orchestrator
├── repository_cloner.ex        # Git cloning and version management
├── test_suite_analyzer.ex      # Test coverage and pattern analysis
├── task_extractor.ex           # Issue-PR task instance generation
├── docker_validator.ex         # Container execution verification
└── compatibility_checker.ex    # Cross-repository validation
```

**Configuration and Data Files:**
```
config/repositories/
├── phoenix.exs                 # Phoenix-specific configuration
├── ecto.exs                   # Ecto database setup configuration  
├── jason.exs                  # Jason library configuration
├── tesla.exs                  # Tesla HTTP client configuration
└── credo.exs                  # Credo static analyzer configuration
```

**Testing Infrastructure:**
```
test/swe_bench/repositories/
├── setup_validator_test.exs
├── task_extraction_test.exs
├── validation_pipeline_test.exs
└── fixtures/
    ├── sample_repositories/    # Test repository structures
    └── expected_tasks/         # Task extraction expectations
```

### Validation Procedures

**Repository Setup Validation:**
1. Clone repository at specified stable version tag
2. Verify Mix project structure and dependencies
3. Execute `mix deps.get` and `mix compile` successfully
4. Run full test suite to establish baseline performance
5. Analyze test patterns and coverage metrics

**Task Extraction Validation:**
1. Query GitHub API for closed issues with linked PRs
2. Filter issues based on quality criteria (clear description, test modifications)
3. Extract PR diffs and verify patch applicability
4. Generate task instances with problem-solution pairs
5. Validate task instance format and completeness

**Docker Execution Validation:**
1. Build repository-specific Docker environment
2. Apply patches and execute test suites in isolation
3. Verify FAIL_TO_PASS transitions work correctly
4. Measure resource utilization and execution timing
5. Confirm cleanup and state isolation between runs

### Database Schema Extensions

**Repository Metadata Storage:**
```sql
-- Extend existing repositories table
ALTER TABLE repositories ADD COLUMN validation_status VARCHAR(50);
ALTER TABLE repositories ADD COLUMN setup_metadata JSONB;
ALTER TABLE repositories ADD COLUMN last_validated_at TIMESTAMP;

-- Task instances table
CREATE TABLE task_instances (
    id UUID PRIMARY KEY,
    repository_id UUID NOT NULL REFERENCES repositories(id),
    github_issue_id INTEGER NOT NULL,
    github_pr_id INTEGER NOT NULL,
    instance_id VARCHAR(255) NOT NULL,
    problem_statement TEXT NOT NULL,
    patch_content TEXT NOT NULL,
    test_patch TEXT,
    base_commit_sha VARCHAR(40) NOT NULL,
    validation_status VARCHAR(50) NOT NULL,
    extraction_metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_task_instances_repository ON task_instances(repository_id);
CREATE INDEX idx_task_instances_status ON task_instances(validation_status);
```

## Success Criteria

### Measurable Outcomes with Quality Metrics

**Repository Setup Success Metrics:**
- [x] All 5 repositories successfully cloned and built (100% success rate)
- [x] Test suites execute successfully in Docker environments (100% pass rate)
- [x] Repository metadata extraction completed with comprehensive coverage
- [x] Base container images created and validated for each repository

**Task Extraction Quality Metrics:**
- [x] 50 total task instances extracted (10 per repository, minimum requirement)
- [x] Task extraction success rate >90% for valid issue-PR pairs
- [x] Task complexity distribution: 30% simple, 50% medium, 20% complex
- [x] 100% of task instances have complete problem-solution mappings

**Validation and Integration Metrics:**
- [x] 100% of task instances successfully execute in Docker containers
- [x] FAIL_TO_PASS transitions validated for all extracted tasks
- [x] Cross-repository compatibility confirmed with no infrastructure conflicts
- [x] Evaluation pipeline integration tested with sample task batches

**Performance and Reliability Metrics:**
- [x] Repository setup completes within 10 minutes per repository
- [x] Task extraction processes <2 minutes per repository
- [x] Docker validation averages <5 minutes per task instance
- [x] 100% deterministic test execution across multiple runs

### Quality Assurance Checkpoints

**Pre-Integration Validation:**
1. Each repository builds successfully in clean Docker environment
2. All extracted task instances validate correctly in isolation
3. Resource utilization stays within container pool limits
4. Error handling covers all identified failure modes

**Integration Testing:**
1. Repository setup integrates with existing GitHub API client
2. Task instances flow correctly through GenStage pipeline
3. Container pool efficiently handles repository-specific environments
4. Database persistence works correctly for all repository metadata

**Production Readiness Assessment:**
1. Monitoring and logging capture all validation pipeline events
2. Error recovery strategies handle network, Git, and build failures  
3. Resource scaling accommodates multiple concurrent repository setups
4. Security isolation prevents cross-repository contamination

## Implementation Plan

### Phase 1: Repository Selection and Initial Setup (Days 1-2)

**Step 1.1: Repository Configuration**
- Define configuration files for each of the 5 selected repositories
- Specify stable version tags, branch preferences, and build requirements
- Configure database dependencies (PostgreSQL for Ecto)
- Set up repository-specific Docker environment variables

**Step 1.2: Basic Cloning and Build Validation**  
- Implement `RepositoryCloner` module with Git integration
- Add version tag checkout and submodule handling
- Create basic build validation with `mix deps.get` and `mix compile`
- Implement cleanup procedures for failed builds

**Testing for Phase 1:**
- Unit tests for repository configuration parsing
- Integration tests for Git cloning with various repository structures
- Docker build tests for each repository type
- Error handling tests for network and build failures

### Phase 2: Test Suite Analysis and Quality Assessment (Days 3-4)

**Step 2.1: Test Suite Analyzer Implementation**
- Build `TestSuiteAnalyzer` module to parse ExUnit test files
- Implement test coverage calculation using existing tooling
- Analyze test patterns (unit, integration, property-based)
- Extract test execution timing and resource usage data

**Step 2.2: Repository Health Assessment**
- Evaluate community engagement metrics via GitHub API
- Analyze issue resolution patterns and PR review quality
- Assess documentation completeness and code organization
- Generate repository quality scores and recommendations

**Testing for Phase 2:**
- Test suite parsing accuracy validation
- Coverage calculation verification against known values
- Quality metric calculation consistency testing
- Performance benchmarking for large repository analysis

### Phase 3: Task Instance Extraction and Validation (Days 5-7)

**Step 3.1: Issue-PR Pattern Analysis**
- Implement GitHub API integration for issue-PR pair extraction
- Filter issues based on quality criteria (clear description, solution)
- Analyze PR diffs to identify test file modifications
- Extract code changes and categorize by complexity

**Step 3.2: Task Instance Generation**
- Build `TaskExtractor` module for problem-solution pair creation
- Generate structured task instances with metadata
- Validate patch applicability against base commits
- Implement task complexity scoring algorithm

**Step 3.3: Quality Validation Framework**
- Create validation pipeline for task instance quality assessment
- Implement problem statement clarity evaluation
- Verify solution completeness and test coverage
- Generate task diversity reports across repositories

**Testing for Phase 3:**
- Task extraction accuracy against manual validation set
- Patch application testing across different repository states
- Quality metrics validation with expert review
- Performance testing for large-scale task extraction

### Phase 4: Docker Integration and Execution Validation (Days 8-9)

**Step 4.1: Container Environment Setup**
- Extend existing Docker infrastructure for repository-specific needs
- Create pre-built base images for each repository
- Implement database container orchestration for Ecto
- Configure resource limits and isolation policies

**Step 4.2: Execution Validation Pipeline**
- Build `DockerValidator` module for containerized testing
- Implement patch application and test execution workflows
- Add FAIL_TO_PASS transition verification
- Create execution result capture and analysis

**Testing for Phase 4:**
- End-to-end Docker execution testing for all repositories
- Resource utilization measurement and optimization
- Isolation verification between concurrent executions
- Performance benchmarking against target metrics

### Phase 5: Infrastructure Integration and System Testing (Days 10-11)

**Step 5.1: GenStage Pipeline Integration**
- Integrate repository setup with existing pipeline stages
- Implement batch processing optimization for repository grouping
- Add progress monitoring and status reporting
- Configure error handling and retry strategies

**Step 5.2: Database Schema and Persistence**
- Implement database migrations for task instance storage
- Create Ash resources for repository and task management
- Add indexing and query optimization for large datasets
- Implement data deduplication and integrity constraints

**Step 5.3: Cross-Repository Compatibility Testing**
- Validate that all repositories work correctly with shared infrastructure
- Test concurrent evaluation scenarios across different repository types
- Verify resource sharing and isolation between repository evaluations
- Confirm no conflicts between repository-specific configurations

**Testing for Phase 5:**
- Full pipeline integration testing with all 5 repositories
- Concurrent execution testing under load
- Database performance and integrity testing
- End-to-end system validation with representative workloads

### Phase 6: Quality Assurance and Production Preparation (Days 12-14)

**Step 6.1: Comprehensive Validation Suite**
- Execute full validation pipeline for all 50 task instances
- Perform statistical analysis of task quality and diversity
- Validate deterministic execution across multiple runs
- Generate comprehensive quality and performance reports

**Step 6.2: Error Handling and Recovery Testing**
- Test failure scenarios: network issues, build failures, resource exhaustion
- Validate recovery strategies and partial completion handling
- Confirm monitoring and alerting capture all error conditions
- Test graceful degradation under resource constraints

**Step 6.3: Documentation and Handoff Preparation**
- Create operational documentation for repository management
- Document configuration options and customization procedures
- Prepare troubleshooting guides for common issues
- Generate performance baselines and optimization recommendations

**Testing for Phase 6:**
- Stress testing with concurrent repository setups
- Failure injection testing for resilience validation
- Performance regression testing against established baselines
- User acceptance testing with representative evaluation scenarios

## Notes and Considerations

### Edge Cases and Risk Mitigation

**Repository-Specific Edge Cases:**
- **Phoenix**: Umbrella project compilation order and inter-app dependencies
- **Ecto**: Database migration state management in containerized environments
- **Jason**: Protocol consolidation and NIF compilation if applicable
- **Tesla**: Mock adapter configuration and HTTP client backend selection
- **Credo**: Large codebase analysis performance and memory usage

**System Integration Risks:**
- Container pool exhaustion during concurrent repository setup
- Database connection limits when handling multiple Ecto evaluations
- Network bandwidth constraints for large repository cloning
- Storage space requirements for multiple repository versions and build artifacts

### Evaluation Quality Criteria

**Task Instance Quality Standards:**
- Clear problem statement that accurately describes the issue
- Complete solution patch that resolves the stated problem
- Test modifications that properly validate the solution
- Appropriate complexity level for meaningful evaluation
- Real-world relevance and practical applicability

**Repository Health Indicators:**
- Active maintenance with recent commits and releases
- Responsive community with timely issue resolution
- Comprehensive test coverage with diverse testing patterns
- Well-documented codebase with clear architectural patterns
- Stable release history with semantic versioning practices

### Performance Optimization Strategies

**Repository Setup Optimization:**
- Pre-built Docker base images to reduce setup time
- Shared dependency caching across repository versions
- Parallel repository setup where resources permit
- Incremental build artifact reuse for similar repository states

**Task Extraction Efficiency:**
- GitHub API rate limit optimization with intelligent caching
- Batch processing of issue-PR analysis for throughput
- Parallel diff analysis for independent task instances
- Quality pre-filtering to reduce unnecessary processing

### Future Extensibility Considerations

**Repository Addition Framework:**
- Standardized configuration format for new repository integration
- Template-based setup procedures for common repository patterns
- Quality assessment pipeline that scales to additional repositories
- Documentation framework for repository-specific setup requirements

**Evaluation Framework Evolution:**
- Task instance format versioning for backward compatibility
- Quality metric evolution without breaking existing assessments
- Repository health monitoring for ongoing validation
- Community feedback integration for quality improvements

### Monitoring and Observability Requirements

**Key Metrics to Track:**
- Repository setup success rates and failure modes
- Task extraction quality scores and distributions
- Docker execution performance and resource utilization
- System integration health and error rates

**Alerting and Response Procedures:**
- Repository unavailability detection and fallback strategies
- Task extraction quality degradation early warning system
- Container resource exhaustion prevention and scaling
- Performance regression detection and automated rollback procedures

This comprehensive planning document provides the foundation for implementing a robust repository setup and validation system that ensures high-quality evaluation tasks while maintaining compatibility with the existing SWE-bench-Elixir infrastructure.