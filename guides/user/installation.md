# Installation Guide

This guide walks you through installing and setting up your own instance of SWE-bench-Elixir for development, research, or private deployment.

## Prerequisites

### System Requirements

```mermaid
graph TB
    subgraph "Minimum Requirements"
        A1[CPU: 4 cores]
        A2[RAM: 8GB]
        A3[Storage: 50GB]
        A4[Network: 1Gbps]
    end
    
    subgraph "Recommended"
        B1[CPU: 8+ cores]
        B2[RAM: 32GB]
        B3[Storage: 200GB SSD]
        B4[Network: 10Gbps]
    end
    
    subgraph "Production"
        C1[CPU: 16+ cores]
        C2[RAM: 64GB]
        C3[Storage: 1TB NVMe]
        C4[Network: Dedicated]
    end
    
    style B1 fill:#10b981,stroke:#059669,stroke-width:2px
    style B2 fill:#10b981,stroke:#059669,stroke-width:2px
    style B3 fill:#10b981,stroke:#059669,stroke-width:2px
```

### Software Dependencies

**Required**:
- **Elixir**: 1.15+ with OTP 25+
- **PostgreSQL**: 13+ for data storage
- **Docker**: 20+ for container evaluation environments
- **Git**: For repository management

**Optional but Recommended**:
- **Redis**: For caching and session storage
- **NGINX**: For production load balancing
- **Kubernetes**: For container orchestration

## Installation Methods

### Method 1: Quick Start (Docker Compose)

**Best for**: Development and testing

```bash
# Clone the repository
git clone https://github.com/your-org/swe_bench.git
cd swe_bench

# Start with Docker Compose
docker-compose up -d

# The system will be available at http://localhost:4000
```

### Method 2: Development Setup

**Best for**: Local development and contribution

#### Step 1: Install Dependencies

```bash
# Install Elixir (macOS with Homebrew)
brew install elixir

# Install Elixir (Ubuntu/Debian)
sudo apt update
sudo apt install elixir

# Install PostgreSQL
brew install postgresql          # macOS
sudo apt install postgresql-13  # Ubuntu/Debian

# Install Docker
# Follow official Docker installation instructions for your OS
```

#### Step 2: Setup Database

```bash
# Start PostgreSQL
brew services start postgresql  # macOS
sudo systemctl start postgresql # Linux

# Create database user
createuser -d -P swe_bench_dev

# Create databases
createdb -O swe_bench_dev swe_bench_dev
createdb -O swe_bench_dev swe_bench_test
```

#### Step 3: Configure Application

```bash
# Clone repository
git clone https://github.com/your-org/swe_bench.git
cd swe_bench

# Install dependencies
mix deps.get

# Create configuration file
cp config/dev.example.exs config/dev.local.exs
```

Edit `config/dev.local.exs`:

```elixir
import Config

# Database configuration
config :swe_bench, SweBench.Repo,
  username: "swe_bench_dev",
  password: "your_password",
  hostname: "localhost",
  database: "swe_bench_dev"

# Container configuration  
config :swe_bench, :container,
  docker_host: "unix:///var/run/docker.sock",
  pool_size: 5

# Real-time events
config :swe_bench, :real_time_events,
  event_store_enabled: true
```

#### Step 4: Initialize Database

```bash
# Run database migrations
mix ecto.create
mix ecto.migrate

# Optional: Seed with sample data
mix run priv/repo/seeds.exs
```

#### Step 5: Start the Application

```bash
# Compile and start  
mix compile
mix phx.server

# Visit http://localhost:4000
```

### Method 3: Production Deployment

**Best for**: Production hosting

#### Using Kubernetes (Recommended)

```yaml
# kubernetes/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: swe-bench
---
# kubernetes/deployment.yaml  
apiVersion: apps/v1
kind: Deployment
metadata:
  name: swe-bench-app
  namespace: swe-bench
spec:
  replicas: 3
  selector:
    matchLabels:
      app: swe-bench
  template:
    metadata:
      labels:
        app: swe-bench
    spec:
      containers:
      - name: swe-bench
        image: swe-bench:latest
        ports:
        - containerPort: 4000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: swe-bench-secrets
              key: database-url
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: swe-bench-secrets  
              key: secret-key-base
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi" 
            cpu: "2"
```

Apply the configuration:

```bash
kubectl apply -f kubernetes/
```

## Configuration

### Environment Variables

#### Required Configuration

```bash
# Database
export DATABASE_URL="postgresql://user:pass@host:5432/swe_bench_prod"

# Security
export SECRET_KEY_BASE="your-secret-key-base-64-chars-long"

# Container Runtime  
export DOCKER_HOST="unix:///var/run/docker.sock"

# Basic Settings
export PHX_HOST="your-domain.com"
export PORT="4000"
```

#### Optional Configuration

```bash
# Authentication
export GITHUB_CLIENT_ID="your-github-oauth-client-id"
export GITHUB_CLIENT_SECRET="your-github-oauth-secret"
export GOOGLE_CLIENT_ID="your-google-oauth-client-id" 
export GOOGLE_CLIENT_SECRET="your-google-oauth-secret"

# Redis (for caching)
export REDIS_URL="redis://localhost:6379/0"

# Monitoring
export PROMETHEUS_ENABLED="true"
export JAEGER_ENDPOINT="http://jaeger:14268/api/traces"

# Container Pool
export CONTAINER_MIN_POOL_SIZE="10"
export CONTAINER_MAX_POOL_SIZE="100"
```

### Production Configuration

#### Environment-Specific Files

**`config/prod.exs`** (Production base configuration):
```elixir
import Config

config :swe_bench, SweBench.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

config :swe_bench_web, SweBenchWeb.Endpoint,
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
  check_origin: [
    "https://#{System.get_env("PHX_HOST")}",
    "https://www.#{System.get_env("PHX_HOST")}"
  ]

# Container configuration
config :swe_bench, :container,
  pool_manager: SweBench.Container.AdvancedPool.PoolManager,
  min_pool_size: String.to_integer(System.get_env("CONTAINER_MIN_POOL_SIZE") || "10"),
  max_pool_size: String.to_integer(System.get_env("CONTAINER_MAX_POOL_SIZE") || "50")
```

## Verification

### Health Check

After installation, verify the system is working:

#### Step 1: Check Application Health

```bash
# Health check endpoint
curl http://localhost:4000/health

# Expected response:
{
  "status": "healthy",
  "database": "connected", 
  "container_pool": "ready",
  "version": "1.0.0"
}
```

#### Step 2: Test Container System

```bash
# Container pool status
curl http://localhost:4000/admin/containers/status

# Should show container pool information
```

#### Step 3: Verify Real-Time Features

1. Open dashboard: `http://localhost:4000/dashboard`
2. Check for live timestamps and real-time indicators
3. Verify filtering works by selecting different models

### System Components Check

```mermaid
graph TD
    A[System Health Check] --> B[Database Connection]
    A --> C[Container Runtime]
    A --> D[PubSub System]
    A --> E[Authentication]
    
    B --> F{PostgreSQL OK?}
    C --> G{Docker OK?}
    D --> H{Phoenix.PubSub OK?}
    E --> I{Auth System OK?}
    
    F -->|Yes| J[✅ Ready]
    G -->|Yes| J
    H -->|Yes| J
    I -->|Yes| J
    
    F -->|No| K[❌ Fix Database]
    G -->|No| L[❌ Fix Docker]
    H -->|No| M[❌ Fix PubSub] 
    I -->|No| N[❌ Fix Auth]
    
    style J fill:#10b981,stroke:#059669,stroke-width:2px
    style K fill:#ef4444,stroke:#dc2626,stroke-width:2px
```

## Troubleshooting

### Common Installation Issues

#### Database Connection Issues

**Problem**: `(Postgrex.Error) FATAL 28000: authentication failed`

**Solutions**:
```bash
# Check PostgreSQL is running
pg_ctl status

# Verify credentials
psql -U swe_bench_dev -h localhost -d swe_bench_dev

# Reset password if needed
ALTER USER swe_bench_dev PASSWORD 'new_password';
```

#### Docker Permission Issues

**Problem**: `Cannot connect to the Docker daemon`

**Solutions**:
```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Start Docker service
sudo systemctl start docker

# Verify Docker access
docker ps
```

#### Port Conflicts

**Problem**: `Port 4000 already in use`

**Solutions**:
```bash
# Find process using port
lsof -i :4000

# Kill process or use different port
export PORT=4001
mix phx.server
```

#### Memory Issues

**Problem**: System runs out of memory during evaluations

**Solutions**:
```bash
# Reduce container pool size
export CONTAINER_MAX_POOL_SIZE=5

# Increase system swap
sudo swapon -s
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## Security Setup

### Basic Security Configuration

```elixir
# Generate secret key base
secret_key_base = :crypto.strong_rand_bytes(64) |> Base.encode64()

# Set in production environment
export SECRET_KEY_BASE="#{secret_key_base}"
```

### SSL/TLS Configuration

For production deployment with SSL:

```elixir
config :swe_bench_web, SweBenchWeb.Endpoint,
  https: [
    port: 443,
    cipher_suite: :strong,
    keyfile: System.get_env("SSL_KEY_PATH"),
    certfile: System.get_env("SSL_CERT_PATH")
  ],
  force_ssl: [hsts: true]
```

### Firewall Configuration

```bash
# Allow HTTP/HTTPS traffic
sudo ufw allow 80
sudo ufw allow 443

# Allow SSH for administration  
sudo ufw allow 22

# Enable firewall
sudo ufw enable
```

## Performance Tuning

### Production Optimization

#### Database Tuning

```elixir
config :swe_bench, SweBench.Repo,
  pool_size: 20,
  timeout: 60_000,
  ownership_timeout: 300_000,
  
  # Connection pooling
  queue_target: 5000,
  queue_interval: 5000
```

#### Container Optimization

```elixir
config :swe_bench, :container,
  min_pool_size: 20,
  max_pool_size: 100,
  scaling_threshold: 0.8,
  container_timeout: 600_000,
  
  # Performance settings
  container_reuse_enabled: true,
  warm_pool_enabled: true,
  health_check_interval: 30_000
```

### Monitoring Setup

Enable comprehensive monitoring:

```elixir
config :swe_bench, :monitoring,
  metrics_collection: true,
  prometheus_enabled: true,
  alerting_enabled: true,
  
  # External integrations
  grafana_url: "https://grafana.your-domain.com",
  jaeger_endpoint: "https://jaeger.your-domain.com"
```

## Next Steps

### After Installation

1. **[Getting Started](./getting-started.md)**: Learn to use the platform
2. **[Web Interface](./web-interface.md)**: Master the dashboard features
3. **[Understanding Results](./understanding-results.md)**: Interpret evaluation metrics
4. **[Advanced Filtering](./advanced-filtering.md)**: Use powerful filtering capabilities

### For System Administration

1. **Monitor Performance**: Use built-in monitoring dashboard
2. **Configure Scaling**: Adjust container pool settings based on usage
3. **Setup Backups**: Configure automated database backups
4. **Security Hardening**: Implement additional security measures

### For Development

1. **Read Developer Guides**: Understand the architecture for contributions
2. **Setup Development Environment**: Configure for local development
3. **Run Tests**: Execute comprehensive test suite for validation
4. **Follow Contribution Guidelines**: Maintain code quality standards

Congratulations! You now have a running SWE-bench-Elixir instance. Start exploring AI coding evaluation capabilities! 🎉