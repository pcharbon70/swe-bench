# Phase 3.4: Task Instance Generator - Feature Planning

**Date:** 2025-08-25  
**Branch:** feature/phase-3.4-task-instance-generator  
**Phase:** 3.4 - Task Instance Generator  
**Status:** 🚧 **PLANNING COMPLETE - READY FOR IMPLEMENTATION**

## 1. Problem Statement

### **Challenge**
SWE-bench-Elixir requires a standardized task instance generation system that transforms validated issue-PR pairs into high-quality benchmark tasks compatible with SWE-bench format while adding sophisticated Elixir-specific enhancements. Currently, there is no automated system for creating standardized benchmark task instances from the comprehensive validation data produced by Phase 3.1-3.3.

### **Impact Analysis**
- **Without Phase 3.4**: Cannot create usable benchmark tasks for AI model evaluation
- **Business Impact**: No standardized output format prevents benchmark adoption and usage
- **Technical Debt**: Manual task generation doesn't scale to hundreds of validated instances
- **User Experience**: Inconsistent task format affects research reproducibility and model comparison

### **Success Metrics**
- Generate **500+ high-quality task instances** from validated issue-PR pairs
- Achieve **100% SWE-bench format compliance** with Elixir-specific extensions
- Maintain **100+ instances/hour** generation throughput
- Provide **95%+ quality validation** with comprehensive enrichment metadata

## 2. Solution Overview

### **High-Level Approach**
Implement a comprehensive Task Instance Generator that creates standardized SWE-bench task instances from validated test transition data, enriching them with sophisticated Elixir-specific metadata including AST analysis, OTP behavior detection, complexity assessment, and quality classification. The system will produce versioned dataset releases with compression and integrity validation.

### **Key Architectural Decisions**
1. **SWE-bench Format Compliance**: Maintain backward compatibility with standard tooling while adding Elixir extensions
2. **Streaming Processing**: Memory-efficient generation using stream processing for large datasets
3. **AST-Based Enrichment**: Sophisticated code analysis using Sourceror and existing analysis infrastructure
4. **Quality-Driven Packaging**: Multi-tier quality assessment with automated dataset release management
5. **GenStage Integration**: Seamless integration with existing parallel pipeline infrastructure

## 3. Agent Consultations Performed

### **Research Agent Consultation**
**Focus**: Task instance generation technologies and SWE-bench format compliance  
**Key Findings**:
- **SWE-bench Format**: Official schema requirements with JSON serialization standards
- **Compression Strategies**: Intelligent compression for large patch content and metadata
- **Performance Patterns**: Streaming JSON serialization with memory management
- **Dataset Packaging**: Versioning and release management for benchmark datasets
- **Quality Assurance**: Validation patterns for ensuring format compliance and data integrity

### **Elixir Expert Consultation**  
**Focus**: Elixir/OTP patterns and existing infrastructure integration  
**Key Recommendations**:
- **Ash Resource Design**: TaskInstance resource with JSONB optimization and GIN indexes
- **GenStage Integration**: Producer-consumer pattern integrated with existing pipeline
- **AST Analysis**: Sourceror integration leveraging existing pattern analysis infrastructure
- **Streaming Processing**: Memory-efficient patterns for large dataset generation
- **Custom Jason Encoders**: Optimized JSON serialization for large task instances

### **Senior Engineer Reviewer Consultation**
**Focus**: Production readiness and scalability validation  
**Key Insights**:
- **Streaming Architecture**: Critical for handling 1000+ instances efficiently
- **Memory Management**: Need sophisticated memory management for concurrent processing
- **Database Optimization**: JSONB with GIN indexes essential for performance
- **Quality Gates**: Comprehensive validation pipeline for production-ready instances

## 4. Technical Details

### **File Structure and Dependencies**
```
lib/swe_bench/
├── task_instances/
│   ├── task_instance.ex             # Ash resource for task instance data
│   ├── generation_job.ex            # Ash resource for generation jobs
│   ├── quality_metrics.ex           # Task-specific quality metrics
│   └── dataset_release.ex           # Versioned dataset releases
├── task_generation/
│   ├── supervisor.ex                # OTP supervision tree
│   ├── coordinator.ex              # Generation job coordination
│   ├── generator.ex                # Core instance generation logic
│   ├── enricher.ex                 # Metadata enrichment and AST analysis
│   ├── complexity_analyzer.ex       # Complexity assessment and classification
│   ├── formatter.ex                # SWE-bench format compliance
│   ├── packager.ex                 # Dataset packaging and compression
│   └── quality_validator.ex        # Comprehensive quality validation
└── tasks.ex                        # Domain module and main interface
```

### **Core Dependencies**
- **Existing**: Ash resources, GenStage pipeline, Sourceror, Jason, existing analysis infrastructure
- **Enhanced**: Custom JSON encoders, compression utilities, dataset versioning
- **New**: Dataset packaging and release management capabilities

### **Database Schema**
```sql
-- Task instances table with optimized storage
CREATE TABLE task_instances (
  id UUID PRIMARY KEY,
  instance_id VARCHAR(200) UNIQUE NOT NULL,
  repository_id UUID REFERENCES repositories(id) NOT NULL,
  issue_pr_link_id UUID REFERENCES issue_pr_links(id) NOT NULL,
  validation_result_id UUID REFERENCES validation_results(id) NOT NULL,
  base_commit_sha VARCHAR(40) NOT NULL,
  problem_statement TEXT NOT NULL,
  patch_content_compressed BYTEA,
  patch_content_size INTEGER,
  task_metadata JSONB DEFAULT '{}',
  evaluation_metadata JSONB DEFAULT '{}',
  quality_tier VARCHAR(10) NOT NULL,
  difficulty_level VARCHAR(10) DEFAULT 'medium',
  packaging_status VARCHAR(20) DEFAULT 'draft',
  content_checksum VARCHAR(64),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Performance indexes
CREATE INDEX CONCURRENTLY idx_task_instances_quality_repository 
ON task_instances (repository_id, quality_tier, difficulty_level);

CREATE INDEX CONCURRENTLY idx_task_instances_packaging_ready 
ON task_instances (packaging_status, quality_tier) 
WHERE packaging_status = 'ready';

-- JSONB indexes for metadata queries
CREATE INDEX CONCURRENTLY idx_task_instances_metadata_gin 
ON task_instances USING gin (task_metadata);
```

## 5. Success Criteria

### **Functional Requirements**
- ✅ **Instance Generation**: Create standardized task instances from validation results
- ✅ **Format Compliance**: Full SWE-bench format compliance with Elixir-specific extensions
- ✅ **Metadata Enrichment**: AST-based analysis with function changes, OTP patterns, complexity metrics
- ✅ **Quality Assessment**: Multi-tier quality classification with comprehensive validation
- ✅ **Dataset Packaging**: Versioned dataset releases with compression and integrity validation

### **Technical Requirements**
- ✅ **Performance**: Generate 100+ instances/hour with comprehensive enrichment
- ✅ **Memory Efficiency**: Stream processing for datasets with 1000+ instances
- ✅ **Integration**: Seamless integration with existing Phase 3.1-3.3 infrastructure
- ✅ **Monitoring**: Comprehensive metrics and quality tracking
- ✅ **Scalability**: Linear scaling with validation result input volume

### **Quality Requirements**
- ✅ **SWE-bench Compatibility**: 100% compatibility with existing SWE-bench tooling
- ✅ **Data Integrity**: Checksum validation and content verification
- ✅ **Documentation**: Comprehensive instance documentation and metadata
- ✅ **Testing**: 90%+ test coverage with integration and performance tests

## 6. Implementation Plan

### **Phase 1: Core Infrastructure (2-3 days)**
- [ ] **6.1.1** Create task instance generator supervisor with OTP supervision tree
- [ ] **6.1.2** Implement TaskInstance Ash resource with JSONB optimization
- [ ] **6.1.3** Create TaskInstances domain with proper configuration
- [ ] **6.1.4** Set up basic generation coordinator and worker structure

### **Phase 2: Instance Generation Engine (3-4 days)**  
- [ ] **6.2.1** Implement core generator with validation result processing
- [ ] **6.2.2** Create SWE-bench format compliance and serialization
- [ ] **6.2.3** Add streaming processing for memory-efficient generation
- [ ] **6.2.4** Implement comprehensive error handling and recovery

### **Phase 3: Metadata Enrichment (2-3 days)**
- [ ] **6.3.1** Create AST-based code enricher using Sourceror
- [ ] **6.3.2** Implement complexity analyzer with multi-dimensional assessment
- [ ] **6.3.3** Add OTP behavior detection and pattern change analysis
- [ ] **6.3.4** Integrate with existing static and functional analysis infrastructure

### **Phase 4: Quality Assessment and Validation (2-3 days)**
- [ ] **6.4.1** Create comprehensive quality validator for SWE-bench compliance
- [ ] **6.4.2** Implement instance integrity validation with checksum verification
- [ ] **6.4.3** Add quality tier classification and difficulty assessment
- [ ] **6.4.4** Build validation pipeline with automated quality gates

### **Phase 5: Dataset Packaging and Versioning (1-2 days)**
- [ ] **6.5.1** Implement dataset packager with compression and versioning
- [ ] **6.5.2** Create release management with semantic versioning
- [ ] **6.5.3** Add dataset bundling with integrity validation
- [ ] **6.5.4** Implement export capabilities for various formats

### **Phase 6: Integration and Testing (2-3 days)**
- [ ] **6.6.1** Integrate with existing GenStage pipeline from Phase 2.8
- [ ] **6.6.2** Create comprehensive integration tests with real validation data
- [ ] **6.6.3** Add performance benchmarks and load testing
- [ ] **6.6.4** Resolve all Credo issues and ensure clean compilation

## 7. Testing Strategy

### **Unit Testing**
- **Instance Generation**: Test creation of task instances from validation data
- **Format Compliance**: Test SWE-bench format compatibility with various data types
- **Metadata Enrichment**: Test AST analysis and complexity assessment accuracy
- **Quality Validation**: Test quality assessment rules and tier classification

### **Integration Testing**
- **Pipeline Integration**: Test complete workflow from validation results to task instances
- **Performance Testing**: Test memory usage and throughput with large datasets
- **Format Compatibility**: Test compatibility with existing SWE-bench tooling
- **End-to-End Validation**: Test complete dataset generation and packaging

### **Production Testing**
- **Load Testing**: Validate performance with 500+ concurrent instance generation
- **Quality Validation**: Verify instance quality with manual validation samples
- **Compatibility Testing**: Test with official SWE-bench evaluation tools

## 8. Notes and Considerations

### **Risk Mitigation**
- **Memory Management**: Streaming processing to handle large datasets efficiently
- **Format Compatibility**: Backward compatibility layer for SWE-bench ecosystem integration
- **Data Integrity**: Comprehensive checksum validation and content verification
- **Performance Optimization**: Database optimization and intelligent caching for large-scale generation

### **Future Enhancements**
- **Machine Learning**: Enhanced complexity assessment using ML models
- **Advanced Compression**: Specialized compression algorithms for code content
- **Real-time Generation**: Live instance generation from repository updates
- **Quality Enhancement**: Community feedback integration for instance improvement

### **Integration Opportunities**
- **Phase 3.1-3.3 Pipeline**: Leverage complete validation pipeline for input data
- **Phase 2 Analysis**: Use existing pattern, static, and functional analysis for enrichment
- **Container Infrastructure**: Leverage existing container pool for isolated generation
- **Pipeline Metrics**: Extend existing monitoring for comprehensive generation tracking

## 9. Implementation Status

### **Current Status**
- ✅ **Planning Complete**: Comprehensive plan with expert consultations
- ✅ **Architecture Validated**: Senior engineering review completed with production recommendations
- ✅ **Research Complete**: All necessary technologies and integration patterns identified
- 🚧 **Implementation Pending**: Ready to begin systematic implementation

### **Next Steps**
1. Begin with Phase 1: Core Infrastructure development
2. Implement and test each phase incrementally
3. Maintain continuous integration with existing Phase 3.1-3.3 infrastructure
4. Update this plan as implementation progresses

### **Success Dependencies**
- Integration with existing validation results from Phase 3.3
- Proper AST analysis integration with existing pattern analysis infrastructure
- Database optimization for large-scale instance storage and querying
- Comprehensive testing with SWE-bench format validation

---

**Ready for Implementation**: This plan provides comprehensive guidance for implementing Phase 3.4 Task Instance Generator with proper expert consultation, architectural validation, and clear implementation steps building on the successful Phase 3.1-3.3 foundations.