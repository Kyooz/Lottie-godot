@echo off
REM ThorVG Build Script for Windows
REM Builds optimized ThorVG with multi-threading, SIMD, and Lottie-only support

echo ========================================
echo Building optimized ThorVG library
echo Target: Lottie animations only
echo Optimizations: Multi-threading, SIMD, Partial rendering
echo ========================================
echo.

REM Check for required build tools
where meson >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Meson not found in PATH
    echo.
    echo Installing and adding to PATH...
    python -m pip install --user meson ninja
    
    REM Add Python Scripts to PATH for current session
    set "PATH=%PATH%;%APPDATA%\Python\Python313\Scripts"
    
    echo.
    echo Meson installed. If build still fails, restart your terminal.
    echo.
)

echo Build tools verified: Meson available
echo.

REM Navigate to ThorVG directory
cd thirdparty\thorvg

REM Clean previous build
if exist builddir (
    echo Cleaning previous build directory...
    rmdir /s /q builddir
)

REM Detect CPU core count for parallel compilation
for /f "tokens=2 delims==" %%i in ('wmic cpu get NumberOfLogicalProcessors /value ^| find "="') do set CORES=%%i

REM Configure build with optimal settings for Lottie rendering
echo Configuring ThorVG build with optimizations...
meson setup builddir ^
  -Dbuildtype=release ^
  -Doptimization=3 ^
  -Db_ndebug=true ^
  -Dsimd=true ^
  -Dthreads=true ^
  -Dpartial=true ^
  -Dengines=sw ^
  -Dloaders=lottie ^
  -Dbindings=capi ^
  -Dexamples=false ^
  -Dcpp_args="-DTHORVG_THREAD_SUPPORT" ^
  --backend=ninja ^
  --wipe

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to configure build
    pause
    exit /b 1
)

REM Build with all available CPU cores
echo Building ThorVG using %CORES% parallel jobs...
meson compile -C builddir -j %CORES%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: ThorVG build failed
    echo Check the output above for error details
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo ThorVG build completed successfully
echo.
echo Output location: thirdparty\thorvg\builddir\src\
echo Library file: thorvg-1.dll (shared library)
echo.
echo Enabled optimizations:
echo   - Multi-threading: Task scheduler with %CORES% workers
echo   - SIMD instructions: CPU vectorization enabled
echo   - Partial rendering: Smart update optimizations
echo   - Lottie loader: JSON animation support only
echo   - Release mode: Maximum compiler optimizations
echo ========================================

echo.
echo Build script completed. Ready to build Godot extension.
pause
