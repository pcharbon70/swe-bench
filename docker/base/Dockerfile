# Base Docker Image for BEAM VM Optimization
# This image provides the foundational runtime for SWE-bench-Elixir evaluation

FROM alpine:3.19

# Metadata
LABEL maintainer="SWE-bench-Elixir"
LABEL description="Base BEAM VM image with Elixir/OTP runtime"
LABEL version="1.0.0"

# Set environment variables for deterministic behavior
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=UTC

# Install system dependencies required for Elixir/OTP
RUN apk add --no-cache \
    # Core system utilities
    bash \
    curl \
    git \
    # Build essentials for native dependencies
    build-base \
    # SSL/TLS support
    openssl \
    openssl-dev \
    # PostgreSQL client for database operations
    postgresql-client \
    # Network utilities
    iproute2 \
    # Process utilities  
    procps \
    # Archive utilities
    tar \
    gzip \
    # Text processing
    grep \
    sed \
    awk \
    # Timezone data
    tzdata

# Configure timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Create application user for security (non-root execution)
RUN addgroup -g 1000 -S elixir && \
    adduser -u 1000 -S elixir -G elixir -h /opt/app -s /bin/bash

# Install Erlang/OTP 27 from Erlang Solutions repository
RUN apk add --no-cache \
    erlang=27.2-r0 \
    erlang-dev=27.2-r0 \
    erlang-crypto=27.2-r0 \
    erlang-ssl=27.2-r0 \
    erlang-public-key=27.2-r0 \
    erlang-asn1=27.2-r0 \
    erlang-sasl=27.2-r0 \
    erlang-erl-interface=27.2-r0 \
    erlang-tools=27.2-r0 \
    erlang-runtime-tools=27.2-r0 \
    erlang-observer=27.2-r0 \
    erlang-odbc=27.2-r0 \
    erlang-eldap=27.2-r0 \
    erlang-xmerl=27.2-r0 \
    erlang-parsetools=27.2-r0 \
    erlang-eunit=27.2-r0 \
    erlang-syntax-tools=27.2-r0 || \
    # Fallback to available versions if specific versions aren't available
    apk add --no-cache \
    erlang \
    erlang-dev \
    erlang-crypto \
    erlang-ssl \
    erlang-public-key \
    erlang-asn1 \
    erlang-sasl \
    erlang-erl-interface \
    erlang-tools \
    erlang-runtime-tools \
    erlang-observer \
    erlang-odbc \
    erlang-eldap \
    erlang-xmerl \
    erlang-parsetools \
    erlang-eunit \
    erlang-syntax-tools

# Install Elixir 1.16
RUN apk add --no-cache elixir=1.16.2-r0 || \
    apk add --no-cache elixir

# Configure EPMD for container isolation
# EPMD (Erlang Port Mapper Daemon) needs special configuration for containers
ENV ERL_EPMD_ADDRESS=127.0.0.1
ENV ERL_EPMD_PORT=4369

# Create EPMD configuration
RUN mkdir -p /etc/erlang && \
    echo "# EPMD Configuration for Container Isolation" > /etc/erlang/epmd.conf && \
    echo "address 127.0.0.1" >> /etc/erlang/epmd.conf && \
    echo "port 4369" >> /etc/erlang/epmd.conf

# Set up application directory structure
RUN mkdir -p /opt/app /opt/app/deps /opt/app/_build /opt/app/tmp && \
    chown -R elixir:elixir /opt/app

# Configure Mix environment for container usage
ENV MIX_ENV=test
ENV MIX_HOME=/opt/app/.mix
ENV HEX_HOME=/opt/app/.hex

# Create Mix and Hex directories
RUN mkdir -p $MIX_HOME $HEX_HOME && \
    chown -R elixir:elixir $MIX_HOME $HEX_HOME

# Switch to application user
USER elixir
WORKDIR /opt/app

# Install Hex and Rebar for dependency management
RUN mix local.hex --force && \
    mix local.rebar --force

# Verify installations and display versions
RUN echo "=== Installation Verification ===" && \
    echo "Erlang/OTP version:" && \
    erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell && \
    echo "Elixir version:" && \
    elixir --version && \
    echo "Mix version:" && \
    mix --version && \
    echo "Hex version:" && \
    mix hex.info && \
    echo "=== Environment Variables ===" && \
    env | grep -E "(LANG|LC_ALL|TZ|MIX_|HEX_|ERL_)" | sort && \
    echo "=== Directory Structure ===" && \
    ls -la /opt/app/

# Configure healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD elixir -e "IO.puts(:ok)" || exit 1

# Default command to keep container running
CMD ["/bin/bash"]

# Expose EPMD port for Erlang distribution (if needed)
EXPOSE 4369

# Add labels for container management
LABEL swe-bench.layer="base"
LABEL swe-bench.version="1.0.0"
LABEL swe-bench.elixir.version="1.16"
LABEL swe-bench.otp.version="27"