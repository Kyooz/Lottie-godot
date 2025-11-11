# ThorVG-Godot

High-performance Lottie animation rendering for Godot Engine 4.3+ using optimized ThorVG backend.

![ThorVG Godot Demo](thor-lottie.gif)

*Lottie animations running at 146 FPS with ThorVG's optimized multi-threaded rendering*

Note: this is an integration demo for personal use, so features may fail/be incomplete and may not perform as expected.

## Features

- **Ready-to-use LottieAnimation**: Drop-in Godot node for seamless Lottie integration in your scenes
- **Hybrid CPU-GPU rendering**: ThorVG rasterizes vector data to RGBA8888 format in CPU memory, then converts to RGB texture for Godot's draw system
- **Multi-threaded rendering**: Parallel processing using all available CPU cores
- **SIMD optimizations**: AVX/SSE (x86/x64) or NEON (ARM) vectorization
- **Smart rendering**: Automatic partial rendering optimizations
- **Lottie-focused**: Optimized build with only necessary loaders
- **Cross-platform**: Windows, Linux, and macOS support

## Quick Demo

**Want to test without building?** The `demo/` folder contains a ready-to-run Godot project with **pre-built binaries for Windows x64**:

1. Open `demo/project.godot` in Godot Engine 4.3+
2. **Enable the plugin**: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. Run immediately - no compilation required!
4. Test multiple Lottie animations and performance demos

> **Note**: For Linux and macOS, you'll need to build the extension first (see Installation section below).

## Prerequisites

- **Python 3.7+** with pip
- **Git**
- **C++ Compiler**:
  - Windows: Visual Studio 2019+ or Build Tools
  - Linux: GCC 8+ or Clang 10+
  - macOS: Xcode Command Line Tools

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/Kyooz/thorvg-godot.git
cd thorvg-godot
git submodule update --init --recursive
```

### 2. Install Build Dependencies

**From the project root directory (`thorvg-godot/`):**

**All platforms:**
```bash
pip install meson ninja
```

> **Note**: On Windows, Meson and Ninja will be automatically added to your PATH by the build script if not already installed.

### 3. Build ThorVG

**From the project root directory (`thorvg-godot/`):**

**Option A: Automated Build (Recommended)**

**Windows:**
```cmd
build_thorvg.bat
```

**Linux/macOS:**
```bash
./build_thorvg.sh
```

**Option B: Manual Build (ThorVG Standard Process)**

If you prefer to build ThorVG manually with custom options.

**From the project root directory (`thorvg-godot/`):**

**Windows:**
```bash
cd thirdparty/thorvg
python -m meson setup builddir -Dbuildtype=release -Dsimd=true -Dthreads=true -Dloaders=lottie -Dbindings=capi
python -m meson compile -C builddir
cd ../..
```

**Linux/macOS:**
```bash
cd thirdparty/thorvg
python3 -m meson setup builddir -Dbuildtype=release -Ddefault_library=static -Dsimd=true -Dthreads=true -Dloaders=lottie -Dbindings=capi
python3 -m meson compile -C builddir
cd ../..
```

**Additional ThorVG build options:**

The automated scripts already include optimal settings. For manual builds, you can customize with these flags:

- `-Dengines=sw` — Software renderer only (already enabled)
- `-Dbindings=capi` — C API bindings (required, already enabled)
- `-Ddefault_library=static` — Static library build (Linux/macOS default)
- `-Ddefault_library=shared` — Shared library build (Windows default)
- `-Dtests=false` — Disable tests and examples
- `-Dpartial=true` — Enable partial rendering optimizations (already enabled)
- `-Doptimization=3` — Maximum optimization level (already enabled)

**Example custom build:**

For development/debugging, you can build with custom options:

```bash
cd thirdparty/thorvg

# Step 1: Configure build with custom options
python3 -m meson setup builddir \
    -Dbuildtype=debugoptimized \
    -Ddefault_library=static \
    -Dsimd=true \
    -Dthreads=true \
    -Dloaders=lottie \
    -Dbindings=capi

# Step 2: Compile the library
python3 -m meson compile -C builddir

cd ../..
```

### 4. Build Godot Extension

**From the project root directory (`thorvg-godot/`):**

```bash
# Windows
python -m SCons platform=windows target=template_debug
python -m SCons platform=windows target=template_release

# Linux
python -m SCons platform=linux target=template_debug
python -m SCons platform=linux target=template_release

# macOS
python -m SCons platform=macos target=template_debug
python -m SCons platform=macos target=template_release
```

> **Note**: On Windows, the build automatically copies `thorvg-1.dll` to the addon's bin directory. Linux and macOS use static linking and don't require runtime libraries.

## Build Configuration

### ThorVG Optimizations

The build system configures ThorVG with the following optimizations:

- **SIMD**: Automatic detection and enablement of CPU vectorization
- **Multi-threading**: Task scheduler with configurable worker threads
- **Partial rendering**: Smart rendering optimizations
- **Lottie loader only**: Minimal build excluding unnecessary formats
- **Release mode**: Maximum compiler optimizations

### Rendering Pipeline

The integration uses a hybrid CPU-GPU rendering approach:

1. **Vector Processing**: ThorVG parses Lottie JSON and builds internal vector representation
2. **CPU Rasterization**: ThorVG software renderer rasterizes vectors to ARGB pixel buffer using CPU with SIMD optimizations
3. **Format Conversion**: ARGB data is converted to RGBA format via optimized SIMD routines (SSSE3/NEON)
4. **GPU Upload**: RGBA texture data is uploaded to Godot's rendering system via `ImageTexture`
5. **GPU Compositing**: Godot handles final compositing, blending, and display using GPU shaders

This approach leverages ThorVG's optimized CPU vector processing while maintaining compatibility with Godot's rendering pipeline.

### Supported Platforms

| Platform | Architecture | ThorVG Library | Compiler | Status |
|----------|-------------|----------------|----------|---------|
| Windows  | x86_64      | thorvg-1.dll (shared) | MSVC | ✓ Tested |
| Linux    | x86_64      | libthorvg.a (static) | GCC/Clang| ⚠ Needs testing |
| macOS    | x86_64/ARM64| libthorvg.a (static) | Clang | ⚠ Needs testing |

## Project Structure

```
thorvg-godot/
├── build_thorvg.bat         # Windows build script
├── build_thorvg.sh          # Linux/macOS build script  
├── src/                     # Extension source code
│   ├── lottie_animation.cpp # Main animation class
│   ├── lottie_animation.h   # Header file
│   └── register_types.cpp   # Godot registration
├── demo/                    # Example project with plugin
│   └── addons/
│       └── godot_lottie/    # ← Plugin folder to copy to your project
└── thirdparty/              # Third-party dependencies
    ├── godot-cpp/           # Godot C++ bindings
    └── thorvg/              # ThorVG vector graphics library
```

## Usage

1. **Copy the plugin**: Copy the `demo/addons/godot_lottie/` folder to your Godot project's `addons/` directory
2. **Enable the plugin**: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. **Add LottieAnimation node**: Add `LottieAnimation` nodes to your scene
4. **Set animation path**: Set the `animation_path` property to your Lottie JSON file

## API Reference

Detailed API documentation for the provided nodes and resources is available in this repository. It includes the `LottieAnimation` node reference (properties, methods, signals) and usage examples in GDScript.

See: **[API.md](API.md)** for a complete and up-to-date reference.

## Performance Tips

- Use appropriate `render_size` values (avoid excessive resolution)
- Enable `use_worker_thread` for better performance on multi-core systems
- Consider frame caching for frequently used animations
- Adjust `engine_option` (0=Default, 1=SmartRender) based on your needs
- On web builds, disable worker threads for better compatibility

## Troubleshooting

### Build Issues

**Meson not found (Windows):**
The build script will automatically install Meson if missing. If you encounter issues:
```bash
pip install --user meson ninja
# Restart terminal to reload PATH
```

**Meson not found (Linux/macOS):**
```bash
pip3 install --user meson ninja
# Or use system package manager:
# Ubuntu/Debian: sudo apt install meson ninja-build
# macOS: brew install meson ninja
```

**Compiler not found:**
- Windows: Install Visual Studio Build Tools
- Linux: `sudo apt install build-essential`
- macOS: `xcode-select --install`

**Submodule errors:**
```bash
git submodule update --init --recursive --force
```

### Runtime Issues

**Poor performance:**
- Verify SIMD is enabled in build output
- Check that multi-threading is working
- Reduce render resolution if needed

**Loading errors:**
- Ensure Lottie files are valid JSON format
- Check file path accessibility
- Verify the plugin is properly enabled

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -m 'Add new feature'`
4. Push to branch: `git push origin feature/new-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Acknowledgments

- **ThorVG Team** - High-performance vector graphics library
- **Godot Engine** - Open source game engine
- **LottieFiles** - vector animation library powered by ThorVG