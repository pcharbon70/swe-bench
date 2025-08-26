#!/bin/bash
# Entrypoint script for distributed Elixir testing nodes
# Configures Erlang distribution and starts the node

set -e

# Default values
NODE_NAME=${NODE_NAME:-"node@localhost"}
CLUSTER_COOKIE=${CLUSTER_COOKIE:-"swe_bench_default_cookie"}
CLUSTER_SIZE=${CLUSTER_SIZE:-1}

echo "Starting distributed Elixir node: $NODE_NAME"
echo "Cluster cookie: $CLUSTER_COOKIE"
echo "Expected cluster size: $CLUSTER_SIZE"

# Configure Erlang distribution
export ERLANG_COOKIE=$CLUSTER_COOKIE

# Wait for other nodes if we're part of a larger cluster
if [ "$CLUSTER_SIZE" -gt 1 ] && [ "$NODE_NAME" != "node1@node1" ]; then
    echo "Waiting for cluster formation..."
    sleep 10
fi

# Start Erlang distribution
if [ "$EPMD_ENABLED" = "false" ]; then
    echo "Starting node without EPMD (EPMDless mode)"
    ERL_FLAGS="$ERL_FLAGS -start_epmd false -epmd_module Kernel.Utils" 
else
    echo "Starting node with EPMD"
    # Start EPMD if needed
    epmd -daemon
fi

# Configure node networking
ERL_FLAGS="$ERL_FLAGS -kernel inet_dist_listen_min 9000 inet_dist_listen_max 9000"
ERL_FLAGS="$ERL_FLAGS -name $NODE_NAME"
ERL_FLAGS="$ERL_FLAGS -setcookie $CLUSTER_COOKIE"

export ERL_FLAGS

echo "Erlang flags: $ERL_FLAGS"

# Health check setup
echo "Node $NODE_NAME ready for distributed testing"

# Execute the provided command
exec "$@"