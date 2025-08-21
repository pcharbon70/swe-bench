# Phase 1.1: Docker Containerization with BEAM VM Optimization

## Problem Statement

The SWE-bench-Elixir project requires a sophisticated containerization infrastructure specifically designed for the unique requirements of the BEAM VM and Elixir ecosystem. Traditional Docker approaches fail to address critical Elixir-specific challenges:

1. **BEAM File Management**: Compiled .beam files require careful handling for incremental compilation and caching
2. **EPMD Isolation**: Erlang Port Mapper Daemon needs proper isolation between container instances
3. **Mix Project Dependencies**: Complex dependency resolution and compilation order requirements
4. **Distributed Erlang**: Support for multi-node Erlang clusters within containers
5. **Performance Optimization**: Container startup times and resource utilization specific to BEAM VM

## Solution Overview

Implement a three-layer Docker architecture optimized for BEAM VM characteristics:

1. **Base Layer**: Foundational Elixir/OTP runtime with system dependencies
2. **Environment Layer**: Dependency compilation and caching with Mix ecosystem optimization
3. **Instance Layer**: Task-specific code execution with patch application and resource limits

## Agent Consultations Performed

**Note**: Custom agents were not accessible in this environment, but research was conducted following their methodologies:

- **Research-Agent Methodology**: Researched Docker multi-layer architecture patterns, container orchestration best practices, and performance optimization techniques
- **Elixir-Expert Methodology**: Analyzed BEAM VM containerization requirements, Mix project handling, and Erlang distribution patterns
- **Architecture-Agent Methodology**: Designed integration with existing codebase structure and evaluated architectural impact

## Technical Details

### Current Codebase Analysis
- **Framework**: Phoenix application with Ash authentication
- **Structure**: Standard Elixir project with mix.exs, configurations
- **Dependencies**: Ash framework, Phoenix, authentication libraries
- **Target**: Container-based evaluation system for AI-generated code

### File Locations and Dependencies
- **Docker Files**: `docker/` directory structure
- **Base Image**: `docker/Dockerfile.base`
- **Environment**: `docker/Dockerfile.env`  
- **Instance**: `docker/Dockerfile.instance`
- **Orchestration**: `lib/swe_bench/container/` module structure
- **Configuration**: Docker Compose files for multi-container scenarios

### Key Dependencies
- **Docker Engine**: Container runtime
- **Docker Compose**: Multi-container orchestration
- **Elixir 1.16+**: Target Elixir version
- **Erlang/OTP 27+**: Target OTP version
- **Alpine Linux**: Minimal base OS for efficiency

## Success Criteria

### Functional Requirements
- [ ] **Base Image Creation**: Minimal Elixir/OTP image with system dependencies
- [ ] **Environment Layer**: Efficient dependency resolution and compilation caching
- [ ] **Instance Layer**: Code patching and execution with resource limits
- [ ] **EPMD Isolation**: Proper Erlang distribution isolation between containers
- [ ] **Container Orchestration**: Automated container lifecycle management

### Performance Requirements
- [ ] **Startup Time**: Base container starts in < 5 seconds
- [ ] **Build Time**: Environment layer builds in < 2 minutes
- [ ] **Resource Usage**: Memory usage < 512MB per instance
- [ ] **Compilation Speed**: Incremental compilation < 30 seconds
- [ ] **Isolation**: Zero interference between concurrent containers

### Quality Requirements
- [ ] **Test Coverage**: 100% test coverage for orchestration module
- [ ] **Error Handling**: Comprehensive error scenarios covered
- [ ] **Documentation**: Complete API documentation
- [ ] **Monitoring**: Health checks and metrics collection
- [ ] **Security**: No root processes, minimal attack surface

## Implementation Plan

### Phase 1.1.1: Create Base Docker Image for Elixir/OTP

- [ ] **1.1.1.1** Configure Alpine Linux base with minimal footprint
  - Research minimal Alpine packages for Elixir
  - Configure package manager and update system
  - Set up proper timezone and locale settings
  
- [ ] **1.1.1.2** Install Elixir 1.16 and Erlang/OTP 27
  - Add Erlang Solutions repository
  - Install specific OTP and Elixir versions
  - Verify installation and version compatibility
  
- [ ] **1.1.1.3** Add system dependencies (git, build-base, postgresql-client)
  - Install compilation tools and libraries
  - Add git for dependency fetching
  - Include database client tools
  
- [ ] **1.1.1.4** Configure EPMD for isolated instances
  - Set up EPMD configuration for container isolation
  - Configure node naming patterns
  - Test inter-container communication
  
- [ ] **1.1.1.5** Set up locale and timezone for deterministic behavior
  - Configure system locale settings
  - Set timezone for consistent timestamps
  - Verify deterministic behavior across runs

### Phase 1.1.2: Implement Environment Layer for Dependencies

- [ ] **1.1.2.1** Create workspace directory structure
  - Design optimal directory layout for Mix projects
  - Set up proper file permissions and ownership
  - Create standard workspace hierarchy
  
- [ ] **1.1.2.2** Configure Mix for offline dependency resolution
  - Set up Mix configuration for container environment
  - Configure dependency caching strategies
  - Handle private repositories and authentication
  
- [ ] **1.1.2.3** Install Hex and Rebar without network access
  - Cache Hex packages for offline installation
  - Set up Rebar for Erlang dependencies
  - Configure package verification and integrity checks
  
- [ ] **1.1.2.4** Implement dependency caching mechanism
  - Design efficient dependency cache structure
  - Implement cache invalidation strategies
  - Optimize for build speed and storage efficiency
  
- [ ] **1.1.2.5** Handle umbrella project dependency graphs
  - Parse umbrella project structures
  - Resolve inter-application dependencies
  - Optimize compilation order for umbrellas

### Phase 1.1.3: Build Instance Layer for Task Execution

- [ ] **1.1.3.1** Apply code patches to specific commits
  - Implement patch application mechanism
  - Handle patch conflicts and failures
  - Verify patch integrity and completeness
  
- [ ] **1.1.3.2** Manage incremental compilation state
  - Track compilation artifacts and dependencies
  - Implement efficient incremental rebuilds
  - Handle compilation cache invalidation
  
- [ ] **1.1.3.3** Configure resource limits (4GB RAM, 4 CPU cores)
  - Set container resource constraints
  - Monitor resource usage and enforcement
  - Handle out-of-memory scenarios gracefully
  
- [ ] **1.1.3.4** Implement 300-second execution timeout
  - Add timeout mechanisms for all operations
  - Handle timeout scenarios and cleanup
  - Provide timeout configuration options
  
- [ ] **1.1.3.5** Handle compilation artifact cleanup
  - Clean up temporary files after execution
  - Manage disk space usage efficiently
  - Implement garbage collection for artifacts

### Phase 1.1.4: Create Advanced Container Orchestration Module

- [ ] **1.1.4.1** Implement container lifecycle management
  - Design container state machine
  - Handle container creation, startup, and shutdown
  - Implement proper cleanup and resource deallocation
  
- [ ] **1.1.4.2** Add volume mounting for code injection
  - Design secure volume mounting strategy
  - Handle code injection for patch testing
  - Implement proper file system isolation
  
- [ ] **1.1.4.3** Configure network isolation per evaluation
  - Set up container network isolation
  - Implement proper network policies
  - Handle inter-container communication needs
  
- [ ] **1.1.4.4** Implement basic container pooling for performance
  - Design container pool architecture
  - Implement pool management and allocation
  - Optimize for container reuse and performance
  
- [ ] **1.1.4.5** Add cleanup and garbage collection
  - Implement automatic cleanup mechanisms
  - Handle failed containers and zombie processes
  - Monitor and manage system resource usage
  
- [ ] **1.1.4.6** Implement container pool pre-warming strategy
  - Design pre-warming algorithms
  - Implement predictive container allocation
  - Optimize startup time with warm pools
  
- [ ] **1.1.4.7** Create container reuse mechanisms with state clearing
  - Implement safe container state reset
  - Design reuse policies and limits
  - Handle state isolation between reuses
  
- [ ] **1.1.4.8** Build pool size auto-scaling based on demand
  - Implement demand-based scaling algorithms
  - Monitor pool utilization and performance
  - Configure scaling policies and limits
  
- [ ] **1.1.4.9** Add health checks for pooled containers
  - Design comprehensive health check system
  - Implement container health monitoring
  - Handle unhealthy container replacement
  
- [ ] **1.1.4.10** Implement container checkout/checkin system with timeouts
  - Design container allocation API
  - Implement timeout-based resource management
  - Handle allocation conflicts and queuing

### Testing Implementation Plan

- [ ] **Unit Tests**: Test each component in isolation
  - Docker image build processes
  - Dependency resolution mechanisms  
  - Resource limit enforcement
  - Container orchestration logic
  
- [ ] **Integration Tests**: Test component interactions
  - End-to-end container lifecycle
  - Multi-container scenarios
  - Resource sharing and isolation
  - Error handling and recovery
  
- [ ] **Performance Tests**: Validate performance requirements
  - Container startup and shutdown times
  - Resource usage under load
  - Concurrent container handling
  - Cache efficiency and hit rates

## Notes/Considerations

### Edge Cases and Potential Issues
- **Container Startup Failures**: Need robust error handling and retry mechanisms
- **Resource Exhaustion**: Handle scenarios where system resources are depleted
- **Network Conflicts**: Manage port conflicts and network isolation issues
- **Storage Limits**: Handle disk space limitations and cleanup requirements
- **BEAM VM Quirks**: Address specific BEAM VM behaviors in containerized environments

### Future Improvements
- **Multi-Architecture Support**: ARM64 and x86_64 compatibility
- **GPU Support**: Container GPU access for compute-intensive tasks
- **Monitoring Integration**: Integration with observability platforms
- **Security Hardening**: Enhanced security policies and scanning
- **Performance Optimization**: Further optimization based on usage patterns

### Risk Assessment
- **High Risk**: EPMD isolation complexity may require extensive testing
- **Medium Risk**: Container pool management complexity could impact reliability
- **Low Risk**: Basic Docker operations are well-established patterns

### Integration Considerations
- **Existing Codebase**: Must integrate cleanly with current Ash/Phoenix structure
- **Testing Framework**: Should work with existing ExUnit test infrastructure  
- **Configuration Management**: Must align with current configuration patterns
- **Deployment Pipeline**: Should integrate with CI/CD processes

## Status Tracking

### Current Progress: Planning Phase Complete ✅
- [x] Problem analysis and requirements gathering
- [x] Solution architecture design  
- [x] Technical specification creation
- [x] Implementation plan development
- [x] Success criteria definition

### Next Steps
1. Begin implementation of base Docker image (1.1.1)
2. Set up development environment for Docker testing
3. Create initial project structure for container modules
4. Start with Alpine Linux base image configuration

### How to Run Development Environment
```bash
# Create development structure
mkdir -p docker/{base,env,instance}
mkdir -p lib/swe_bench/container
mkdir -p test/swe_bench/container

# Start development
mix deps.get
mix compile
```

This planning document provides the comprehensive foundation for implementing Phase 1.1 of the SWE-bench-Elixir containerization infrastructure, following established planning methodologies and ensuring thorough preparation for successful implementation.