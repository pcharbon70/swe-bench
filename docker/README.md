# Docker Infrastructure for SWE-bench-Elixir

This directory contains the Docker infrastructure implementing the three-layer architecture optimized for BEAM VM evaluation:

## Architecture Overview

### Layer 1: Base Image (`base/Dockerfile`)
- **Purpose**: Foundational Elixir/OTP runtime environment
- **Contents**: Alpine Linux, Elixir 1.16, Erlang/OTP 27, system dependencies
- **Optimizations**: Minimal footprint, EPMD isolation, deterministic locale settings
- **Size Target**: ~200MB

### Layer 2: Environment Image (`env/Dockerfile`) 
- **Purpose**: Dependency compilation and caching layer
- **Contents**: Common Elixir dependencies, Mix configuration, build tools
- **Optimizations**: Pre-compiled dependencies, umbrella project support
- **Size Target**: ~500MB (cached deps add ~300MB)

### Layer 3: Instance Image (`instance/Dockerfile`)
- **Purpose**: Task execution and patch application layer
- **Contents**: Execution scripts, resource monitoring, cleanup tools
- **Optimizations**: Resource limits, timeout handling, artifact management
- **Size Target**: ~550MB (adds ~50MB of tooling)

## Key Features

### BEAM VM Optimizations
- **EPMD Isolation**: Proper Erlang Port Mapper Daemon configuration
- **Compilation Caching**: Efficient .beam file management
- **Memory Management**: Optimized garbage collection settings
- **Process Limits**: Configured for evaluation workloads

### Security Features
- **Non-root Execution**: All containers run as `elixir` user
- **Read-only Filesystem**: Immutable container filesystem
- **Network Isolation**: Containers run with `--network none` by default
- **Resource Limits**: Memory and CPU limits enforced

### Performance Features
- **Container Pooling**: Pre-warmed containers for fast execution
- **Incremental Compilation**: Smart dependency rebuilds
- **Artifact Caching**: Persistent compilation artifacts
- **Health Monitoring**: Comprehensive container health checks

## Usage

### Building Images

```bash
# Build all images in dependency order
cd docker/
docker build -t swe-bench/base:latest -f base/Dockerfile base/
docker build -t swe-bench/env:latest --build-arg BASE_IMAGE=swe-bench/base:latest -f env/Dockerfile env/
docker build -t swe-bench/instance:latest --build-arg ENV_IMAGE=swe-bench/env:latest -f instance/Dockerfile instance/

# Or use the orchestration system
iex -S mix
SweBench.Container.build_images(force: true)
```

### Running Development Environment

```bash
# Start all services
docker-compose up -d

# Check service health
docker-compose ps

# View logs
docker-compose logs swe_bench

# Stop all services
docker-compose down
```

### Manual Container Testing

```bash
# Run instance container interactively
docker run -it --rm swe-bench/instance:latest /bin/bash

# Test patch application (inside container)
/opt/app/apply_patch.sh /path/to/patch.diff base_commit /opt/app/execution

# Test execution (inside container)  
/opt/app/execute_tests.sh /opt/app/execution

# Test full orchestration (inside container)
/opt/app/orchestrate.sh /path/to/patch.diff base_commit /path/to/project false
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MIX_ENV` | `test` | Mix environment for evaluation |
| `EXECUTION_TIMEOUT` | `300` | Execution timeout in seconds |
| `MEMORY_LIMIT` | `4294967296` | Memory limit in bytes (4GB) |
| `CPU_LIMIT` | `4` | CPU core limit |
| `ERL_EPMD_ADDRESS` | `127.0.0.1` | EPMD bind address |
| `ERL_EPMD_PORT` | `4369` | EPMD port |

### Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker-in-Docker access |
| `./project` | `/opt/app/execution` | Project code injection |
| `./patches` | `/opt/app/patches` | Patch file access |
| `./results` | `/opt/app/results` | Result collection |

## Monitoring and Debugging

### Health Checks
Each layer includes comprehensive health checks:
- **Base**: Elixir runtime verification
- **Environment**: Mix and dependency verification  
- **Instance**: Execution capability verification

### Resource Monitoring
Containers include built-in resource monitoring:
- Memory usage tracking with alerts
- CPU utilization monitoring
- Process count limits
- File descriptor limits

### Logging
Structured logging for all container operations:
- Container lifecycle events
- Resource usage statistics
- Execution progress and results
- Error conditions and recovery

### Debug Commands

```bash
# Inspect container configuration
docker inspect <container_id>

# Monitor resource usage
docker stats <container_id>

# Execute commands in running container
docker exec -it <container_id> /bin/bash

# View container logs
docker logs <container_id>
```

## Troubleshooting

### Common Issues

1. **Build Failures**
   - Check Docker daemon is running
   - Verify sufficient disk space (>2GB)
   - Ensure network connectivity for package downloads

2. **Container Startup Issues**
   - Check resource limits (memory/CPU)
   - Verify EPMD port availability
   - Review container logs for errors

3. **Execution Timeouts**
   - Adjust `EXECUTION_TIMEOUT` environment variable
   - Check for infinite loops in test code
   - Monitor resource usage during execution

4. **Permission Issues**
   - Verify Docker socket permissions
   - Check file ownership in mounted volumes
   - Ensure `elixir` user has proper access

### Performance Tuning

1. **Memory Optimization**
   ```bash
   # Adjust container memory limits
   docker run --memory=2g swe-bench/instance:latest
   ```

2. **CPU Optimization**
   ```bash
   # Set CPU limits
   docker run --cpus=2 swe-bench/instance:latest
   ```

3. **Storage Optimization**
   ```bash
   # Use tmpfs for temporary files
   docker run --tmpfs /tmp:exec,size=100m swe-bench/instance:latest
   ```

## Development

### Adding New Dependencies
1. Add to `env/Dockerfile` in the dependency list
2. Rebuild environment image
3. Test with sample project
4. Update documentation

### Modifying Execution Scripts
1. Edit scripts in `instance/` directory
2. Rebuild instance image
3. Test with sample evaluation
4. Update integration tests

### Performance Improvements
1. Profile container startup time
2. Optimize image layer sizes
3. Improve caching strategies
4. Monitor resource utilization

## Security Considerations

- All containers run as non-root user
- Network isolation prevents external access
- Resource limits prevent DoS attacks
- Read-only filesystems prevent tampering
- Regular security updates for base images

## Production Deployment

For production deployment:
1. Use specific image tags instead of `latest`
2. Configure proper logging aggregation
3. Set up monitoring and alerting
4. Implement backup strategies for persistent data
5. Use container orchestration (Kubernetes/Docker Swarm)