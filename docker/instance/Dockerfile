# Instance Layer for Task Execution
# This layer handles code patching, execution, and resource management

ARG ENV_IMAGE=swe-bench/env:latest
FROM ${ENV_IMAGE}

# Metadata for instance layer
LABEL swe-bench.layer="instance"
LABEL swe-bench.description="Task execution layer with patch application"

# Switch to root for system configuration
USER root

# Install additional tools needed for patch application and execution
RUN apk add --no-cache \
    # Patch utilities
    patch \
    diff \
    # Process monitoring
    htop \
    # Memory analysis
    strace \
    # Time measurement
    time \
    # File watching
    inotify-tools \
    # JSON processing
    jq

# Configure resource limits and monitoring
# Install memory monitoring tools
RUN apk add --no-cache \
    procfs-ng \
    sysstat

# Switch back to elixir user
USER elixir
WORKDIR /opt/app

# Configure execution environment
ENV MIX_ENV=test
ENV EXECUTION_TIMEOUT=300
ENV MEMORY_LIMIT=4294967296
ENV CPU_LIMIT=4

# Create execution directory structure
RUN mkdir -p \
    /opt/app/execution \
    /opt/app/patches \
    /opt/app/results \
    /opt/app/logs \
    /opt/app/artifacts

# Create patch application script
RUN echo '#!/bin/bash
# Patch application and verification script
set -e

PATCH_FILE="$1"
BASE_COMMIT="$2"
TARGET_DIR="${3:-/opt/app/execution}"

echo "=== Patch Application Started ==="
echo "Patch file: $PATCH_FILE"
echo "Base commit: $BASE_COMMIT" 
echo "Target directory: $TARGET_DIR"

# Validate inputs
if [[ -z "$PATCH_FILE" || ! -f "$PATCH_FILE" ]]; then
    echo "ERROR: Patch file not provided or not found: $PATCH_FILE"
    exit 1
fi

# Create execution directory if it doesnt exist
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# If base commit is provided, ensure we are at the right commit
if [[ -n "$BASE_COMMIT" && -d ".git" ]]; then
    echo "Checking out base commit: $BASE_COMMIT"
    git checkout "$BASE_COMMIT" 2>/dev/null || {
        echo "WARNING: Could not checkout commit $BASE_COMMIT"
    }
fi

# Apply patch with various strategies
echo "Applying patch..."
if patch -p1 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "Patch applies cleanly with -p1"
    patch -p1 < "$PATCH_FILE"
elif patch -p0 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "Patch applies with -p0"
    patch -p0 < "$PATCH_FILE"
elif git apply --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "Applying with git apply"
    git apply "$PATCH_FILE"
else
    echo "ERROR: Patch does not apply cleanly"
    echo "Attempting fuzzy patch application..."
    if patch -p1 --fuzz=3 < "$PATCH_FILE"; then
        echo "WARNING: Patch applied with fuzz"
    else
        echo "ERROR: Patch application failed completely"
        exit 1
    fi
fi

echo "=== Patch Application Complete ==="

# Verify patch was applied
echo "=== Patch Verification ==="
if [[ -d ".git" ]]; then
    echo "Git status after patch:"
    git status --porcelain || true
    echo "Git diff summary:"
    git diff --stat || true
fi

echo "Modified files:"
find . -name "*.ex" -o -name "*.exs" -newer "$PATCH_FILE" 2>/dev/null | head -20 || true

' > /opt/app/apply_patch.sh && \
    chmod +x /opt/app/apply_patch.sh

# Create test execution script with timeout and resource monitoring
RUN echo '#!/bin/bash
# Test execution with resource monitoring and timeout
set -e

TIMEOUT="${EXECUTION_TIMEOUT:-300}"
MEMORY_LIMIT="${MEMORY_LIMIT:-4294967296}"
WORK_DIR="${1:-/opt/app/execution}"
RESULTS_DIR="/opt/app/results"
LOGS_DIR="/opt/app/logs"

echo "=== Test Execution Started ==="
echo "Working directory: $WORK_DIR"
echo "Timeout: ${TIMEOUT}s"
echo "Memory limit: $MEMORY_LIMIT bytes"
echo "Results directory: $RESULTS_DIR"

# Ensure directories exist
mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

# Change to working directory
cd "$WORK_DIR"

# Function to monitor resources
monitor_resources() {
    local pid=$1
    local log_file="$LOGS_DIR/resource_usage.log"
    
    echo "timestamp,memory_mb,cpu_percent" > "$log_file"
    
    while kill -0 "$pid" 2>/dev/null; do
        if [[ -f "/proc/$pid/status" ]]; then
            local memory_kb=$(awk "/VmRSS:/ { print \$2 }" "/proc/$pid/status" 2>/dev/null || echo "0")
            local memory_mb=$((memory_kb / 1024))
            local cpu_percent=$(ps -p "$pid" -o "%cpu" --no-headers 2>/dev/null || echo "0.0")
            local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
            
            echo "$timestamp,$memory_mb,$cpu_percent" >> "$log_file"
            
            # Check memory limit
            if [[ $memory_kb -gt $((MEMORY_LIMIT / 1024)) ]]; then
                echo "MEMORY LIMIT EXCEEDED: ${memory_mb}MB > $((MEMORY_LIMIT / 1024 / 1024))MB"
                kill -9 "$pid" 2>/dev/null || true
                break
            fi
        fi
        
        sleep 1
    done
}

# Pre-execution setup
echo "Setting up test environment..."

# Install dependencies if needed
if [[ -f "mix.exs" ]]; then
    echo "Installing dependencies..."
    timeout 120 mix deps.get || {
        echo "WARNING: Dependency installation timed out or failed"
    }
    
    echo "Compiling project..."
    timeout 180 mix compile || {
        echo "ERROR: Compilation failed"
        exit 1
    }
fi

# Start test execution with timeout and monitoring
echo "Starting test execution..."

# Create result capture file
RESULT_FILE="$RESULTS_DIR/test_results.json"
LOG_FILE="$LOGS_DIR/test_output.log"

# Execute tests with timeout and capture output
{
    echo "{"
    echo "  \"start_time\": \"$(date -Iseconds)\","
    echo "  \"timeout\": $TIMEOUT,"
    echo "  \"memory_limit\": $MEMORY_LIMIT,"
    
    # Start test execution in background for monitoring
    (
        if [[ -f "mix.exs" ]]; then
            mix test --formatter=json 2>&1
        else
            echo "No mix.exs found, trying to run elixir files directly"
            find . -name "*_test.exs" -exec elixir {} \; 2>&1
        fi
    ) > "$LOG_FILE" 2>&1 &
    
    TEST_PID=$!
    
    # Start resource monitoring in background
    monitor_resources $TEST_PID &
    MONITOR_PID=$!
    
    # Wait for test completion with timeout
    local exit_code=0
    if timeout $TIMEOUT wait $TEST_PID; then
        wait $TEST_PID
        exit_code=$?
    else
        echo "EXECUTION TIMEOUT REACHED"
        kill -9 $TEST_PID 2>/dev/null || true
        exit_code=124
    fi
    
    # Stop monitoring
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
    
    echo "  \"end_time\": \"$(date -Iseconds)\","
    echo "  \"exit_code\": $exit_code,"
    echo "  \"log_file\": \"$LOG_FILE\","
    echo "  \"resource_log\": \"$LOGS_DIR/resource_usage.log\""
    echo "}"
    
} > "$RESULT_FILE"

echo "=== Test Execution Complete ==="
echo "Results: $RESULT_FILE"
echo "Logs: $LOG_FILE"

# Output summary
if [[ -f "$RESULT_FILE" ]]; then
    echo "=== Execution Summary ==="
    cat "$RESULT_FILE" | jq . 2>/dev/null || cat "$RESULT_FILE"
fi

' > /opt/app/execute_tests.sh && \
    chmod +x /opt/app/execute_tests.sh

# Create cleanup script for artifacts
RUN echo '#!/bin/bash
# Cleanup script for execution artifacts
set -e

WORK_DIR="${1:-/opt/app/execution}"
KEEP_RESULTS="${2:-true}"

echo "=== Cleanup Started ==="
echo "Working directory: $WORK_DIR"
echo "Keep results: $KEEP_RESULTS"

# Clean compilation artifacts
if [[ -d "$WORK_DIR" ]]; then
    cd "$WORK_DIR"
    
    echo "Cleaning compilation artifacts..."
    rm -rf _build/*/lib/*/ebin/*.beam 2>/dev/null || true
    rm -rf .elixir_ls 2>/dev/null || true
    rm -rf deps/*/ebin/*.beam 2>/dev/null || true
    
    echo "Cleaning temporary files..."
    find . -name "*.tmp" -delete 2>/dev/null || true
    find . -name "*.log" -delete 2>/dev/null || true
    find . -name ".DS_Store" -delete 2>/dev/null || true
    
    echo "Cleaning git artifacts..."
    rm -rf .git/objects/tmp_* 2>/dev/null || true
    git gc --prune=now 2>/dev/null || true
fi

# Optionally clean results
if [[ "$KEEP_RESULTS" == "false" ]]; then
    echo "Cleaning results and logs..."
    rm -rf /opt/app/results/* 2>/dev/null || true
    rm -rf /opt/app/logs/* 2>/dev/null || true
fi

# System cleanup
echo "Cleaning system temporary files..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /opt/app/tmp/* 2>/dev/null || true

echo "=== Cleanup Complete ==="

' > /opt/app/cleanup.sh && \
    chmod +x /opt/app/cleanup.sh

# Create comprehensive execution orchestrator
RUN echo '#!/bin/bash
# Main execution orchestrator for patch testing
set -e

# Parse arguments
PATCH_FILE="$1"
BASE_COMMIT="$2"
PROJECT_PATH="$3"
KEEP_ARTIFACTS="${4:-false}"

echo "=== SWE-Bench Execution Orchestrator ==="
echo "Patch file: $PATCH_FILE"
echo "Base commit: $BASE_COMMIT"
echo "Project path: $PROJECT_PATH"
echo "Keep artifacts: $KEEP_ARTIFACTS"

# Validate required inputs
if [[ -z "$PATCH_FILE" || -z "$PROJECT_PATH" ]]; then
    echo "ERROR: Missing required arguments"
    echo "Usage: $0 <patch_file> <base_commit> <project_path> [keep_artifacts]"
    exit 1
fi

# Set up execution environment
EXECUTION_DIR="/opt/app/execution"
RESULTS_DIR="/opt/app/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXECUTION_ID="${TIMESTAMP}_$(basename $PATCH_FILE .patch)"

echo "Execution ID: $EXECUTION_ID"

# Create execution directory
rm -rf "$EXECUTION_DIR"
mkdir -p "$EXECUTION_DIR"

# Copy project to execution directory
echo "Copying project files..."
cp -r "$PROJECT_PATH"/* "$EXECUTION_DIR/" 2>/dev/null || {
    echo "ERROR: Failed to copy project files from $PROJECT_PATH"
    exit 1
}

# Apply patch
echo "Applying patch..."
/opt/app/apply_patch.sh "$PATCH_FILE" "$BASE_COMMIT" "$EXECUTION_DIR" || {
    echo "ERROR: Patch application failed"
    exit 1
}

# Execute tests
echo "Executing tests..."
/opt/app/execute_tests.sh "$EXECUTION_DIR" || {
    echo "WARNING: Test execution had issues"
}

# Generate final report
REPORT_FILE="$RESULTS_DIR/execution_report_${EXECUTION_ID}.json"
echo "{"
echo "  \"execution_id\": \"$EXECUTION_ID\","
echo "  \"timestamp\": \"$(date -Iseconds)\","
echo "  \"patch_file\": \"$PATCH_FILE\","
echo "  \"base_commit\": \"$BASE_COMMIT\","
echo "  \"project_path\": \"$PROJECT_PATH\","
echo "  \"execution_directory\": \"$EXECUTION_DIR\","
echo "  \"results_directory\": \"$RESULTS_DIR\","
if [[ -f "$RESULTS_DIR/test_results.json" ]]; then
    echo "  \"test_results\": $(cat $RESULTS_DIR/test_results.json),"
fi
echo "  \"status\": \"completed\""
echo "}" > "$REPORT_FILE"

echo "=== Execution Complete ==="
echo "Report: $REPORT_FILE"

# Cleanup if requested
if [[ "$KEEP_ARTIFACTS" == "false" ]]; then
    /opt/app/cleanup.sh "$EXECUTION_DIR" "false"
fi

' > /opt/app/orchestrate.sh && \
    chmod +x /opt/app/orchestrate.sh

# Set proper permissions
USER root
RUN chown -R elixir:elixir /opt/app
USER elixir

# Configure resource limits through environment
ENV ELIXIR_ERL_OPTIONS="+fnu +A 4"
ENV ERL_FLAGS="+fnu +A 4"

# Test the instance layer setup
RUN echo "=== Instance Layer Verification ===" && \
    echo "Scripts available:" && \
    ls -la /opt/app/*.sh && \
    echo "Directory structure:" && \
    ls -la /opt/app/ && \
    echo "Execution environment ready"

# Health check for instance layer  
HEALTHCHECK --interval=30s --timeout=20s --start-period=15s --retries=3 \
    CMD /opt/app/cleanup.sh /tmp true > /dev/null && echo "Instance layer healthy" || exit 1

# Working directory for execution
WORKDIR /opt/app

# Default command
CMD ["/bin/bash"]

# Labels
LABEL swe-bench.layer="instance"  
LABEL swe-bench.execution="ready"
LABEL swe-bench.timeout="300"
LABEL swe-bench.memory_limit="4GB"