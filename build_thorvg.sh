#!/bin/bash

# ThorVG Build Script for Linux/macOS
# Builds optimized ThorVG with multi-threading, SIMD, and Lottie-only support

set -e  # Exit on any error

echo "========================================"
echo "Building optimized ThorVG library"
echo "Platform: $(uname -s) $(uname -m)"
echo "Target: Lottie animations only"
echo "Optimizations: Multi-threading, SIMD, Partial rendering"
echo "========================================"
echo

# Check for required build tools
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 not found"
    echo "Please install Python 3.7 or later"
    exit 1
fi

if ! meson --version &> /dev/null; then
    echo "ERROR: Meson build system not found"
    echo
    echo "To install:"
    echo "  pip3 install --user meson ninja"
    echo
    echo "Or use your package manager:"
    echo "  Ubuntu/Debian: sudo apt install meson ninja-build"
    echo "  macOS: brew install meson ninja"
    echo
    exit 1
fi

MESON_VERSION=$(meson --version)
echo "Build tools verified:"
echo "  Python: $(python3 --version 2>&1)"
echo "  Meson: $MESON_VERSION"
echo

# Navigate to ThorVG directory
cd thirdparty/thorvg

# Clean previous build
if [ -d "builddir" ]; then
    echo "Cleaning previous build directory..."
    rm -rf builddir
fi

# Detect CPU core count for parallel compilation
if command -v nproc &> /dev/null; then
    CORES=$(nproc)
elif [ "$(uname)" == "Darwin" ]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=4  # Fallback
fi

echo "Detected $CORES CPU cores for parallel compilation"
echo

# Configure build with optimal settings for Lottie rendering
echo "Configuring ThorVG build with optimizations..."

# Detect platform and set threads configuration
# ARM Mac requires threads=false for compatibility
if [ "$(uname)" == "Darwin" ] && [ "$(uname -m)" == "arm64" ]; then
    THREADS_OPTION="-Dthreads=false"
    echo "ARM Mac detected: Setting threads=false"
else
    THREADS_OPTION="-Dthreads=true"
    echo "Non-ARM platform: Setting threads=true"
fi

meson setup builddir \
    -Dbuildtype=release \
    -Doptimization=3 \
    -Db_ndebug=true \
    -Ddefault_library=static \
    -Dsimd=true \
    $THREADS_OPTION \
    -Dpartial=true \
    -Dengines=sw \
    -Dloaders=lottie \
    -Dbindings=capi \
    -Dexamples=false \
    -Dtests=false \
    --backend=ninja \
    --wipe

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Meson configuration failed"
    exit 1
fi

# Build with all available CPU cores
echo
echo "Building ThorVG using $CORES parallel jobs..."
meson compile -C builddir -j $CORES

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: ThorVG build failed"
    exit 1
fi

echo
echo "========================================"
echo "ThorVG build completed successfully!"
echo
echo "Output location: thirdparty/thorvg/builddir/src/"
echo "Library file: libthorvg.a (static library)"
echo
echo "Enabled optimizations:"
echo "  ✓ Multi-threading: Task scheduler with $CORES workers"
echo "  ✓ SIMD instructions: CPU vectorization enabled"
echo "  ✓ Partial rendering: Smart update optimizations"  
echo "  ✓ Lottie loader: JSON animation support only"
echo "  ✓ Release mode: Maximum compiler optimizations (-O3)"
echo "  ✓ Static linking: No runtime dependencies"
echo "========================================"
echo
echo "Next step: Build Godot extension with SCons"
echo "  SCons platform=linux target=template_release  # Linux"
echo "  SCons platform=macos target=template_release  # macOS"
