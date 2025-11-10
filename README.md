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

**Want to test without building?** The `demo/` folder contains a ready-to-run Godot project:

1. Open `demo/project.godot` in Godot Engine
2.  Enable the plugin: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. Run immediately - no compilation required!
4. Test multiple Lottie animations and performance demos

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

```bash
pip install meson ninja
```

### 3. Build ThorVG

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

If you prefer to build ThorVG manually with custom options:

```bash
cd thirdparty/thorvg
meson setup builddir
meson configure builddir -Dsimd=true -Dthreads=true -Dloaders=lottie
meson compile -C builddir
```

Additional ThorVG build options:
- `-Dengines=sw` — Software renderer only (default for this integration)
- `-Dbindings=capi` — C API bindings (required)
- `-Dstatic=true` — Static library build
- `-Dtests=false` — Disable tests and examples

### 4. Build Godot Extension

```bash
# Windows
scons platform=windows target=template_release

# Linux
scons platform=linux target=template_release

# macOS
scons platform=macos target=template_release
```

## Build Configuration

### ThorVG Optimizations

The build system configures ThorVG with the following optimizations:

- **SIMD**: Automatic detection and enablement of CPU vectorization
- **Multi-threading**: Task scheduler with configurable worker threads
- **Partial rendering**: Smart rendering optimizations
- **Lottie loader only**: Minimal build excluding unnecessary formats
- **Release mode**: Maximum compiler optimizations

### Rendering Pipeline

The integration uses a hybrid rendering approach:

1. **Vector Processing**: ThorVG parses Lottie JSON and builds internal vector representation
2. **CPU Rasterization**: ThorVG software renderer rasterizes vectors to RGBA8888 pixel buffer using CPU
3. **Format Conversion**: RGBA8888 data is converted to RGB format compatible with Godot's texture system
4. **GPU Upload**: RGB texture data is uploaded to Godot's GPU canvas via `draw_texture()` calls
5. **GPU Compositing**: Godot handles final compositing, blending, and display using GPU shaders

This approach leverages ThorVG's optimized CPU vector processing while maintaining compatibility with Godot's rendering pipeline.

### Supported Platforms

| Platform | Architecture | Compiler | Status |
|----------|-------------|----------|---------|
| Windows  | x86_64      | MSVC     | ✓ Tested |
| Linux    | x86_64      | GCC/Clang| ? Supported(need test) |
| macOS    | x86_64/ARM64| Clang    | ? Supported(need test) |

## Project Structure

```
thorvg-godot/
├── build_thorvg.bat         # Windows build script
├── build_thorvg.sh          # Linux/macOS build script  
├── src/                     # Extension source code
│   ├── lottie_animation.cpp # Main animation class
│   ├── lottie_animation.h   # Header file
│   └── register_types.cpp   # Godot registration
├── thirdparty/thorvg/       # ThorVG submodule
├── demo/                    # Example project
└── godot-cpp/               # Godot C++ bindings
```

## Usage

1. **Copy the extension**: Copy the built extension to your Godot project's `addons/` folder
2. **Enable the plugin**: Go to Project → Project Settings → Plugins and enable "Godot Lottie"
3. **Add LottieAnimation node**: Add `LottieAnimation` nodes to your scene
4. **Set animation path**: Set the `animation_path` property to your Lottie JSON file

## API Reference

Detailed API documentation for the provided nodes and resources is available in this repository. It includes the `LottieAnimation` node reference (properties, methods, signals) and usage examples in GDScript.

See: **[API.md](API.md)** for a complete and up-to-date reference.

## Performance Tips

- Use appropriate `render_size` values (avoid excessive resolution)
- Enable `SmartRender` engine option for better performance
- Consider frame caching for frequently used animations
- Use multi-threading when rendering multiple animations (compile web using no threads is recommended)

## Troubleshooting

### Build Issues

**Meson not found:**
```bash
pip install --user meson ninja
# Add Python Scripts directory to PATH
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