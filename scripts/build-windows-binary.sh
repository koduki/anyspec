#!/usr/bin/env bash
#
# Build anyspec Spinel binary on Windows (MSYS2 / RubyInstaller Devkit)
#
# Run this script in MSYS2 UCRT64 shell or RubyInstaller Devkit shell.
#
# Prerequisites:
#   1. MSYS2 with UCRT64 toolchain, or RubyInstaller with Devkit
#   2. Required packages:
#      pacman -S --needed make diffutils curl tar git mingw-w64-ucrt-x86_64-gcc
#      pacman -S --needed mingw-w64-ucrt-x86_64-ruby  # MSYS2 only; Devkit has its own
#   3. Spinel compiler built and available (see below)
#
# To build Spinel (one-time setup):
#   git clone https://github.com/matz/spinel.git
#   cd spinel
#   make deps && make
#   # Optionally: make install PREFIX=/usr/local
#
# Usage:
#   ./scripts/build-windows-binary.sh
#
# Output:
#   dist/anyspec.exe - The standalone Windows executable
#
# Note: This produces a WINDOWS NATIVE binary (.exe).
#       The 'oci' CLI must be installed separately in the target environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/dist"

echo "======================================================="
echo "  anyspec Windows Binary Builder (MSYS2/Devkit)"
echo "======================================================="
echo ""
echo "Project root: ${PROJECT_ROOT}"
echo "Output directory: ${OUTPUT_DIR}"

# Check we're on Windows/MSYS2
if [[ "${OSTYPE}" != "msys" && "${OSTYPE}" != "mingw"* && "${OSTYPE}" != "cygwin" ]]; then
    echo ""
    echo "Error: This script is for Windows (MSYS2/Devkit) only."
    echo "For Linux builds, use: ./scripts/build-linux-binary.sh"
    echo "For macOS native builds, use: spin build (after installing Spinel on macOS)"
    exit 1
fi

# Check for Spinel
echo ""
echo "=== Checking for Spinel ==="
if ! command -v spinel &> /dev/null; then
    echo ""
    echo "Error: Spinel compiler not found in PATH."
    echo ""
    echo "To build Spinel on Windows, run these commands in MSYS2 UCRT64 shell:"
    echo ""
    echo "    # Install dependencies"
    echo "    pacman -S --needed make diffutils curl tar git mingw-w64-ucrt-x86_64-gcc"
    echo "    pacman -S --needed mingw-w64-ucrt-x86_64-ruby  # MSYS2 only"
    echo ""
    echo "    # Clone and build Spinel"
    echo "    git clone https://github.com/matz/spinel.git"
    echo "    cd spinel"
    echo "    make deps && make"
    echo ""
    echo "    # Add to PATH or install"
    echo "    export PATH=\"\$PWD/bin:\$PATH\""
    echo "    # or: make install PREFIX=/usr/local"
    echo ""
    exit 1
fi

SPINEL_VERSION=$(spinel --version 2>&1 || echo "unknown")
echo "Found Spinel: ${SPINEL_VERSION}"

# Check for spin
if ! command -v spin &> /dev/null; then
    echo "Error: spin command not found. It should be installed alongside spinel."
    exit 1
fi

SPIN_VERSION=$(spin --version 2>&1 || echo "unknown")
echo "Found spin: ${SPIN_VERSION}"

# Set SPINEL_SHELL if not set (spin needs a POSIX shell on Windows)
if [[ -z "${SPINEL_SHELL:-}" ]]; then
    if command -v /usr/bin/sh &> /dev/null; then
        export SPINEL_SHELL="/usr/bin/sh"
        echo "Set SPINEL_SHELL=${SPINEL_SHELL}"
    fi
fi

# Build anyspec
echo ""
echo "=== Building anyspec ==="
cd "${PROJECT_ROOT}"

spin build

# Check output
BUILD_OUTPUT="${PROJECT_ROOT}/build/bin/anyspec.exe"
if [[ ! -f "${BUILD_OUTPUT}" ]]; then
    # Try without .exe (in case spin doesn't add it)
    BUILD_OUTPUT="${PROJECT_ROOT}/build/bin/anyspec"
    if [[ ! -f "${BUILD_OUTPUT}" ]]; then
        echo "Error: Build output not found"
        exit 1
    fi
fi

# Create output directory and copy
echo ""
echo "=== Copying to output directory ==="
mkdir -p "${OUTPUT_DIR}"

OUTPUT_FILE="${OUTPUT_DIR}/anyspec.exe"
cp "${BUILD_OUTPUT}" "${OUTPUT_FILE}"

# Make executable (though Windows doesn't use this bit)
chmod +x "${OUTPUT_FILE}" 2>/dev/null || true

# Verify
echo ""
echo "=== Build complete ==="
echo ""
echo "Binary: ${OUTPUT_FILE}"
ls -lh "${OUTPUT_FILE}"
echo ""

# Try to run version check
echo "Testing binary..."
if "${OUTPUT_FILE}" --version 2>/dev/null; then
    echo ""
else
    echo "(Could not verify binary)"
fi

echo ""
echo "To use anyspec:"
echo "  1. Ensure 'oci' CLI is installed and configured"
echo "  2. Run: ${OUTPUT_FILE} check <spec.yml>"
echo ""
echo "Note: The 'oci' CLI is NOT bundled with anyspec."
echo "      Install it: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
