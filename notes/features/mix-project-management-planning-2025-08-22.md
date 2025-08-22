# Mix Project Management System - Feature Planning Document

**Date**: 2025-08-22  
**Feature**: Section 1.4 - Mix Project Management System  
**Context**: SWE-bench-Elixir evaluation system Phase 1.4 implementation  
**Agent**: feature-planner  

---

## Problem Statement

The SWE-bench-Elixir evaluation system requires a sophisticated Mix project management infrastructure to handle the complexities of evaluating diverse Elixir projects in isolated, deterministic environments. Current implementation lacks comprehensive support for:

1. **Environment Isolation**: No deterministic Mix environment configuration with proper MIX_ENV, MIX_HOME, and HEX_HOME path management
2. **Dependency Resolution**: Missing robust mix.lock parsing, Hex package caching, and git dependency handling with conflict resolution
3. **Compilation Orchestration**: Absence of intelligent compilation order determination for umbrella projects, incremental compilation management, and protocol consolidation
4. **Project Structure Analysis**: Lack of automated project type detection (standard/umbrella/poncho), dependency mapping, and configuration parsing

### Impact Analysis

Without this system, the evaluation infrastructure faces:
- **Non-deterministic builds** leading to inconsistent evaluation results
- **Compilation failures** in complex umbrella projects with circular dependencies  
- **Performance degradation** from unnecessary full recompilation cycles
- **Evaluation errors** from incorrect project structure assumptions
- **Resource waste** from inefficient dependency management
- **Reliability issues** from environment variable conflicts between evaluations

---

## Solution Overview

The Mix Project Management System implements a four-component architecture providing comprehensive project lifecycle management:

### Design Decisions

1. **Isolated Environment Strategy**: Each evaluation gets dedicated MIX_HOME and HEX_HOME paths with deterministic compilation flags
2. **Dependency Resolution Engine**: Parse mix.lock files, implement local Hex caching, and resolve version conflicts using override mechanisms  
3. **Compilation Orchestrator**: Build dependency graphs for umbrella projects, manage incremental compilation state, and handle protocol consolidation
4. **Project Structure Analyzer**: Detect project types through mix.exs analysis, map inter-app dependencies, and parse configuration files

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mix Project Manager                           │
├─────────────────┬─────────────────┬─────────────────┬───────────┤
│   Environment   │   Dependency    │   Compilation   │  Project  │
│    Isolator     │    Manager      │  Orchestrator   │ Analyzer  │
├─────────────────┼─────────────────┼─────────────────┼───────────┤
│ • MIX_ENV       │ • mix.lock      │ • Umbrella      │ • Type    │
│ • MIX_HOME      │ • Hex caching   │   compilation   │   detect  │
│ • HEX_HOME      │ • Git deps      │ • Incremental   │ • Dep     │
│ • Deterministic │ • Version       │   builds        │   mapping │
│   flags         │   conflicts     │ • Protocol      │ • Config  │
│                 │                 │   consolidation │   parsing │
└─────────────────┴─────────────────┴─────────────────┴───────────┘
```

---

## Agent Consultations Performed

### Research Agent Consultation
**Topic**: Mix environment management and dependency resolution best practices

**Key Findings**:
- **Environment Variables**: MIX_HOME (default: `~/.mix`), MIX_ENV (dev/test/prod), MIX_BUILD_PATH for build isolation
- **Deterministic Builds**: Use `ERL_COMPILER_OPTIONS=deterministic` for reproducible compilation
- **Configuration Strategy**: Prefer runtime configuration in `config/runtime.exs` over build-time environment variables
- **Dependency Isolation**: Dependencies compiled in `:prod` environment regardless of host environment

**Recommendations**:
- Implement per-evaluation MIX_HOME directories for complete isolation
- Use deterministic compiler flags for reproducible evaluation results
- Separate build-time and runtime configuration management
- Cache dependencies at container layer for performance optimization

### Elixir Expert Consultation  
**Topic**: Mix, Hex, and umbrella project patterns

**Key Findings**:
- **Project Detection**: Use `Mix.Project.umbrella?/1` and `:apps_path` configuration detection
- **Dependency Types**: Hex packages, git dependencies, path dependencies, umbrella siblings
- **Mix.lock Format**: Dependencies locked with specific versions, checksums, and SCM information
- **Version Conflicts**: Resolve using `mix hex.outdated`, `mix deps.upgrade`, or dependency overrides

**Recommendations**:  
- Parse mix.exs files to detect `umbrella: true` and `apps_path:` configurations
- Implement Hex package caching using checksums for integrity verification
- Handle git dependencies with specific commit/tag references for reproducibility
- Use Mix.Project API for programmatic project configuration access

### Senior Engineer Reviewer Consultation
**Topic**: Compilation orchestration architecture

**Key Findings**:
- **Incremental Builds**: Essential for large codebases (15,000+ files), cache aggressively but handle failures
- **Compilation Order**: Dependencies compiled innermost first, circular dependencies prohibited in umbrellas
- **Cache Management**: 99.5% reliability on incremental builds, automatic fallback to full recompilation on retry
- **Performance**: Use `mix xref graph --label compile-connected` to detect unnecessary recompilation triggers

**Recommendations**:
- Implement intelligent caching with automatic cache invalidation on compile errors
- Build dependency graphs before compilation to determine optimal order
- Use compiler warnings and dependency analysis for proactive issue detection
- Implement compilation artifact management with selective cache clearing

---

## Technical Details

### File Locations and Module Structure

```
lib/swe_bench/mix/
├── environment_isolator.ex      # MIX_ENV/HOME/HEX_HOME management  
├── dependency_manager.ex        # mix.lock parsing and resolution
├── compilation_orchestrator.ex  # Build order and incremental compilation
├── project_analyzer.ex          # Project type and structure detection
└── cache_manager.ex            # Compilation artifact caching
```

### Dependencies Required

**New Dependencies**:
- None - leveraging existing Mix, Hex, and Elixir standard library functionality

**Existing Dependencies Utilized**:  
- `Mix.Project` - Project configuration access
- `Mix.Dep` - Dependency parsing and resolution
- `Mix.Tasks.Deps` - Dependency management operations
- `:hex` - Hex package manager integration

### Configuration Schema

```elixir
# Configuration in container executor
config :swe_bench, :mix_manager,
  isolated_home_base: "/tmp/mix_homes",
  hex_cache_dir: "/opt/hex_cache", 
  compilation_timeout: 300_000,
  enable_incremental: true,
  max_circular_deps: 0,
  protocol_consolidation: true
```

### Integration Points

1. **Container System**: Environment variable injection and volume mounting
2. **Test Runner**: Project structure information for test discovery
3. **GitHub API**: Repository structure analysis for project type hints
4. **Caching Layer**: Compilation artifact storage and retrieval

---

## Success Criteria

### Measurable Outcomes

1. **Environment Isolation**: 100% evaluation isolation verified through concurrent execution tests
2. **Dependency Resolution**: Successfully resolve dependencies for all 5 target repositories (Phoenix, Ecto, Jason, Tesla, Credo)  
3. **Compilation Success Rate**: ≥95% successful compilation on first attempt, 99.8% with retry logic
4. **Project Type Detection**: 100% accuracy on standard vs umbrella vs poncho project identification
5. **Performance Targets**:
   - Standard projects: ≤30s compilation time
   - Umbrella projects: ≤90s compilation time  
   - Incremental builds: ≤10s on average
   - Cache hit ratio: ≥80% for repeated evaluations

### Test Requirements

**Unit Tests** (targeting 100% coverage):
- Environment variable isolation verification
- Mix.lock parsing accuracy with edge cases
- Dependency resolution conflict handling
- Project type detection across repository samples
- Compilation order correctness for umbrella structures

**Integration Tests**:
- End-to-end evaluation with each project type
- Concurrent evaluation isolation verification  
- Cache performance and invalidation testing
- Error recovery and retry mechanism validation

**Performance Tests**:
- Compilation time benchmarking across project sizes
- Cache hit ratio measurement under load
- Memory usage monitoring during large project builds
- Concurrent evaluation resource utilization

---

## Implementation Plan

### Phase 1: Environment Isolator (Week 1)
1. **Create Base Module** - `SweBench.Mix.EnvironmentIsolator`
   - Design GenServer for stateful environment management
   - Implement per-evaluation directory creation
   - Add environment variable configuration API

2. **MIX_HOME Isolation** 
   - Generate unique MIX_HOME paths per evaluation
   - Handle Hex and Rebar installation in isolated environments
   - Implement cleanup mechanisms for expired environments

3. **Deterministic Configuration**
   - Set ERL_COMPILER_OPTIONS=deterministic
   - Configure consistent locale and timezone settings
   - Handle Mix.Config vs runtime configuration differences

4. **Unit Testing**
   - Test environment variable isolation
   - Verify MIX_HOME directory management
   - Validate deterministic compilation flags

### Phase 2: Dependency Manager (Week 2)  
1. **Mix.lock Parser**
   - Build robust parser for mix.lock file format
   - Extract dependency versions, checksums, and SCM info
   - Handle parse errors gracefully with fallback mechanisms

2. **Hex Package Caching**
   - Implement local Hex package cache with integrity verification
   - Add cache warming strategies for common dependencies
   - Build cache invalidation logic based on dependency changes

3. **Git Dependency Handling**
   - Clone and checkout specific commits/tags for git dependencies
   - Implement git credential management for private repositories
   - Add git repository caching for performance optimization

4. **Conflict Resolution**
   - Detect version conflicts using constraint solving
   - Implement automatic override suggestions
   - Add manual conflict resolution configuration

### Phase 3: Compilation Orchestrator (Week 3)
1. **Dependency Graph Builder**
   - Parse umbrella project structure to build dependency graphs
   - Detect circular dependencies and report errors
   - Calculate optimal compilation order for parallel builds

2. **Incremental Compilation**
   - Track compilation state across evaluation runs
   - Implement intelligent cache invalidation on source changes
   - Add fallback to full compilation on incremental failures

3. **Protocol Consolidation**
   - Manage protocol consolidation for umbrella projects
   - Handle consolidation failures and recovery
   - Optimize consolidation performance for large projects

4. **Compilation Artifact Management**
   - Cache compiled BEAM files with source fingerprinting
   - Implement selective cache clearing on dependency changes
   - Add compilation artifact sharing across similar evaluations

### Phase 4: Project Analyzer (Week 4)
1. **Project Type Detection**
   - Analyze mix.exs files for umbrella indicators (`umbrella: true`, `apps_path:`)
   - Detect poncho projects through directory structure analysis
   - Build confidence scoring for project type classification

2. **Dependency Mapping**
   - Extract application dependencies from mix.exs files
   - Map inter-app dependencies in umbrella projects
   - Build dependency relationship graphs for visualization

3. **Configuration Parsing**
   - Parse config files (config.exs, runtime.exs, environment-specific)
   - Extract test file patterns and locations
   - Identify build tool requirements and constraints

4. **Integration Testing**
   - Test full pipeline with all project types
   - Verify performance targets across repository set
   - Validate error handling and recovery mechanisms

### Phase 5: Integration & Testing (Week 5)
1. **Container System Integration**
   - Update Docker configurations for Mix environment support
   - Add volume mounting for isolated MIX_HOME directories
   - Test environment variable injection mechanisms

2. **Test Runner Integration**  
   - Provide project structure information to test orchestrator
   - Add compilation failure handling in test execution
   - Implement test discovery optimization using project analysis

3. **Performance Optimization**
   - Profile compilation performance across project types
   - Optimize cache strategies based on usage patterns
   - Implement adaptive compilation strategies

4. **Comprehensive Testing**
   - Execute full test suite with all 5 target repositories
   - Measure performance against success criteria
   - Validate concurrent evaluation isolation

---

## Notes & Considerations

### Edge Cases & Risk Mitigation

**Circular Dependencies in Umbrella Projects**:
- Risk: Complex umbrella projects may have undocumented circular dependencies
- Mitigation: Implement graph analysis with clear error reporting and suggested restructuring

**Mix Version Compatibility**:
- Risk: Different projects may require different Mix versions with incompatible features  
- Mitigation: Version detection and environment switching capabilities

**Large Project Compilation Memory**:
- Risk: Large umbrella projects may exceed container memory limits during compilation
- Mitigation: Implement compilation chunking and memory monitoring with graceful degradation

**Private Hex Packages**:
- Risk: Some repositories may depend on private packages not available during evaluation
- Mitigation: Package availability checking with clear error reporting and skip mechanisms

### Security Considerations

- **Code Execution**: Compilation processes execute repository code - ensure sandboxing
- **Git Credentials**: Handle private repository access securely without credential leakage
- **File System Isolation**: Prevent cross-evaluation contamination through proper cleanup

### Performance Optimizations

**Compilation Artifact Sharing**:
- Share artifacts between evaluations of the same repository/commit
- Implement artifact fingerprinting for safe reuse
- Use copy-on-write semantics for artifact directories

**Dependency Pre-fetching**:
- Analyze repository dependency patterns to pre-fetch common packages
- Build dependency popularity metrics for cache warming strategies
- Implement background dependency updates for commonly used packages

### Future Improvements

**Advanced Caching Strategies**:  
- Implement distributed caching for multi-node evaluation clusters
- Add dependency graph analysis for predictive cache warming
- Build machine learning models for compilation time prediction

**Enhanced Project Analysis**:
- Add static analysis for code complexity metrics
- Implement test coverage analysis integration
- Build project health scoring based on compilation patterns

**Monitoring and Observability**:
- Add comprehensive metrics collection for compilation performance
- Implement compilation failure pattern analysis
- Build alerting for systematic compilation issues

---

## Conclusion

The Mix Project Management System provides essential infrastructure for reliable, performant, and isolated Elixir project evaluation. Through comprehensive environment isolation, intelligent dependency management, sophisticated compilation orchestration, and robust project analysis, this system enables the SWE-bench-Elixir infrastructure to handle diverse project structures with deterministic, reproducible results.

The phased implementation approach ensures incremental value delivery while maintaining system stability, with comprehensive testing and performance optimization throughout the development process.