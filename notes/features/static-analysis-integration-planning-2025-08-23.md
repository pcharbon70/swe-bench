# Static Analysis Integration (Credo & Dialyzer) Planning Document

## Phase 2.4 Implementation Plan - Static Analysis Integration

**Created:** 2025-08-23  
**Feature:** Phase 2.4 Static Analysis Integration (Credo & Dialyzer)  
**Status:** Planning Phase

---

## 1. Problem Statement

The SWE-bench evaluation system currently relies primarily on test execution for evaluating code quality, but lacks comprehensive static analysis capabilities. To provide multi-dimensional quality metrics and graduated scoring beyond simple test passage, we need to integrate industry-standard Elixir static analysis tools (Credo and Dialyzer) into the evaluation pipeline.

### Key Requirements:
- **Credo Integration**: Code quality analysis with strict configuration, issue categorization, metrics extraction, and scoring
- **Dialyzer Integration**: Type checking with PLT building, type analysis, warning categorization, spec violations detection, and type safety scoring  
- **Warning Aggregation**: Collection, deduplication, prioritization, location mapping, and comprehensive reporting of all static analysis findings
- **Quality Metrics**: Calculation of complexity, duplication, documentation coverage, naming conventions, and overall quality scoring
- **Pipeline Integration**: Seamless integration with existing container-based evaluation system and GenStage pipeline architecture

### Impact on System:
- Provides additional quality dimensions beyond test results
- Enables graduated scoring for partial credit evaluation
- Improves evaluation accuracy for functional programming practices
- Supports the expansion to 15 repositories with diverse codebases
- Enhances the benchmark's ability to assess real-world code quality

---

## 2. Solution Overview

The static analysis integration follows a modular architecture that extends the existing evaluation pipeline with four core components:

### High-Level Architecture:
1. **Credo Analyzer**: Configures and executes Credo analysis with strict settings, categorizes issues by severity, and calculates readability/complexity scores
2. **Dialyzer Integration**: Manages PLT file lifecycle, executes type analysis, categorizes warnings, and computes type safety metrics
3. **Warning Aggregator**: Centralizes collection of all static analysis findings, deduplicates similar issues, prioritizes by impact, and maps to source locations
4. **Quality Metrics Calculator**: Computes comprehensive quality metrics including cyclomatic complexity, code duplication, documentation coverage, and naming convention adherence

### Key Design Decisions:
- **Container-based Execution**: Static analysis runs within the existing Docker container infrastructure for consistency and isolation
- **Asynchronous Processing**: Integration with GenStage pipeline for concurrent analysis alongside test execution
- **Database Integration**: New Ash resources for storing static analysis results with proper relationships to evaluations
- **Caching Strategy**: PLT files and analysis results cached for performance optimization
- **Graduated Scoring**: Multi-dimensional scoring system that awards partial credit for good practices even when tests fail

---

## 3. Agent Consultations Performed

### Elixir Expert Consultation Results:
**Key Insights on Credo & Dialyzer Integration:**
- Credo configurations should use strict preset with custom rules for functional programming patterns
- PLT building requires careful dependency management in containerized environments  
- Dialyzer warnings should be categorized by severity: error, warning, info levels
- Performance considerations: PLT building is expensive but cacheable across evaluations
- Version compatibility: Both tools need to match Elixir version in containers

**Best Practices Identified:**
- Use `.credo.exs` configuration files for consistent analysis
- Implement incremental PLT updates to reduce rebuild times
- Handle OTP application-specific Dialyzer configurations
- Filter false positives through configurable warning suppression
- Parallel analysis execution to avoid blocking the evaluation pipeline

### Research Agent Consultation Results:
**Static Analysis Methodologies:**
- Industry standard metrics: cyclomatic complexity, Halstead complexity, maintainability index
- Code duplication detection using token-based and semantic analysis
- Documentation coverage metrics including spec coverage and module documentation
- Quality scoring algorithms based on weighted composite metrics

**Evaluation Strategies:**
- Baseline establishment through analysis of high-quality Elixir codebases
- Threshold determination for graduated scoring tiers (25%, 50%, 75%, 100%)
- Cross-repository normalization for consistent scoring across different project types
- Integration with existing pattern matching and OTP validation scores

### Senior Engineer Reviewer Consultation Results:
**System Architecture Review:**
- Integration points clearly defined with existing GenStage pipeline stages
- Database schema properly extends current Ash resource model
- Container resource allocation adequate for additional analysis workload
- Error handling strategies appropriate for production deployment

**Integration Considerations:**
- Backwards compatibility maintained with existing evaluation API
- Performance impact minimized through asynchronous processing and caching
- Monitoring and observability integrated with existing telemetry infrastructure
- Graceful degradation when static analysis tools are unavailable

---

## 4. Technical Details

### 4.1 File Structure and Components

```
lib/swe_bench/static_analysis/
├── credo_analyzer.ex          # Main Credo integration module
├── dialyzer_integration.ex    # Dialyzer PLT management and analysis
├── warning_aggregator.ex      # Centralized warning collection and processing
├── quality_calculator.ex      # Quality metrics computation
├── config_manager.ex          # Analysis tool configuration management
└── cache_manager.ex           # PLT and result caching

lib/swe_bench/static_analysis/metrics/
├── complexity_calculator.ex   # Cyclomatic complexity analysis
├── duplication_detector.ex    # Code duplication detection
├── documentation_analyzer.ex  # Documentation coverage analysis
└── naming_analyzer.ex         # Naming convention validation

lib/swe_bench/static_analysis/schemas/
├── analysis_result.ex         # Ash resource for analysis results
├── credo_finding.ex           # Ash resource for Credo findings  
├── dialyzer_warning.ex        # Ash resource for Dialyzer warnings
└── quality_metric.ex          # Ash resource for quality metrics
```

### 4.2 Database Schema Design

```elixir
# Analysis Result Resource
defmodule SweBench.StaticAnalysis.AnalysisResult do
  use Ash.Resource, data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :evaluation_id, :uuid, allow_nil?: false
    attribute :analysis_type, :atom, allow_nil?: false  # :credo, :dialyzer, :composite
    attribute :overall_score, :decimal, allow_nil?: false
    attribute :execution_time_ms, :integer, allow_nil?: false
    attribute :tool_version, :string, allow_nil?: false
    attribute :configuration_hash, :string, allow_nil?: false
    timestamps()
  end

  relationships do
    belongs_to :evaluation, SweBench.Evaluation
    has_many :credo_findings, SweBench.StaticAnalysis.CredoFinding
    has_many :dialyzer_warnings, SweBench.StaticAnalysis.DialyzerWarning
    has_many :quality_metrics, SweBench.StaticAnalysis.QualityMetric
  end
end
```

### 4.3 Integration Points

**Container Integration:**
- Extend `SweBench.Container.Executor` to include static analysis execution phase
- Modify Docker images to include Credo and Dialyzer with appropriate configurations
- Add PLT management to container lifecycle for Dialyzer optimization

**Pipeline Integration:**
- New GenStage consumer: `SweBench.Pipeline.StaticAnalyzer`
- Parallel processing with existing test execution stage
- Results aggregation in `SweBench.Pipeline.ResultAnalyzer`

**Evaluation Integration:**
- Extend evaluation results schema to include static analysis dimensions
- Update scoring algorithm to incorporate static analysis metrics
- Maintain backwards compatibility with existing evaluation API

### 4.4 Dependencies and Configuration

**Required Dependencies** (already present in mix.exs):
- `credo: "~> 1.7"` - Code quality analysis
- `dialyxir: "~> 1.3"` - Dialyzer integration wrapper

**Configuration Files:**
- `.credo.exs` - Strict Credo configuration template
- `dialyzer.config` - Dialyzer warning configuration
- Container environment variables for tool versions and paths

**Resource Requirements:**
- Additional 512MB memory per container for PLT files
- Disk space for PLT caching (~100MB per Elixir version)
- CPU overhead: ~20% increase in evaluation time

---

## 5. Success Criteria

### 5.1 Functional Requirements
- [ ] **Credo Analysis Execution**: Successfully analyze code with strict configuration and categorize issues by severity
- [ ] **Dialyzer Type Checking**: Build PLT files and execute type analysis with proper warning categorization
- [ ] **Warning Aggregation**: Collect, deduplicate, and prioritize all static analysis findings
- [ ] **Quality Metrics**: Calculate comprehensive quality scores including complexity, duplication, documentation, and naming
- [ ] **Pipeline Integration**: Seamlessly integrate with GenStage pipeline without performance degradation

### 5.2 Performance Requirements  
- [ ] **Analysis Speed**: Complete static analysis within 2x test execution time
- [ ] **PLT Caching**: Achieve >90% cache hit rate for PLT files across evaluations
- [ ] **Memory Efficiency**: Keep memory overhead under 512MB per evaluation container
- [ ] **Concurrent Processing**: Support parallel static analysis with test execution
- [ ] **Throughput Maintenance**: Maintain pipeline throughput of ≥500 tasks/hour with static analysis enabled

### 5.3 Quality Requirements
- [ ] **Scoring Accuracy**: Graduated scoring correctly differentiates between quality levels
- [ ] **Cross-Repository Consistency**: Scoring normalized appropriately across different project types  
- [ ] **False Positive Rate**: <5% false positive rate for critical issues
- [ ] **Coverage**: Analysis covers 100% of patched code files
- [ ] **Reliability**: <1% failure rate for static analysis execution

### 5.4 Integration Requirements
- [ ] **Database Persistence**: All analysis results properly stored with relationships
- [ ] **API Compatibility**: Existing evaluation API remains functional with additional static analysis data
- [ ] **Monitoring Integration**: Static analysis metrics included in telemetry and health checks
- [ ] **Error Handling**: Graceful degradation when static analysis tools fail
- [ ] **Configuration Management**: Tool configurations properly versioned and managed

---

## 6. Implementation Plan

### Phase 1: Core Infrastructure (Week 1)
**Step 1.1: Database Schema Implementation**
- Create Ash resources for analysis results, findings, warnings, and metrics
- Implement database migrations for new tables and relationships
- Add indexes for performance optimization
- Test data persistence and retrieval

**Step 1.2: Configuration Management**  
- Implement `SweBench.StaticAnalysis.ConfigManager`
- Create strict Credo configuration template (`.credo.exs`)
- Develop Dialyzer configuration management
- Add version compatibility checks

**Step 1.3: Container Integration Setup**
- Modify Docker images to include static analysis tools
- Update container resource allocation
- Implement tool availability verification
- Add configuration file mounting

### Phase 2: Credo Integration (Week 1-2)
**Step 2.1: Credo Analyzer Implementation**
- Implement `SweBench.StaticAnalysis.CredoAnalyzer` module
- Add configuration loading and validation
- Implement analysis execution and output parsing
- Create issue categorization logic

**Step 2.2: Credo Results Processing**
- Implement result parsing from Credo JSON output
- Create severity mapping and categorization
- Add code location mapping and context extraction
- Implement scoring algorithm based on findings

**Step 2.3: Testing and Validation**
- Unit tests for Credo analyzer with known code samples
- Integration tests with container execution
- Performance testing with large codebases
- Edge case handling (parsing errors, empty results)

### Phase 3: Dialyzer Integration (Week 2-3)
**Step 3.1: PLT Management System**
- Implement `SweBench.StaticAnalysis.DialyzerIntegration` module
- Create PLT building and caching logic
- Add dependency analysis for PLT requirements
- Implement incremental PLT updates

**Step 3.2: Type Analysis Execution**
- Implement Dialyzer execution with proper flags
- Add warning parsing and categorization
- Create type safety scoring algorithm
- Implement spec violation detection

**Step 3.3: Performance Optimization**
- Implement PLT caching with proper invalidation
- Add parallel PLT building for multiple Elixir versions
- Optimize memory usage during analysis
- Add timeout handling for long-running analysis

### Phase 4: Warning Aggregation and Quality Metrics (Week 3)
**Step 4.1: Warning Aggregator Implementation**
- Implement `SweBench.StaticAnalysis.WarningAggregator`
- Add deduplication logic for similar warnings
- Implement prioritization based on severity and impact
- Create comprehensive reporting format

**Step 4.2: Quality Metrics Calculator**
- Implement complexity calculation (cyclomatic, Halstead)
- Add code duplication detection algorithm
- Create documentation coverage analysis
- Implement naming convention validation

**Step 4.3: Composite Scoring System**
- Develop weighted scoring algorithm
- Implement graduated scoring tiers (25%, 50%, 75%, 100%)
- Add cross-repository normalization
- Create quality dimension breakdowns

### Phase 5: Pipeline Integration (Week 3-4)
**Step 5.1: GenStage Consumer Implementation**
- Create `SweBench.Pipeline.StaticAnalyzer` GenStage consumer
- Implement parallel processing with test execution
- Add backpressure handling and flow control
- Integrate with existing pipeline supervisor

**Step 5.2: Result Integration**
- Extend `SweBench.Pipeline.ResultAnalyzer` for static analysis results
- Update evaluation result aggregation
- Implement composite scoring with test results
- Add result caching and persistence

**Step 5.3: API Extension**
- Update evaluation API to include static analysis results
- Maintain backwards compatibility
- Add filtering and querying capabilities
- Implement result export formats

### Phase 6: Testing and Optimization (Week 4)
**Step 6.1: Integration Testing**
- End-to-end testing with complete pipeline
- Multi-repository testing across different project types
- Performance testing under load
- Error scenario testing

**Step 6.2: Performance Optimization**
- Profile memory usage and optimize allocation
- Benchmark analysis speed and identify bottlenecks
- Optimize database queries and indexes
- Implement result streaming for large evaluations

**Step 6.3: Monitoring and Observability**
- Add telemetry metrics for static analysis
- Implement health checks for analysis tools
- Create performance dashboards
- Add alerting for analysis failures

**Testing Integration:**
- Unit tests accompany each implementation step
- Integration tests validate end-to-end functionality
- Performance tests ensure scalability requirements
- Comprehensive error scenario testing

---

## 7. Notes/Considerations

### 7.1 Edge Cases and Challenges

**Tool Version Management:**
- Different Elixir versions may require different tool versions
- PLT compatibility across versions needs careful management
- Container image versioning strategy for tool updates

**Performance Considerations:**
- PLT building is CPU and memory intensive
- Large codebases may require analysis timeouts
- Concurrent analysis may impact container resource limits
- Cache invalidation strategy needs to balance accuracy and performance

**Error Handling Scenarios:**
- Credo/Dialyzer tool crashes or hangs during analysis
- Malformed or unparseable source code
- Missing dependencies during PLT building
- Insufficient container resources for analysis

### 7.2 Future Improvements

**Advanced Analysis Features:**
- Custom Credo checks for Elixir-specific patterns
- Integration with additional static analysis tools (Sobelow for security)
- Machine learning-based quality scoring refinements
- Cross-file dependency analysis for better context

**Performance Enhancements:**
- Distributed PLT building across multiple nodes
- Incremental analysis for partial code changes
- Result streaming for large-scale evaluations
- Advanced caching strategies with dependency tracking

**Integration Expansions:**
- IDE integration for development-time feedback
- CI/CD pipeline integration for continuous quality assessment
- Historical trend analysis and quality regression detection
- Integration with code review systems

### 7.3 Risk Mitigation

**Technical Risks:**
- **PLT Building Failures**: Implement fallback to basic analysis without full PLT
- **Tool Version Incompatibilities**: Version locking and compatibility matrix
- **Memory Exhaustion**: Resource monitoring and graceful degradation
- **Analysis Timeouts**: Configurable timeouts with partial results

**Operational Risks:**  
- **Container Resource Limits**: Monitoring and automatic scaling
- **Database Performance**: Query optimization and connection pooling
- **Cache Invalidation**: Proper versioning and consistency checks
- **Pipeline Bottlenecks**: Load balancing and horizontal scaling

**Quality Risks:**
- **False Positives**: Configurable suppression and community feedback
- **Scoring Bias**: Cross-repository validation and normalization
- **Tool Configuration Drift**: Version control and automated updates
- **Analysis Coverage Gaps**: Comprehensive testing across code patterns

### 7.4 Success Metrics and KPIs

**Quality Metrics:**
- Analysis accuracy: >95% correct issue identification
- False positive rate: <5% for critical findings  
- Coverage: 100% of modified code analyzed
- Consistency: <10% scoring variance across similar patterns

**Performance Metrics:**
- Analysis completion time: <2x test execution time
- PLT cache hit rate: >90%
- Memory overhead: <512MB per container
- Pipeline throughput: Maintain ≥500 tasks/hour

**Reliability Metrics:**
- Analysis success rate: >99%
- Tool availability: >99.9% uptime
- Container failure rate: <0.1%
- Data consistency: 100% result persistence

This comprehensive planning document provides a complete blueprint for implementing static analysis integration that seamlessly extends the existing SWE-bench evaluation system with sophisticated code quality analysis capabilities.