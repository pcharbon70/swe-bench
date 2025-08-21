# Environment Layer for Dependency Management
# This layer handles Mix project dependencies and compilation caching

ARG BASE_IMAGE=swe-bench/base:latest
FROM ${BASE_IMAGE}

# Metadata for environment layer
LABEL swe-bench.layer="environment"
LABEL swe-bench.description="Dependency compilation and caching layer"

# Switch to root for package installation
USER root

# Install additional development tools needed for dependency compilation
RUN apk add --no-cache \
    # Additional build tools
    cmake \
    make \
    autoconf \
    automake \
    libtool \
    # Image processing (for some Elixir deps)
    imagemagick \
    imagemagick-dev \
    # XML/HTML processing
    libxml2-dev \
    libxslt-dev \
    # Additional network tools
    curl-dev \
    # Python for some build processes
    python3 \
    python3-dev \
    py3-pip

# Switch back to elixir user
USER elixir
WORKDIR /opt/app

# Configure Mix for optimal dependency handling
ENV MIX_ENV=test
ENV MIX_BUILD_ROOT=/opt/app/_build
ENV MIX_DEPS_PATH=/opt/app/deps
ENV HEX_UNSAFE_HTTPS=1
ENV HEX_UNSAFE_REGISTRY=1

# Create optimized directory structure for dependencies
RUN mkdir -p \
    $MIX_BUILD_ROOT \
    $MIX_DEPS_PATH \
    /opt/app/cache/hex \
    /opt/app/cache/git \
    /opt/app/cache/build \
    /opt/app/tmp

# Configure Git for dependency fetching (safe directory configuration)
RUN git config --global --add safe.directory '*' && \
    git config --global init.defaultBranch main

# Pre-install commonly used Hex packages to cache layer
RUN echo "Installing common Elixir dependencies..." && \
    cd /tmp && \
    echo 'defmodule CacheProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :cache_project,
      version: "0.1.0",
      elixir: "~> 1.16",
      deps: deps()
    ]
  end

  def application, do: []

  defp deps do
    [
      # Common test and development dependencies
      {:ex_unit_notifier, "~> 1.0", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.16", only: :test},
      
      # Common production dependencies  
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.0"},
      {:tesla, "~> 1.7"},
      {:req, "~> 0.4"},
      {:finch, "~> 0.16"},
      
      # Database and ORM
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      
      # Web framework
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 3.3"},
      
      # Ash framework dependencies (project-specific)
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      
      # Utility libraries
      {:nimble_csv, "~> 1.2"},
      {:timex, "~> 3.7"},
      {:uuid, "~> 1.1"}
    ]
  end
end' > mix.exs && \
    mix deps.get && \
    mix deps.compile && \
    echo "Common dependencies cached successfully"

# Clean up temporary cache project
RUN rm -rf /tmp/*

# Copy common Mix configuration templates
RUN mkdir -p /opt/app/templates

# Create a template mix.exs for umbrella projects
RUN echo 'defmodule UmbrellaTemplate.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps, do: []

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end' > /opt/app/templates/umbrella_mix.exs

# Create dependency resolution helper script
RUN echo '#!/bin/bash
# Dependency resolution helper for containerized environments
set -e

echo "=== Dependency Resolution Started ==="
echo "Project root: $(pwd)"
echo "Mix environment: $MIX_ENV"
echo "Mix build root: $MIX_BUILD_ROOT"
echo "Mix deps path: $MIX_DEPS_PATH"

# Check if this is an umbrella project
if [[ -d "apps" && -f "mix.exs" ]]; then
    echo "Detected umbrella project structure"
    export MIX_PROJECT_TYPE="umbrella"
    
    # Handle umbrella dependencies
    echo "Fetching umbrella root dependencies..."
    mix deps.get
    
    # Compile each app in dependency order
    for app_dir in apps/*/; do
        if [[ -f "$app_dir/mix.exs" ]]; then
            app_name=$(basename "$app_dir")
            echo "Processing app: $app_name"
            cd "$app_dir"
            mix deps.get
            mix deps.compile
            cd ../..
        fi
    done
    
    echo "Compiling umbrella project..."
    mix compile
else
    echo "Detected standard project structure"
    export MIX_PROJECT_TYPE="standard"
    
    # Standard project dependency handling
    mix deps.get
    mix deps.compile
    mix compile
fi

echo "=== Dependency Resolution Complete ==="
' > /opt/app/resolve_deps.sh && \
    chmod +x /opt/app/resolve_deps.sh

# Create cache warming script
RUN echo '#!/bin/bash
# Cache warming for frequently used operations
set -e

echo "=== Warming Build Caches ==="

# Warm hex package cache
mix hex.info > /dev/null 2>&1 || true

# Warm compilation cache with common patterns
echo "Warming compilation cache..."
cd /tmp
echo "defmodule WarmupModule do
  def hello, do: :world
  def pattern_match({:ok, value}), do: value
  def pattern_match({:error, reason}), do: {:error, reason}
  def pattern_match(_), do: :unknown
end" > warmup.ex

elixir -c warmup.ex > /dev/null 2>&1 || true
rm -f warmup.ex *.beam

echo "Cache warming complete"
' > /opt/app/warm_cache.sh && \
    chmod +x /opt/app/warm_cache.sh

# Set up proper permissions
USER root
RUN chown -R elixir:elixir /opt/app
USER elixir

# Configure environment for optimal dependency handling
ENV ELIXIR_ERL_OPTIONS="+fnu"
ENV ERL_FLAGS="+fnu"
ENV MIX_XDG=1

# Run cache warming
RUN /opt/app/warm_cache.sh

# Verify environment setup
RUN echo "=== Environment Layer Verification ===" && \
    echo "Mix environment: $MIX_ENV" && \
    echo "Build directories:" && \
    ls -la $MIX_BUILD_ROOT/ 2>/dev/null || echo "Build root not yet created" && \
    echo "Dependency directories:" && \
    ls -la $MIX_DEPS_PATH/ 2>/dev/null || echo "Deps path not yet created" && \
    echo "Cache directories:" && \
    ls -la /opt/app/cache/ && \
    echo "Hex status:" && \
    mix hex.info --short && \
    echo "=== Environment Layer Ready ==="

# Healthcheck for environment layer
HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=3 \
    CMD mix help > /dev/null && elixir -e "Application.loaded_applications() |> length() |> IO.puts()" || exit 1

# Default working directory
WORKDIR /opt/app

# Default command
CMD ["/bin/bash"]

# Labels
LABEL swe-bench.layer="environment"
LABEL swe-bench.cached="common-deps"
LABEL swe-bench.umbrella="supported"