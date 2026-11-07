# Dockerfile for building anyspec Spinel binary
# Produces a standalone Linux executable that can be distributed
#
# Usage:
#   docker build --target extractor -t anyspec-builder .
#   docker run --rm -v $(pwd)/dist:/output anyspec-builder
#
# The binary will be output to ./dist/anyspec
# Or use the helper script: ./scripts/build-linux-binary.sh
#
# Platform support:
#   - linux/amd64 (Intel/AMD 64-bit)
#   - linux/arm64 (ARM 64-bit, e.g., Apple Silicon via Rosetta or native ARM)
#
# Note: This produces a LINUX binary, not a native macOS binary.
# For native macOS binaries, build Spinel directly on macOS.

ARG SPINEL_VERSION=2026.10.25
ARG BASE_IMAGE=debian:bookworm-slim

# =============================================================================
# Stage 1: Build Spinel compiler from source
# =============================================================================
FROM ${BASE_IMAGE} AS spinel-builder

ARG SPINEL_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download and extract Spinel release (includes vendored prism)
RUN curl -fsSL "https://github.com/matz/spinel/releases/download/${SPINEL_VERSION}/spinel-${SPINEL_VERSION}.tar.xz" \
    -o spinel.tar.xz \
    && tar xf spinel.tar.xz \
    && rm spinel.tar.xz

WORKDIR /build/spinel-${SPINEL_VERSION}

# Build Spinel (deps already vendored in release tarball)
RUN make -j$(nproc) \
    && make install PREFIX=/usr/local

# Verify installation
RUN spinel --version && spin --version

# =============================================================================
# Stage 2: Build anyspec binary
# =============================================================================
FROM spinel-builder AS anyspec-builder

WORKDIR /app

# Copy anyspec source
COPY . .

# Build anyspec binary using spin
RUN spin build

# Verify the binary was created
RUN ls -la build/bin/anyspec && ./build/bin/anyspec --version

# =============================================================================
# Stage 3: Extract binary (minimal output stage)
# =============================================================================
FROM ${BASE_IMAGE} AS extractor

# Create output directory
RUN mkdir -p /dist

# Copy the built binary
COPY --from=anyspec-builder /app/build/bin/anyspec /dist/anyspec

# Default command: copy binary to mounted volume
CMD ["cp", "/dist/anyspec", "/output/anyspec"]

# =============================================================================
# Alternative: Run as final stage for testing
# =============================================================================
FROM ${BASE_IMAGE} AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=anyspec-builder /app/build/bin/anyspec /usr/local/bin/anyspec

# Note: oci CLI is NOT bundled - it must be installed in the target environment
# This is an intentional design decision for anyspec distribution

ENTRYPOINT ["anyspec"]
CMD ["--help"]
