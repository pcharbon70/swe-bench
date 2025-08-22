# Phase 1.2: ExUnit Test Runner with Result Capture

## Problem Statement

The SWE-bench-Elixir evaluation system requires a sophisticated test execution engine that integrates deeply with ExUnit to capture structured, detailed test results. Traditional test runners lack the granular visibility needed for AI model evaluation, failing to provide:

1. **Structured Result Capture**: Detailed information about test failures, timing, and assertion types
2. **Deterministic Execution**: Consistent test results across multiple runs for reliable evaluation
3. **Process Isolation**: Proper cleanup between test executions to prevent state contamination
4. **Failure Analysis**: Deep insight into why tests failed, including stacktraces and assertion details
5. **Transition Detection**: Ability to detect FAIL_TO_PASS and PASS_TO_PASS transitions for evaluation scoring

The system must handle both synchronous and asynchronous test execution while maintaining deterministic results and providing comprehensive failure analysis for AI model benchmarking.

## Solution Overview

Implement a comprehensive ExUnit-based test execution system with four core components:

1. **Custom ExUnit Formatter**: GenServer-based formatter that captures detailed test execution data
2. **Test Execution Orchestrator**: Manages test execution with environment control and timeout handling
3. **Test Result Analyzer**: Processes results to detect transitions and generate evaluation metrics
4. **Test Isolation Mechanism**: Ensures clean state between test executions

The system integrates with the existing container infrastructure from Phase 1.1 to provide isolated, reproducible test execution environments.

## Agent Consultations Performed

**Note**: Following established methodologies from agent definitions:

- **Elixir-Expert Methodology**: Researched ExUnit internals, formatter implementation patterns, and test isolation techniques
- **Research-Agent Methodology**: Analyzed test execution frameworks, result capture patterns, and deterministic testing approaches
- **Architecture-Agent Methodology**: Designed integration with container system and evaluated architectural impact on existing codebase

## Technical Details

### Current Codebase Integration
- **Existing Infrastructure**: Phase 1.1 Docker containerization system
- **Integration Points**: Container.Executor module for test execution
- **Framework**: ExUnit as the core testing framework
- **Results Format**: JSON-structured output for programmatic analysis

### File Locations and Dependencies
- **Core Module**: `lib/swe_bench/test_runner/` directory structure
- **Formatter**: `lib/swe_bench/test_runner/formatter.ex` 
- **Orchestrator**: `lib/swe_bench/test_runner/orchestrator.ex`
- **Analyzer**: `lib/swe_bench/test_runner/analyzer.ex`
- **Isolation**: `lib/swe_bench/test_runner/isolation.ex`
- **Tests**: `test/swe_bench/test_runner/` comprehensive test suite
- **Integration**: Updates to `SweBench.Container.Executor` for test execution

### Key Dependencies
- **ExUnit**: Core testing framework (built into Elixir)
- **Jason**: JSON encoding/decoding for result serialization
- **GenServer**: Process management for formatter and orchestrator
- **Logger**: Structured logging for test execution events
- **System**: Process management and timeout handling

## Success Criteria

### Functional Requirements
- [ ] **Custom Formatter**: Captures all test execution details in structured format
- [ ] **Deterministic Execution**: Consistent results across multiple runs
- [ ] **Comprehensive Analysis**: Detailed failure analysis with stacktraces and timing
- [ ] **Transition Detection**: Accurate FAIL_TO_PASS and PASS_TO_PASS identification
- [ ] **Process Isolation**: Clean state between test executions
- [ ] **Timeout Handling**: Graceful handling of infinite loops and hanging tests
- [ ] **Coverage Metrics**: Test coverage calculation and reporting

### Performance Requirements
- [ ] **Execution Speed**: Test execution overhead < 10% compared to standard ExUnit
- [ ] **Memory Usage**: Formatter memory usage < 50MB during execution
- [ ] **Result Processing**: Result analysis completes in < 5 seconds
- [ ] **Isolation Speed**: State cleanup completes in < 2 seconds
- [ ] **Scalability**: Handles test suites with 1000+ tests efficiently

### Quality Requirements
- [ ] **Test Coverage**: 100% test coverage for all test runner components
- [ ] **Error Handling**: Robust error scenarios with graceful degradation
- [ ] **Documentation**: Complete API documentation with usage examples
- [ ] **Integration**: Seamless integration with Phase 1.1 container system
- [ ] **Reliability**: Zero data loss during test result capture

## Implementation Plan

### Phase 1.2.1: Create ExUnit Custom Formatter

- [ ] **1.2.1.1** Implement GenServer-based formatter
  - Create `SweBench.TestRunner.Formatter` GenServer module
  - Handle ExUnit formatter callbacks (suite_started, test_started, test_finished, etc.)
  - Maintain state for test execution tracking
  - Implement proper GenServer lifecycle management
  
- [ ] **1.2.1.2** Capture test module, name, and state
  - Extract test module names and function names
  - Track test state transitions (pending, running, passed, failed, skipped)
  - Record test tags and metadata
  - Capture test description and context information
  
- [ ] **1.2.1.3** Extract failure messages and stacktraces
  - Parse ExUnit failure structures for detailed error information
  - Extract assertion failure messages
  - Capture complete stacktraces with file/line information
  - Identify assertion types (assert, refute, assert_raise, etc.)
  
- [ ] **1.2.1.4** Identify assertion types from failures
  - Analyze assertion failure patterns
  - Categorize assertion types for evaluation metrics
  - Extract expected vs actual values from assertions
  - Track assertion complexity and patterns
  
- [ ] **1.2.1.5** Record test execution timing
  - Capture start and end times for each test
  - Calculate execution duration with microsecond precision
  - Track setup and teardown timing
  - Record total suite execution time

### Phase 1.2.2: Implement Test Execution Orchestrator

- [ ] **1.2.2.1** Configure Mix test environment variables
  - Set up proper Mix.env for test execution
  - Configure ExUnit for deterministic behavior
  - Set environment variables for consistent execution
  - Handle test-specific configuration requirements
  
- [ ] **1.2.2.2** Force synchronous execution for determinism
  - Configure ExUnit async: false for all tests
  - Implement synchronous test execution mode
  - Ensure predictable test execution order
  - Handle async test semantics appropriately
  
- [ ] **1.2.2.3** Preserve async test semantics through process isolation
  - Create isolated processes for async-marked tests
  - Maintain async test performance benefits where safe
  - Handle process cleanup after async test completion
  - Ensure proper message passing and synchronization
  
- [ ] **1.2.2.4** Handle test timeouts and infinite loops
  - Implement per-test timeout mechanisms
  - Detect and handle infinite loops in test code
  - Provide configurable timeout values
  - Generate timeout reports for evaluation analysis
  
- [ ] **1.2.2.5** Capture compilation errors during test runs
  - Intercept compilation errors before test execution
  - Parse compiler error messages and warnings
  - Generate structured compilation error reports
  - Handle partial compilation scenarios gracefully

### Phase 1.2.3: Build Test Result Analyzer

- [ ] **1.2.3.1** Parse FAIL_TO_PASS test transitions
  - Compare test results between base and patched code
  - Identify tests that transition from failing to passing
  - Generate detailed transition reports
  - Validate transition accuracy and consistency
  
- [ ] **1.2.3.2** Verify PASS_TO_PASS test stability
  - Ensure existing passing tests remain stable
  - Detect any regressions in previously passing tests
  - Generate stability reports for evaluation
  - Track test consistency across multiple runs
  
- [ ] **1.2.3.3** Detect test flakiness and non-determinism
  - Run tests multiple times to detect flaky behavior
  - Identify tests with inconsistent results
  - Generate flakiness reports and statistics
  - Filter out flaky tests from evaluation results
  
- [ ] **1.2.3.4** Calculate test coverage metrics
  - Integrate with ExCoveralls for coverage analysis
  - Generate line and function coverage reports
  - Track coverage changes with patch application
  - Provide coverage-based evaluation metrics
  
- [ ] **1.2.3.5** Generate structured JSON reports
  - Create standardized JSON format for test results
  - Include all captured metadata and analysis
  - Ensure JSON schema compatibility
  - Support incremental result updates

### Phase 1.2.4: Create Test Isolation Mechanism

- [ ] **1.2.4.1** Reset application state between tests
  - Clear application environment variables
  - Reset application configuration
  - Handle application supervision tree cleanup
  - Ensure clean application startup state
  
- [ ] **1.2.4.2** Clear ETS tables and process registry
  - Identify and clean up ETS tables created during tests
  - Clear process registry entries
  - Handle named processes and cleanup
  - Ensure proper ETS table ownership transfer
  
- [ ] **1.2.4.3** Handle database transaction rollbacks
  - Implement database state isolation using transactions
  - Handle database connection cleanup
  - Ensure test data doesn't persist between runs
  - Support multiple database adapters
  
- [ ] **1.2.4.4** Manage GenServer state cleanup
  - Identify GenServer processes started during tests
  - Implement proper GenServer termination
  - Handle GenServer state persistence issues
  - Ensure clean GenServer startup for subsequent tests
  
- [ ] **1.2.4.5** Ensure supervisor tree restart
  - Restart application supervision trees between tests
  - Handle supervisor child specifications
  - Manage application startup dependencies
  - Verify complete supervision tree cleanup

### Testing Implementation Plan

- [ ] **Unit Tests**: Test each component in isolation
  - ExUnit formatter callback handling
  - Test execution orchestration logic
  - Result analysis algorithms
  - Isolation mechanism effectiveness
  
- [ ] **Integration Tests**: Test component interactions
  - End-to-end test execution with result capture
  - Container integration with test runner
  - Multi-test execution with isolation
  - Error handling and recovery scenarios
  
- [ ] **Performance Tests**: Validate performance requirements
  - Formatter overhead measurement
  - Large test suite execution performance
  - Memory usage during test execution
  - Isolation mechanism performance impact

## Notes/Considerations

### Edge Cases and Potential Issues
- **ExUnit Formatter Lifecycle**: Proper formatter startup/shutdown coordination
- **Process Cleanup**: Ensuring all processes are properly terminated
- **Memory Leaks**: Preventing memory accumulation during long test runs
- **Test Dependencies**: Handling tests that depend on external services
- **Async Test Isolation**: Maintaining isolation while preserving async benefits

### Future Improvements
- **Parallel Test Execution**: Support for parallel test execution across containers
- **Test Result Caching**: Caching test results for repeated evaluations
- **Advanced Coverage**: Branch and condition coverage analysis
- **Performance Profiling**: Integration with performance profiling tools
- **Visual Test Reports**: HTML reports with detailed test analysis

### Risk Assessment
- **High Risk**: ExUnit formatter integration complexity may require extensive testing
- **Medium Risk**: Process isolation may impact test execution performance
- **Low Risk**: JSON result serialization is well-established pattern

### Integration Considerations
- **Container System**: Must integrate with Phase 1.1 container execution
- **Future Phases**: Should support GenStage pipeline integration from Phase 1.6
- **Existing Tests**: Must work with current project test structure
- **Mix Integration**: Should work seamlessly with Mix test commands

## Status Tracking

### Current Progress: Planning Phase Complete ✅
- [x] Problem analysis and requirements gathering
- [x] Solution architecture design
- [x] Technical specification creation
- [x] Implementation plan development
- [x] Success criteria definition

### Next Steps
1. Begin implementation of ExUnit custom formatter (1.2.1)
2. Set up test runner module structure
3. Create initial GenServer-based formatter
4. Integrate with container execution system

### How to Run Development Environment
```bash
# Ensure Phase 1.1 container system is available
cd /home/ducky/code/swe_bench
mix deps.get
mix compile

# Test container system integration
iex -S mix
SweBench.Container.start_link()

# Run existing tests to validate environment
mix test
```

This planning document provides the comprehensive foundation for implementing Phase 1.2 of the SWE-bench-Elixir test execution infrastructure, ensuring seamless integration with the existing container system while providing sophisticated test result capture and analysis capabilities.