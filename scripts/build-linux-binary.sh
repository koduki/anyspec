#!/usr/bin/env bash
#
# Build anyspec Spinel binary using Docker
#
# This script builds a Linux binary from macOS (or any Docker-capable host).
# The resulting binary runs on Linux x86-64 or arm64 depending on your build platform.
#
# Requirements:
#   - Docker (Docker Desktop, Colima, OrbStack, or similar)
#
# Usage:
#   ./scripts/build-linux-binary.sh                    # Build for current platform
#   ./scripts/build-linux-binary.sh --platform linux/amd64   # Force x86-64
#   ./scripts/build-linux-binary.sh --platform linux/arm64   # Force ARM64
#
# Output:
#   dist/anyspec - The standalone Linux binary
#
# Note: This produces a LINUX binary. For native macOS binaries,
# install Spinel on macOS and run `spin build` directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
PLATFORM=""
OUTPUT_DIR="${PROJECT_ROOT}/dist"
IMAGE_NAME="anyspec-builder"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build anyspec Spinel binary using Docker"
            echo ""
            echo "Options:"
            echo "  --platform PLATFORM   Target platform (linux/amd64 or linux/arm64)"
            echo "  --output-dir DIR      Output directory (default: dist/)"
            echo "  -h, --help            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                           # Build for current platform"
            echo "  $0 --platform linux/amd64    # Build x86-64 binary"
            echo "  $0 --platform linux/arm64    # Build ARM64 binary"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    echo "Please install Docker Desktop, Colima, or OrbStack"
    exit 1
fi

# Check Docker daemon is running
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    echo "Please start Docker and try again"
    exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo "=== Building anyspec Spinel binary ==="
echo "Project root: ${PROJECT_ROOT}"
echo "Output directory: ${OUTPUT_DIR}"

# Build Docker image
cd "${PROJECT_ROOT}"

BUILD_ARGS=()
if [[ -n "${PLATFORM}" ]]; then
    BUILD_ARGS+=(--platform "${PLATFORM}")
    echo "Target platform: ${PLATFORM}"
else
    echo "Target platform: (native)"
fi

echo ""
echo "Building Docker image..."
docker build \
    "${BUILD_ARGS[@]}" \
    --target extractor \
    -t "${IMAGE_NAME}" \
    .

echo ""
echo "Extracting binary..."
docker run --rm \
    "${BUILD_ARGS[@]}" \
    -v "${OUTPUT_DIR}:/output" \
    "${IMAGE_NAME}"

# Verify output
if [[ -f "${OUTPUT_DIR}/anyspec" ]]; then
    echo ""
    echo "=== Build successful ==="
    echo "Binary: ${OUTPUT_DIR}/anyspec"
    ls -lh "${OUTPUT_DIR}/anyspec"
    
    # Show file type
    echo ""
    echo "Binary type:"
    file "${OUTPUT_DIR}/anyspec" || true
else
    echo ""
    echo "Error: Binary was not created"
    exit 1
fi

echo ""
echo "Note: This is a LINUX binary. To run it:"
echo "  - On Linux: ./dist/anyspec --help"
echo "  - On macOS: Use Docker or a Linux VM"
echo "  - Requires 'oci' CLI to be installed in the target environment"
