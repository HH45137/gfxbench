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

REM ---------- Print build parameters ----------
echo.
echo --------------- BUILD PARAMETERS ---------------
echo product id       : %PRODUCT_ID%
echo product name     : %PRODUCT_NAME%
echo product version  : %PRODUCT_VERSION%
echo workspace        : %WORKSPACE%
echo platform         : %PLATFORM%
echo platform type    : %PLATFORM_TYPE%
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

REM ---------- 获取 vcpkg 根目录 ----------
if "%VCPKG_ROOT%"=="" (
    echo WARNING: VCPKG_ROOT not set, vcpkg toolchain will not be used.
    set "VCPKG_TOOLCHAIN="
) else (
    REM 将反斜杠转为正斜杠以保证 CMake 兼容
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

REM ---------- 追加 vcpkg 工具链 (若可用) ----------
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

REM ---------- 指定工程主目录 ----------
REM 与 Linux build.sh 保持一致：frameworks/testfw 是主程序工程，
REM 它通过 BENCHMARK_DIR 引入 gfxbench 测试模块并生成 testfw_app.exe。
REM （注意：不单独构建 gfxbench，否则会重复编译且不产出 exe）
set "PROJECTS=frameworks/testfw"

REM ---------- Set per-project CMake options ----------
REM testfw 主程序通过 BENCHMARK_DIR 指向 gfxbench 测试模块目录
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
    
    REM 从完整路径取最后一段作为项目名 (gfxbench / testfw)
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

if exist "%WORKSPACE%\build\%proj_name%" (
    echo Clearing legacy CMake cache directory...
    rmdir /s /q "%WORKSPACE%\build\%proj_name%"
)

set "FIXED_WORKSPACE=%WORKSPACE:\=/%"

REM ──── 🌟 全局锁自动生成带防重复加载守卫的 Findngrtl.cmake 桥接器 🌟 ────
echo Generating solid dependency bridge for ngrtl framework...
set "BRIDGE_NGRTL=%WORKSPACE%\frameworks\cmake-utils\cmake\Findngrtl.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_NGRTL%"
echo get_property(NGRTL_LOADED GLOBAL PROPERTY NGRTL_BRIDGE_LOADED) >> "%BRIDGE_NGRTL%"
echo if(NOT NGRTL_LOADED) >> "%BRIDGE_NGRTL%"
echo   set_property(GLOBAL PROPERTY NGRTL_BRIDGE_LOADED TRUE) >> "%BRIDGE_NGRTL%"
echo   message(STATUS "Bridge: First injection of in-tree frameworks/ngrtl into build graph") >> "%BRIDGE_NGRTL%"
echo   add_subdirectory("%FIXED_WORKSPACE%/frameworks/ngrtl" "${CMAKE_BINARY_DIR}/frameworks/ngrtl" EXCLUDE_FROM_ALL) >> "%BRIDGE_NGRTL%"
echo endif() >> "%BRIDGE_NGRTL%"
echo set(NGRTL_INCLUDE_DIRS "%FIXED_WORKSPACE%/frameworks/ngrtl/include/core" CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(NGRTL_INCLUDE_DIR "%FIXED_WORKSPACE%/frameworks/ngrtl/include/core" CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(NGRTL_LIBRARIES ngrtl_core CACHE INTERNAL "") >> "%BRIDGE_NGRTL%"
echo set(ngrtl_FOUND TRUE) >> "%BRIDGE_NGRTL%"
REM ngrtl 以静态库构建（BUILD_SHARED_LIBS=0）。未定义 NGRTL_STATIC 时
REM ngrtl_core_export.h 会把符号标成 __declspec(dllimport)（__imp_*），而静态库
REM 中没有这些导入符号，导致链接期 LNK2019。此处对引用 ngrtl 的编译单元统一定义。
echo add_definitions(-DNGRTL_STATIC) >> "%BRIDGE_NGRTL%"

REM ──── 🌟 自动生成 FindOGLX.cmake 桥接器对齐 frameworks/oglx 🌟 ────
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

REM ──── 🌟 动态接管并干掉会报错的 FindZLIB 脚本 🌟 ────
echo Generating strict interceptor bridge for ZLIB dependency...
set "BRIDGE_ZLIB=%WORKSPACE%\frameworks\cmake-utils\cmake\_FindZLIB.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_ZLIB%"
echo message(STATUS "Bridge: Intercepting FindZLIB to prevent -64-mt mismatch error") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_LIBRARIES "%FIXED_WORKSPACE%/build/zlib/Release/zlib-1.2.8-static.lib" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_LIBRARY "%FIXED_WORKSPACE%/build/zlib/Release/zlib-1.2.8-static.lib" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_INCLUDE_DIRS "%FIXED_WORKSPACE%/3rdparty/zlib;%FIXED_WORKSPACE%/build/zlib" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_INCLUDE_DIR "%FIXED_WORKSPACE%/3rdparty/zlib;%FIXED_WORKSPACE%/build/zlib" CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"
echo set(ZLIB_FOUND TRUE CACHE INTERNAL "") >> "%BRIDGE_ZLIB%"

REM ──── 🌟 生成 FindPoco.cmake 桥接器（把 vcpkg 的 Poco:: targets 映射回 POCO_* 变量）🌟 ────
echo Generating dependency bridge for POCO framework...
set "BRIDGE_POCO=%WORKSPACE%\frameworks\cmake-utils\cmake\FindPoco.cmake"

echo # Generated by build_windows.bat > "%BRIDGE_POCO%"
echo if(Poco_FOUND) >> "%BRIDGE_POCO%"
echo   return() >> "%BRIDGE_POCO%"
echo endif() >> "%BRIDGE_POCO%"
echo find_package(Poco CONFIG QUIET COMPONENTS ${Poco_FIND_COMPONENTS}) >> "%BRIDGE_POCO%"
echo if(NOT Poco_FOUND) >> "%BRIDGE_POCO%"
echo   set(POCO_FOUND FALSE) >> "%BRIDGE_POCO%"
echo   return() >> "%BRIDGE_POCO%"
echo endif() >> "%BRIDGE_POCO%"
echo set(POCO_FOUND TRUE) >> "%BRIDGE_POCO%"
echo set(POCO_LIBRARIES "") >> "%BRIDGE_POCO%"
echo foreach(_poco_comp ${Poco_FIND_COMPONENTS}) >> "%BRIDGE_POCO%"
echo   if(TARGET Poco::${_poco_comp}) >> "%BRIDGE_POCO%"
echo     list(APPEND POCO_LIBRARIES Poco::${_poco_comp}) >> "%BRIDGE_POCO%"
echo     set(POCO_${_poco_comp}_FOUND TRUE) >> "%BRIDGE_POCO%"
echo   endif() >> "%BRIDGE_POCO%"
echo endforeach() >> "%BRIDGE_POCO%"
echo if(TARGET Poco::Foundation) >> "%BRIDGE_POCO%"
echo   get_target_property(POCO_INCLUDE_DIRS Poco::Foundation INTERFACE_INCLUDE_DIRECTORIES) >> "%BRIDGE_POCO%"
echo endif() >> "%BRIDGE_POCO%"

REM 检测本地真实的 libpng 静态库名称；若本地未构建则回退到 vcpkg 提供的 libpng
set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng/Release/libpng16_static.lib"
set "PNG_INC_PATH=%FIXED_WORKSPACE%/3rdparty/libpng;%FIXED_WORKSPACE%/build/libpng"
if not exist "%WORKSPACE%\build\libpng\Release\libpng16_static.lib" (
    if exist "%WORKSPACE%\build\libpng\Release\png.lib" set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng/Release/png.lib"
    if exist "%WORKSPACE%\build\libpng\Release\libpng.lib" set "PNG_LIB_PATH=%FIXED_WORKSPACE%/build/libpng/Release/libpng.lib"
    REM 本地没有构建 libpng：回退到 vcpkg（提供 pnglibconf.h）
    if not "%VCPKG_ROOT_FIXED%"=="" (
        if exist "%VCPKG_ROOT%\installed\x64-windows\include\pnglibconf.h" (
            set "PNG_LIB_PATH=%VCPKG_ROOT_FIXED%/installed/x64-windows/lib/libpng16.lib"
            set "PNG_INC_PATH=%VCPKG_ROOT_FIXED%/installed/x64-windows/include"
        )
    )
)

REM 检测本地是否有编译完的 GLEW 第三方静态库
set "GLEW_LIB_PATH=%FIXED_WORKSPACE%/build/glew/lib/Release/glew32s.lib"

if not exist "%WORKSPACE%\build\glew\lib\Release\glew32s.lib" (
    REM 本地没有构建 GLEW：优先回退到 vcpkg 提供的 glew32.lib，否则退回 opengl32.lib
    set "GLEW_LIB_PATH=opengl32.lib"
    if not "%VCPKG_ROOT_FIXED%"=="" (
        if exist "%VCPKG_ROOT%\installed\x64-windows\lib\glew32.lib" (
            set "GLEW_LIB_PATH=%VCPKG_ROOT_FIXED%/installed/x64-windows/lib/glew32.lib"
        )
    )
)

REM 执行 CMake 配置 (新注入 -D 宏进行强制别名映射，如果 CMakeLists.txt 内部使用的是变量路径，可直接完成运行时覆写)
cmake -S "%FIXED_WORKSPACE%/%proj_path%" -G "%GEN%" -A x64 -DCMAKE_CONFIGURATION_TYPES=%CONFIG% ^
-DCMAKE_MODULE_PATH="%FIXED_WORKSPACE%/frameworks/cmake-utils/cmake;%FIXED_WORKSPACE%/frameworks/ngrtl;%FIXED_WORKSPACE%/frameworks/ngrtl/libs/core;%FIXED_WORKSPACE%/frameworks/oglx" ^
-DCMAKE_PREFIX_PATH="%FIXED_WORKSPACE%/build/libpng;%FIXED_WORKSPACE%/3rdparty/libpng;%FIXED_WORKSPACE%/build/zlib;%FIXED_WORKSPACE%/3rdparty/zlib;%FIXED_WORKSPACE%/build/libepoxy;%FIXED_WORKSPACE%/3rdparty/libepoxy;%FIXED_WORKSPACE%/build/poco;%FIXED_WORKSPACE%/3rdparty/poco;%FIXED_WORKSPACE%/frameworks/ngrtl;%FIXED_WORKSPACE%/frameworks/oglx" ^
-DGFX_TEST_10_DIR="%FIXED_WORKSPACE%/%proj_path%/src/tests/10" ^
-DGLEW_LIBRARIES="%GLEW_LIB_PATH%" ^
-DGLEW_LIBRARY="%GLEW_LIB_PATH%" ^
-DGLEW_INCLUDE_DIRS="%FIXED_WORKSPACE%/3rdparty/glew/include" ^
-DGLEW_INCLUDE_DIR="%FIXED_WORKSPACE%/3rdparty/glew/include" ^
-DGLEW_FOUND=TRUE ^
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
