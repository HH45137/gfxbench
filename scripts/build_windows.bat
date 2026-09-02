@echo off
setlocal enabledelayedexpansion

REM ============================================
REM   Windows (Visual Studio) Build Script
REM ============================================

REM ---------- Default parameters ----------
if "%WORKSPACE%"=="" set "WORKSPACE=%CD%"
set "PRODUCT_ID=gfxbench_gl"
set "PRODUCT_NAME=%PRODUCT_ID%"
set "PRODUCT_VERSION=5.0.0"
set "CONFIG=Release"
set "APPLICATION_TYPE=developer"
set "BUNDLE_DATA=true"
set "EDITOR=false"
set "TEST="
set "RENDER_API="
set "MP_COMPILE=false"
set "KEEP_TFW_PACKAGE=false"
set "BUILD_NUMBER=0"
set "ARCHIVE_ROOT="
set "BENCHMARK_GUI=false"
set "SIGNIFICANT_FRAME_MODE=false"
set "STORE_VERSION=false"
set "COMMUNITY_BUILD=false"
set "DISABLE_GFX4=false"
set "FIXUP_BUNDLE=true"
set "VK_NULL=false"
set "OGLX_VARIANT=default"
set "OGLX_DRIVER="
set "DISPLAY_PROTOCOL=WIN32"
set "ENABLE_CLANG=false"

REM ---------- Override variables via command line or environment ----------
if not "%1"=="" set "PLATFORM=%1"
if "%PLATFORM%"=="" set "PLATFORM=vs2019-x64"

REM ---------- Check mandatory variables ----------
if "%PRODUCT_ID%"=="" (
    echo ERROR: PRODUCT_ID not set
    exit /b 1
)
if "%PRODUCT_VERSION%"=="" (
    echo ERROR: PRODUCT_VERSION not set
    exit /b 1
)
if "%CONFIG%"=="" (
    echo ERROR: CONFIG not set
    exit /b 1
)

REM ---------- Platform-specific settings (Windows VS only) ----------
if "%PLATFORM:~0,6%"=="vs2019" (
    set "PLATFORM_TYPE=vs2019"
) else if "%PLATFORM:~0,6%"=="vs2022" (
    set "PLATFORM_TYPE=vs2022"
) else (
    echo Unsupported platform: %PLATFORM%
    exit /b 1
)

REM ---------- Detect architecture from PLATFORM ----------
set "ARCH=x64"
echo %PLATFORM% | findstr /I "arm64" >nul
if %errorlevel% equ 0 set "ARCH=arm64"
REM ---------------------------------------------------------

REM ---------- Map ARCH to vcpkg triplet ----------
set "VCPKG_TRIPLET=x64-windows"
if "%ARCH%"=="arm64" set "VCPKG_TRIPLET=arm64-windows"
REM -------------------------------------------------

REM ---------- Print build parameters ----------
echo.
echo --------------- BUILD PARAMETERS ---------------
echo product id       : %PRODUCT_ID%
echo product name     : %PRODUCT_NAME%
echo product version  : %PRODUCT_VERSION%
echo workspace        : %WORKSPACE%
echo platform         : %PLATFORM%
echo platform type    : %PLATFORM_TYPE%
echo architecture     : %ARCH%
echo application type : %APPLICATION_TYPE%
echo configuration    : %CONFIG%
echo bundle data      : %BUNDLE_DATA%
echo multiprocess     : %MP_COMPILE%
echo keep tfw package : %KEEP_TFW_PACKAGE%
echo -------------------------------------------------
echo.

REM ---------- Set TFW package directory ----------
set "TFW_PACKAGE_DIR=%WORKSPACE%\tfw-pkg"

if not "%KEEP_TFW_PACKAGE%"=="true" (
    if exist "%TFW_PACKAGE_DIR%" (
        rmdir /s /q "%TFW_PACKAGE_DIR%"
    )
)
mkdir "%TFW_PACKAGE_DIR%" 2>nul

REM ---------- Enable parallel compilation for MSVC ----------
if "%MP_COMPILE%"=="true" (
    set "CFLAGS=%CFLAGS% -MP"
    set "CXXFLAGS=%CXXFLAGS% -MP"
)

REM ---------- Get vcpkg root ----------
if "%VCPKG_ROOT%"=="" (
    echo WARNING: VCPKG_ROOT not set, vcpkg toolchain will not be used.
    set "VCPKG_TOOLCHAIN="
) else (
    REM Convert backslashes to forward slashes for CMake compatibility
    set "VCPKG_ROOT_FIXED=%VCPKG_ROOT:\=/%"
    set "VCPKG_TOOLCHAIN=!VCPKG_ROOT_FIXED!/scripts/buildsystems/vcpkg.cmake"
    echo Using vcpkg toolchain: !VCPKG_TOOLCHAIN!
)

REM ---------- Build common CMake options ----------
set "COMMON_OPTS="
set COMMON_OPTS=%COMMON_OPTS% -DOPT_FIXUP_BUNDLE=%FIXUP_BUNDLE%
set COMMON_OPTS=%COMMON_OPTS% -DSIGNIFICANT_FRAME_MODE=%SIGNIFICANT_FRAME_MODE%
set COMMON_OPTS=%COMMON_OPTS% -DPRODUCT_ID=%PRODUCT_ID%
set COMMON_OPTS=%COMMON_OPTS% -DPRODUCT_VERSION=%PRODUCT_VERSION%
set COMMON_OPTS=%COMMON_OPTS% -DAPPLICATION_TYPE=%APPLICATION_TYPE%
set COMMON_OPTS=%COMMON_OPTS% -DBUNDLE_DATA=%BUNDLE_DATA%
set COMMON_OPTS=%COMMON_OPTS% -DSTORE_VERSION=%STORE_VERSION%
set COMMON_OPTS=%COMMON_OPTS% -DBUILD_NUMBER=%BUILD_NUMBER%
set COMMON_OPTS=%COMMON_OPTS% -DTFW_PACKAGE_DIR=%TFW_PACKAGE_DIR%
set COMMON_OPTS=%COMMON_OPTS% -DPLATFORM=%PLATFORM%
set COMMON_OPTS=%COMMON_OPTS% -DBENCHMARK_GUI=%BENCHMARK_GUI%
set COMMON_OPTS=%COMMON_OPTS% -DOPT_COMMUNITY_BUILD=%COMMUNITY_BUILD%
set COMMON_OPTS=%COMMON_OPTS% -DCMAKE_SYSTEM_VERSION=10.0
set COMMON_OPTS=%COMMON_OPTS% -DDISPLAY_PROTOCOL=%DISPLAY_PROTOCOL%
set COMMON_OPTS=%COMMON_OPTS% -DCMAKE_POLICY_VERSION_MINIMUM="3.5"

REM ---------- Append vcpkg toolchain (if available) ----------
if not "%VCPKG_TOOLCHAIN%"=="" (
    set COMMON_OPTS=%COMMON_OPTS% -DCMAKE_TOOLCHAIN_FILE="!VCPKG_TOOLCHAIN!"
)

REM Set default render API based on PRODUCT_ID
if "%RENDER_API%"=="" (
    if "%PRODUCT_ID%"=="gfxbench_dx" (
        set "RENDER_API=D3D11;D3D12"
    ) else if "%PRODUCT_ID%"=="gfxbench_vulkan" (
        set "RENDER_API=VULKAN;GL"
    ) else (
        set "RENDER_API=ES31;GL"
    )
)
set COMMON_OPTS=%COMMON_OPTS% -DRENDER_API=%RENDER_API%
set COMMON_OPTS=%COMMON_OPTS% -DVK_NULL=%VK_NULL%

if "%EDITOR%"=="true" (
    set COMMON_OPTS=%COMMON_OPTS% -DEDITOR=TRUE
) else (
    set COMMON_OPTS=%COMMON_OPTS% -DEDITOR=FALSE
)

REM ---------- Specify the main project directory ----------
REM Consistent with the Linux build.sh: frameworks/testfw is the main program project,
REM which pulls in the gfxbench test modules through BENCHMARK_DIR and builds testfw_app.exe.
REM (Note: do not build gfxbench separately, it would duplicate work and not produce an exe)
set "PROJECTS=frameworks/testfw"

REM ---------- Set per-project CMake options ----------
REM testfw main program points BENCHMARK_DIR at the gfxbench test module directory
set "BENCHMARK_DIR=%WORKSPACE:\=/%/gfxbench"
set "testfw_OPTS=-DBENCHMARK_DIR=%BENCHMARK_DIR% -DSILENCE_PLUGIN_LOAD_WARNINGS=1 -DBUILD_SHARED_LIBS=0"

REM ---------- Default build target ----------
REM NOTE: "install"/"package" must NOT be prefixed with "-t" because
REM "-t" is itself the short form of "--target". The cmake --build call
REM below already passes "--target %proj_target%", so only the bare
REM target name should be stored here.
if not "%ARCHIVE_ROOT%"=="" (
    set "DEFAULT_TARGET=package"
) else (
    set "DEFAULT_TARGET=install"
)

REM ---------- Loop over projects and build each ----------
for %%p in (%PROJECTS%) do (
    set "proj_full=%%p"
    
    REM Take the last path segment as the project name (gfxbench / testfw)
    for %%f in ("%%p") do set "proj_name=%%~nxf"
    set "proj_name_underscore=!proj_name:-=_!"
    
    call :get_opts !proj_name_underscore!_OPTS
    call :get_target !proj_name_underscore!_TARGET
    
    call :build_project !proj_name! !proj_full! "!opts!" "!target!" !PLATFORM_TYPE!
    if errorlevel 1 exit /b !errorlevel!
)

echo.
echo Build finished successfully.
exit /b 0

REM ---------- Helper subroutines to fetch option and target variable values ----------
:get_opts
set opts=!%1!
if "%opts%"=="" set "opts="
exit /b

:get_target
set target=!%1!
if "%target%"=="" set "target=%DEFAULT_TARGET%"
exit /b

REM ---------- Helper function to build a single project ----------
:build_project
setlocal
set "proj_name=%~1"
set "proj_path=%~2"
set "proj_opts=%~3"
set "proj_target=%~4"
set "current_platform_type=%~5"

echo.
echo ######################################################
echo # PROJECT:  %proj_name%
echo # PLATFORM: %PLATFORM%
echo # CONFIG:   %CONFIG%
echo # OPTIONS:  %proj_opts% %COMMON_OPTS% -DPRODUCT_NAME=%PRODUCT_NAME%
echo # TARGET :  %proj_target%
echo ######################################################
echo.

if "%current_platform_type%"=="vs2019" (
    set "GEN=Visual Studio 16 2019"
) else if "%current_platform_type%"=="vs2022" (
    set "GEN=Visual Studio 17 2022"
) else (
    echo ERROR: Unknown platform type "%current_platform_type%"
    exit /b 1
)

REM ---- Auto-detect MSVC toolset that has an ARM64 compiler ----
REM On some machines the first/default toolset (e.g. 14.38) has no
REM Hostx64\arm64\cl.exe, which makes CMake fail compiler detection
REM with LNK1112 (x64 object linked for an ARM64 target).
set "TOOLSET_ARG="
if /I "%ARCH%"=="arm64" (
    set "FOUND_ARM64_TOOLSET="
    for /d %%e in ("%ProgramFiles%\Microsoft Visual Studio\2022\*" "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\*") do (
        if exist "%%e\VC\Tools\MSVC\*" (
            for /d %%t in ("%%e\VC\Tools\MSVC\*") do (
                if exist "%%t\bin\Hostx64\arm64\cl.exe" (
                    set "FOUND_ARM64_TOOLSET=%%t"
                )
            )
        )
    )
    if not "!FOUND_ARM64_TOOLSET!"=="" (
        for %%f in ("!FOUND_ARM64_TOOLSET!") do set "TOOLSET_ARG=-T v143,version=%%~nxf"
        echo Using MSVC toolset with ARM64 compiler: !TOOLSET_ARG!
    ) else (
        echo WARNING: No MSVC toolset with an ARM64 compiler found.
    )
)
REM ---------------------------------------------------------

if exist "%WORKSPACE%\build\%proj_name%" (
    echo Clearing legacy CMake cache directory...
    rmdir /s /q "%WORKSPACE%\build\%proj_name%"
)

set "FIXED_WORKSPACE=%WORKSPACE:\=/%"

REM ---- Generate Findngrtl.cmake bridge with a duplicate-load guard ----
echo Generating solid dependency bridge for ngrtl framework...
set "BRIDGE_NGRTL=%WORKSPACE%\frameworks\cmake-utils\cmake\Findngrtl.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_NGRTL%"
echo get_property(NGRTL_LOADED GLOBAL PROPERTY NGRTL_BRIDGE_LOADED) >> "%BRIDGE_NGRTL%"
echo if(NOT NGRTL_LOADED) >> "%BRIDGE_NGRTL%"
echo   set_property(GLOBAL PROPERTY NGRTL_BRIDGE_LOADED TRUE) >> "%BRIDGE_NGRTL%"
echo   message(STATUS "Bridge: First injection of in-tree frameworks/ngrtl into build graph") >> "%BRIDGE_NGRTL%"
echo   add_subdirectory("%FIXED_WORKSPACE%/frameworks/ngrtl" "${CMAKE_BINARY_DIR}/frameworks/ngrtl" EXCLUDE_FROM_ALL) >> "%BRIDGE_NGRTL%"
echo endif() >> "%BRIDGE_NGRTL%"
echo set(NGRTL_INCLUDE_DIRS "%FIXED_WORKSPACE%/frameworks/ngrtl/include/core;%FIXED_WORKSPACE%/frameworks/ngrtl/include/pngio" CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(NGRTL_INCLUDE_DIR "%FIXED_WORKSPACE%/frameworks/ngrtl/include/core;%FIXED_WORKSPACE%/frameworks/ngrtl/include/pngio" CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(NGRTL_LIBRARIES ngrtl_core CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(ngrtl_FOUND TRUE) >> "%BRIDGE_NGRTL%"
REM ngrtl is built as a static library (BUILD_SHARED_LIBS=0). Without NGRTL_STATIC,
REM ngrtl_core_export.h marks symbols as __declspec(dllimport) (__imp_*), but the static
REM library has no such import symbols, causing LNK2019 at link time. Define it for ngrtl users.
echo add_definitions(-DNGRTL_STATIC) >> "%BRIDGE_NGRTL%"

REM ---- Generate _FindOGLX.cmake bridge aligned with frameworks/oglx ----
echo Generating solid dependency bridge for OGLX framework...
set "BRIDGE_OGLX=%WORKSPACE%\frameworks\cmake-utils\cmake\_FindOGLX.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_OGLX%"
echo get_property(OGLX_LOADED GLOBAL PROPERTY OGLX_BRIDGE_LOADED) >> "%BRIDGE_OGLX%"
echo if(NOT OGLX_LOADED) >> "%BRIDGE_OGLX%"
echo   set_property(GLOBAL PROPERTY OGLX_BRIDGE_LOADED TRUE) >> "%BRIDGE_OGLX%"
echo   message(STATUS "Bridge: Injecting in-tree frameworks/oglx into build graph") >> "%BRIDGE_OGLX%"
echo   add_subdirectory("%FIXED_WORKSPACE%/frameworks/oglx" "${CMAKE_BINARY_DIR}/frameworks/oglx" EXCLUDE_FROM_ALL) >> "%BRIDGE_OGLX%"
echo endif() >> "%BRIDGE_OGLX%"
echo set(OGLX_INCLUDE_DIRS "%FIXED_WORKSPACE%/frameworks/oglx/dummy" CACHE INTERNAL "") >> "%BRIDGE_OGLX%"
echo set(OGLX_INCLUDE_DIR "%FIXED_WORKSPACE%/frameworks/oglx/dummy" CACHE INTERNAL "") >> "%BRIDGE_OGLX%"
echo set(OGLX_LIBRARIES oglx_dummy CACHE INTERNAL "") >> "%BRIDGE_OGLX%"
echo set(OGLX_FOUND TRUE) >> "%BRIDGE_OGLX%"

REM ---- Generate _FindZLIB.cmake interceptor bridge ----
echo Generating strict interceptor bridge for ZLIB dependency...
set "BRIDGE_ZLIB=%WORKSPACE%\frameworks\cmake-utils\cmake\_FindZLIB.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_ZLIB%"
echo message(STATUS "Bridge: Intercepting FindZLIB to prevent -64-mt mismatch error") >> "%BRIDGE_ZLIB%"
REM Detect local zlib static lib name (build_3rdparty.bat outputs to build\zlib-%ARCH%)
set "ZLIB_LIB_PATH=%FIXED_WORKSPACE%/build/zlib-%ARCH%/Release/zlib-1.2.8-static.lib"
set "ZLIB_INC_PATH=%FIXED_WORKSPACE%/3rdparty/zlib;%FIXED_WORKSPACE%/build/zlib-%ARCH%"
if not exist "%WORKSPACE%\build\zlib-%ARCH%\Release\zlib-1.2.8-static.lib" (
    if exist "%WORKSPACE%\build\zlib-%ARCH%\Release\zlibstatic.lib" (
        set "ZLIB_LIB_PATH=%FIXED_WORKSPACE%/build/zlib-%ARCH%/Release/zlibstatic.lib"
    ) else if not "%VCPKG_ROOT_FIXED%"=="" (
        set "ZLIB_LIB_PATH=%VCPKG_ROOT_FIXED%/installed/%VCPKG_TRIPLET%/lib/zlib.lib"
        set "ZLIB_INC_PATH=%VCPKG_ROOT_FIXED%/installed/%VCPKG_TRIPLET%/include"
    )
)
echo set(ZLIB_LIBRARIES "%ZLIB_LIB_PATH%" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_LIBRARY "%ZLIB_LIB_PATH%" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_INCLUDE_DIRS "%ZLIB_INC_PATH%" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_INCLUDE_DIR "%ZLIB_INC_PATH%" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_FOUND TRUE CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"

REM ---- Generate FindPoco.cmake bridge (direct mapping to in-tree headers and built libs) ----
echo Generating dependency bridge for POCO framework...
set "BRIDGE_POCO=%WORKSPACE%\frameworks\cmake-utils\cmake\FindPoco.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_POCO%"
echo if(POCO_FOUND) >> "%BRIDGE_POCO%"
echo   return() >> "%BRIDGE_POCO%"
echo endif() >> "%BRIDGE_POCO%"
echo set(POCO_FOUND TRUE) >> "%BRIDGE_POCO%"
echo set(POCO_DEFINITIONS -DPOCO_NO_AUTOMATIC_LIBS -DPOCO_STATIC) >> "%BRIDGE_POCO%"
echo set(POCO_INCLUDE_DIRS >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/3rdparty/poco/Foundation/include" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/3rdparty/poco/XML/include" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/3rdparty/poco/JSON/include" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/3rdparty/poco/Util/include" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/3rdparty/poco/Net/include") >> "%BRIDGE_POCO%"
echo set(POCO_LIBRARIES >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/build/poco-%ARCH%/lib/Release/PocoFoundationmd.lib" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/build/poco-%ARCH%/lib/Release/PocoXMLmd.lib" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/build/poco-%ARCH%/lib/Release/PocoJSONmd.lib" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/build/poco-%ARCH%/lib/Release/PocoUtilmd.lib" >> "%BRIDGE_POCO%"
echo   "%FIXED_WORKSPACE%/build/poco-%ARCH%/lib/Release/PocoNetmd.lib" >> "%BRIDGE_POCO%"
echo   iphlpapi.lib ws2_32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib user32.lib gdi32.lib) >> "%BRIDGE_POCO%"

REM Detect real local libpng static library name; fall back to vcpkg libpng if not built locally
set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng-%ARCH%/Release/png-1.6.7-static.lib"
set "PNG_INC_PATH=%FIXED_WORKSPACE%/3rdparty/libpng;%FIXED_WORKSPACE%/build/libpng-%ARCH%"
if not exist "%WORKSPACE%\build\libpng-%ARCH%\Release\png-1.6.7-static.lib" (
    if exist "%WORKSPACE%\build\libpng-%ARCH%\Release\libpng16_static.lib" set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng-%ARCH%/Release/libpng16_static.lib"
    if exist "%WORKSPACE%\build\libpng-%ARCH%\Release\png.lib" set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng-%ARCH%/Release/png.lib"
    if exist "%WORKSPACE%\build\libpng-%ARCH%\Release\libpng.lib" set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng-%ARCH%/Release/libpng.lib"
    REM Local libpng not built: fall back to vcpkg (provides pnglibconf.h)
    if not "%VCPKG_ROOT_FIXED%"=="" (
        if exist "%VCPKG_ROOT%\installed\%VCPKG_TRIPLET%\include\pnglibconf.h" (
            set "PNG_LIB_PATH=%VCPKG_ROOT_FIXED%/installed/%VCPKG_TRIPLET%/lib/libpng16.lib"
            set "PNG_INC_PATH=%VCPKG_ROOT_FIXED%/installed/%VCPKG_TRIPLET%/include"
        )
    )
)

REM Detect whether a local compiled GLEW third-party static library exists
set "GLEW_LIB_PATH=%FIXED_WORKSPACE%/build/glew-%ARCH%/lib/Release/glew32s.lib"

if not exist "%WORKSPACE%\build\glew-%ARCH%\lib\Release\glew32s.lib" (
    REM The 3rdparty/glew CMake build outputs GLEW.lib directly under Release/
    if exist "%WORKSPACE%\build\glew-%ARCH%\Release\GLEW.lib" set "GLEW_LIB_PATH=%FIXED_WORKSPACE%/build/glew-%ARCH%/Release/GLEW.lib"
    if exist "%WORKSPACE%\build\glew-%ARCH%\lib\Release\glew32.lib" set "GLEW_LIB_PATH=%FIXED_WORKSPACE%/build/glew-%ARCH%/lib/Release/glew32.lib"
    if exist "%WORKSPACE%\build\glew-%ARCH%\Release\glew32.lib" set "GLEW_LIB_PATH=%FIXED_WORKSPACE%/build/glew-%ARCH%/Release/glew32.lib"
    if not exist "!GLEW_LIB_PATH!" (
        REM Local GLEW not built: prefer vcpkg glew32.lib, otherwise fall back to opengl32.lib
        set "GLEW_LIB_PATH=opengl32.lib"
        if not "%VCPKG_ROOT_FIXED%"=="" (
            if exist "%VCPKG_ROOT%\installed\%VCPKG_TRIPLET%\lib\glew32.lib" (
                set "GLEW_LIB_PATH=%VCPKG_ROOT_FIXED%/installed/%VCPKG_TRIPLET%/lib/glew32.lib"
            )
        )
    )
)

REM ---- Generate _FindGLEW.cmake bridge (bypasses broken vcpkg GLEW config lookup) ----
REM This file is generated per-machine and is listed in .gitignore (alias file,
REM so the tracked FindGLEW.cmake is never overwritten).
REM FindOGLX.cmake calls find_package(GLEW); the vcpkg toolchain may find the
REM x64 GLEW config and report it, but leave GLEW_LIBRARIES empty, so OGLX falls
REM back to the system GL/gl.h (GL 1.1) and glBindBuffer/GLintptr are undefined.
set "BRIDGE_GLEW=%WORKSPACE%\frameworks\cmake-utils\cmake\_FindGLEW.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_GLEW%"
echo add_definitions(-DGLEW_STATIC) >> "%BRIDGE_GLEW%"
echo if(GLEW_FOUND) >> "%BRIDGE_GLEW%"
echo   return() >> "%BRIDGE_GLEW%"
echo endif() >> "%BRIDGE_GLEW%"
echo set(GLEW_FOUND TRUE) >> "%BRIDGE_GLEW%"
echo set(GLEW_LIBRARIES "%GLEW_LIB_PATH%") >> "%BRIDGE_GLEW%"
echo set(GLEW_LIBRARY "%GLEW_LIB_PATH%") >> "%BRIDGE_GLEW%"
echo set(GLEW_INCLUDE_DIRS "%FIXED_WORKSPACE%/3rdparty/glew/include") >> "%BRIDGE_GLEW%"
echo set(GLEW_INCLUDE_DIR "%FIXED_WORKSPACE%/3rdparty/glew/include") >> "%BRIDGE_GLEW%"
echo add_library(GLEW::GLEW INTERFACE IMPORTED) >> "%BRIDGE_GLEW%"
echo set_target_properties(GLEW::GLEW PROPERTIES >> "%BRIDGE_GLEW%"
echo   INTERFACE_INCLUDE_DIRECTORIES "%FIXED_WORKSPACE%/3rdparty/glew/include" >> "%BRIDGE_GLEW%"
echo   INTERFACE_LINK_LIBRARIES "%GLEW_LIB_PATH%") >> "%BRIDGE_GLEW%"
REM ---------------------------------------------------------

REM ---- Generate _Findepoxy.cmake bridge (maps built epoxy.lib to CMake vars) ----
REM This file is generated per-machine and is listed in .gitignore (alias file,
REM so the tracked Findepoxy.cmake is never overwritten).
REM The in-tree epoxy-config.cmake looks for "libepoxy.a"/"epoxy", but MSVC
REM produces "epoxy.lib", so find_package(epoxy) fails and HAVE_EPOXY is never
REM defined, which makes eglgraphicscontext.h fall back to <EGL/egl.h>.
set "BRIDGE_EPOXY=%WORKSPACE%\frameworks\cmake-utils\cmake\_Findepoxy.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_EPOXY%"
echo add_definitions(-DEPOXY_STATIC=1) >> "%BRIDGE_EPOXY%"
echo if(epoxy_FOUND) >> "%BRIDGE_EPOXY%"
echo   return() >> "%BRIDGE_EPOXY%"
echo endif() >> "%BRIDGE_EPOXY%"
echo set(epoxy_FOUND TRUE) >> "%BRIDGE_EPOXY%"
echo set(EPOXY_FOUND TRUE) >> "%BRIDGE_EPOXY%"
echo set(epoxy_LIBRARIES "%FIXED_WORKSPACE%/build/libepoxy-%ARCH%/Release/epoxy.lib") >> "%BRIDGE_EPOXY%"
echo set(epoxy_LIBRARY "%FIXED_WORKSPACE%/build/libepoxy-%ARCH%/Release/epoxy.lib") >> "%BRIDGE_EPOXY%"
echo set(epoxy_INCLUDE_DIRS "%FIXED_WORKSPACE%/3rdparty/libepoxy/include;%FIXED_WORKSPACE%/3rdparty/libepoxy/khronos/include") >> "%BRIDGE_EPOXY%"
echo set(epoxy_INCLUDE_DIR "%FIXED_WORKSPACE%/3rdparty/libepoxy/include;%FIXED_WORKSPACE%/3rdparty/libepoxy/khronos/include") >> "%BRIDGE_EPOXY%"
echo add_library(epoxy INTERFACE IMPORTED) >> "%BRIDGE_EPOXY%"
echo set_target_properties(epoxy PROPERTIES >> "%BRIDGE_EPOXY%"
echo   INTERFACE_INCLUDE_DIRECTORIES "%FIXED_WORKSPACE%/3rdparty/libepoxy/include;%FIXED_WORKSPACE%/3rdparty/libepoxy/khronos/include" >> "%BRIDGE_EPOXY%"
echo   INTERFACE_LINK_LIBRARIES "%FIXED_WORKSPACE%/build/libepoxy-%ARCH%/Release/epoxy.lib") >> "%BRIDGE_EPOXY%"
REM ---------------------------------------------------------------

REM Run CMake configure (inject -D macros to force alias mapping; if CMakeLists.txt uses variable paths, this overrides them at runtime)
cmake -S "%FIXED_WORKSPACE%/%proj_path%" -G "%GEN%" -A %ARCH% !TOOLSET_ARG! -DCMAKE_CONFIGURATION_TYPES=%CONFIG% ^
-DCMAKE_MODULE_PATH="%FIXED_WORKSPACE%/frameworks/cmake-utils/cmake;%FIXED_WORKSPACE%/frameworks/ngrtl;%FIXED_WORKSPACE%/frameworks/ngrtl/libs/core;%FIXED_WORKSPACE%/frameworks/oglx" ^
-DCMAKE_PREFIX_PATH="%FIXED_WORKSPACE%/build/libpng-%ARCH%;%FIXED_WORKSPACE%/3rdparty/libpng;%FIXED_WORKSPACE%/build/zlib-%ARCH%;%FIXED_WORKSPACE%/3rdparty/zlib;%FIXED_WORKSPACE%/build/libepoxy-%ARCH%;%FIXED_WORKSPACE%/3rdparty/libepoxy;%FIXED_WORKSPACE%/build/poco-%ARCH%;%FIXED_WORKSPACE%/3rdparty/poco;%FIXED_WORKSPACE%/frameworks/ngrtl;%FIXED_WORKSPACE%/frameworks/oglx" ^
-DGFX_TEST_10_DIR="%FIXED_WORKSPACE%/%proj_path%/src/tests/10" ^
-DGLEW_LIBRARIES="%GLEW_LIB_PATH%" ^
-DGLEW_LIBRARY="%GLEW_LIB_PATH%" ^
-DGLEW_INCLUDE_DIRS="%FIXED_WORKSPACE%/3rdparty/glew/include" ^
-DGLEW_INCLUDE_DIR="%FIXED_WORKSPACE%/3rdparty/glew/include" ^
-DGLEW_FOUND=TRUE ^
-DZLIB_LIBRARIES="%ZLIB_LIB_PATH%" ^
-DZLIB_LIBRARY="%ZLIB_LIB_PATH%" ^
-DZLIB_INCLUDE_DIRS="%ZLIB_INC_PATH%" ^
-DZLIB_INCLUDE_DIR="%ZLIB_INC_PATH%" ^
-DPNG_LIBRARIES="%PNG_LIB_PATH%" ^
-DPNG_LIBRARY="%PNG_LIB_PATH%" ^
-DPNG_INCLUDE_DIRS="%PNG_INC_PATH%" ^
-DPNG_INCLUDE_DIR="%PNG_INC_PATH%" ^
%COMMON_OPTS% %proj_opts% -DPRODUCT_NAME=%PRODUCT_NAME% ^
-B "%WORKSPACE%\build\%proj_name%"

if errorlevel 1 exit /b !errorlevel!
cmake --build "%WORKSPACE%\build\%proj_name%" --config %CONFIG%
if errorlevel 1 exit /b !errorlevel!
endlocal
exit /b 0
