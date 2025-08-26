# Dockerfile for distributed Elixir testing nodes
# Extends base SWE-bench container with Erlang distribution support

FROM swe-bench/instance:latest

# Install additional distributed testing dependencies
RUN apt-get update && apt-get install -y \
    iproute2 \
    net-tools \
    telnet \
    && rm -rf /var/lib/apt/lists/*

# Configure Erlang distribution
ENV ERL_FLAGS="+K true +A 64 +sbtu +sbwt very_short +swt very_low"
ENV ERLANG_DISTRIBUTION=true
ENV EPMD_ENABLED=false

# Expose Erlang distribution ports
EXPOSE 9000
EXPOSE 4369

# Copy distributed testing configuration
COPY docker/distributed-node-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/distributed-node-entrypoint.sh

# Set distributed node entrypoint
ENTRYPOINT ["/usr/local/bin/distributed-node-entrypoint.sh"]
CMD ["mix", "test", "--include", "distributed"]