#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# Tweak this if you want to use different folders, or more folders, to store your source code in.
env.Append(CPPPATH=["src/"])
sources = Glob("src/*.cpp")

# ThorVG integration
env.Append(CPPPATH=["thirdparty/thorvg/inc"])
env.Append(CPPDEFINES=["TVG_STATIC"])  # Link against static ThorVG without dllimport

# Add ThorVG library path and library (handle .lib or .a)
# Use platform-specific ThorVG build output directory
if env["platform"] == "web":
    thorvg_lib_dir = os.path.join("thirdparty", "thorvg", "build_wasm", "src")
else:
    thorvg_lib_dir = os.path.join("thirdparty", "thorvg", "builddir", "src")
if os.path.exists(thorvg_lib_dir):
    env.Append(LIBPATH=[thorvg_lib_dir])
    thorvg_lib_file_lib = os.path.join(thorvg_lib_dir, "thorvg.lib")
    thorvg_lib_file_a = os.path.join(thorvg_lib_dir, "libthorvg.a")
    if os.path.isfile(thorvg_lib_file_lib):
        # Typical MSVC static library
        env.Append(LIBS=["thorvg"])
    elif os.path.isfile(thorvg_lib_file_a):
        # Meson may output a COFF static lib with .a extension; pass full path to linker
        env.Append(LINKFLAGS=[thorvg_lib_file_a])
    else:
        print("Warning: ThorVG library not found in {}".format(thorvg_lib_dir))

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
