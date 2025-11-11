#!/usr/bin/env python

"""
ThorVG-Godot Build Configuration
Builds optimized Lottie animation extension for Godot Engine
"""

import os
import sys
import shutil

env = SConscript("thirdparty/godot-cpp/SConstruct")

# Source files
env.Append(CPPPATH=["src/"])
sources = Glob("src/*.cpp")

# ThorVG integration - Platform-specific library handling
env.Append(CPPPATH=["thirdparty/thorvg/inc"])

# Determine ThorVG library location and linking method
if env["platform"] == "web":
    thorvg_lib_dir = os.path.join("thirdparty", "thorvg", "build_wasm", "src")
else:
    thorvg_lib_dir = os.path.join("thirdparty", "thorvg", "builddir", "src")

if os.path.exists(thorvg_lib_dir):
    env.Append(LIBPATH=[thorvg_lib_dir])
    
    # Platform-specific library files
    platform_libs = {
        "windows": [
            ("thorvg.lib", lambda: env.Append(LIBS=["thorvg"])),
            ("libthorvg.a", lambda: env.Append(LINKFLAGS=[os.path.join(thorvg_lib_dir, "libthorvg.a")]))
        ],
        "linux": [
            ("libthorvg.so", lambda: env.Append(LIBS=["thorvg"])),
            ("libthorvg.a", lambda: env.Append(LIBS=["thorvg"]))
        ],
        "macos": [
            ("libthorvg.dylib", lambda: env.Append(LIBS=["thorvg"])),
            ("libthorvg.a", lambda: env.Append(LIBS=["thorvg"]))
        ]
    }
    
    # Try to find and link appropriate library for current platform
    lib_found = False
    if env["platform"] in platform_libs:
        for lib_name, link_func in platform_libs[env["platform"]]:
            lib_path = os.path.join(thorvg_lib_dir, lib_name)
            if os.path.isfile(lib_path):
                link_func()
                lib_found = True
                print("Using ThorVG library: {}".format(lib_name))
                break
    
    if not lib_found:
        print("Warning: ThorVG library not found in {}".format(thorvg_lib_dir))
        print("Available files:", os.listdir(thorvg_lib_dir) if os.path.exists(thorvg_lib_dir) else "Directory not found")
else:
    print("Error: ThorVG build directory not found: {}".format(thorvg_lib_dir))
    print("Please run the appropriate build script first:")
    print("  Windows: build_thorvg.bat") 
    print("  Linux/macOS: ./build_thorvg.sh")

# Output library name
if env["platform"] == "macos":
    library = env.SharedLibrary(
        "demo/addons/godot_lottie/bin/libgodot_lottie.{}.{}.framework/libgodot_lottie.{}.{}".format(
            env["platform"], env["target"], env["platform"], env["target"]
        ),
        source=sources,
    )
else:
    library = env.SharedLibrary(
        "demo/addons/godot_lottie/bin/libgodot_lottie{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
        source=sources,
    )

Default(library)

# Copy ThorVG runtime DLL on Windows (Linux/macOS use static linking)
if env["platform"] == "windows":
    thorvg_runtime_dir = thorvg_lib_dir if 'thorvg_lib_dir' in locals() else os.path.join("thirdparty", "thorvg", "builddir", "src")
    thorvg_runtime = os.path.join(thorvg_runtime_dir, "thorvg-1.dll")
    dest_dir = os.path.join("demo", "addons", "godot_lottie", "bin")
    dest_dll = os.path.join(dest_dir, "thorvg-1.dll")

    if os.path.isfile(thorvg_runtime):
        def _copy_thorvg_dll(target, source, env):
            try:
                if not os.path.isdir(dest_dir):
                    os.makedirs(dest_dir, exist_ok=True)
                shutil.copy2(thorvg_runtime, dest_dll)
                print("Copied ThorVG runtime to {}".format(dest_dll))
            except Exception as e:
                print("Warning: Failed to copy ThorVG runtime DLL: {}".format(e))

        try:
            env.AddPostAction(library, _copy_thorvg_dll)
        except Exception:
            # Fallback: immediate copy
            try:
                if not os.path.isdir(dest_dir):
                    os.makedirs(dest_dir, exist_ok=True)
                shutil.copy2(thorvg_runtime, dest_dll)
                print("Copied ThorVG runtime to {} (fallback)".format(dest_dll))
            except Exception as e:
                print("Warning: Could not copy ThorVG runtime: {}".format(e))
