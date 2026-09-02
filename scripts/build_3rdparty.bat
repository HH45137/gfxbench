@echo off
setlocal enabledelayedexpansion


REM ============================================
REM   Windows (Visual Studio) 3rdParty Build Script
REM ============================================

REM ---------- Default parameters ----------
if "%WORKSPACE%"=="" set "WORKSPACE=%CD%"

REM Must be set before running or passed as argument
if not "%1"=="" set "PLATFORM=%1"
if "%PLATFORM%"=="" (
    echo ERROR: PLATFORM not set. Usage: build_3rdparty.bat [platform]
    exit /b 1
)

REM ---------- Detect architecture from PLATFORM ----------
set "ARCH=x64"
echo %PLATFORM% | findstr /I "arm64" >nul
if %errorlevel% equ 0 set "ARCH=arm64"
REM ---------------------------------------------------------

if "%CONFIG%"=="" set "CONFIG=Release"
if "%ENABLE_CLANG%"=="" set "ENABLE_CLANG=false"
if "%USE_WAYLAND%"=="" set "USE_WAYLAND=false"
if "%MP_COMPILE%"=="" set "MP_COMPILE=true"

REM ---------- Load product description via Parse ----------
set "PRODUCT_FILE="
if exist "%WORKSPACE%\.repo\manifests\product" set "PRODUCT_FILE=%WORKSPACE%\.repo\manifests\product"
if exist "%WORKSPACE%\product" set "PRODUCT_FILE=%WORKSPACE%\product"

if not "%PRODUCT_FILE%"=="" (
    for /f "usebackq delims=" %%a in ("%PRODUCT_FILE%") do (
        set "line=%%a"
        if not "!line:~0,1!"=="#" (
            for /f "tokens=1* delims==" %%i in ("%%a") do (
                set "key=%%i"
                set "val=%%j"
                set "key=!key:export =!"
                set "key=!key: =!"
                if not "!key!"=="" set "!key!=!val!"
            )
        )
    )
) else (
    echo Warning: No product description was found in workspace or manifest repo.
)

REM Check mandatory product variables after loading
if "%PRODUCT_ID%"=="" set "PRODUCT_ID=gfxbench_gl"

REM ---------- Define base 3rdparty projects ----------
if "%COMMUNITY_BUILD%"=="true" (
    set "PROJECTS=3rdparty/openssl-cmake"
) else (
    set "PROJECTS="
)

if not "%PLATFORM%"=="qnx-armv7" if not "%PLATFORM%"=="qnx-aarch64" if not "%PLATFORM%"=="qnx-x86_64" (
    set "PROJECTS=%PROJECTS% 3rdparty/libepoxy"
)

set "PROJECTS=%PROJECTS% 3rdparty/zlib 3rdparty/libpng 3rdparty/poco 3rdparty/AgilitySDK"

echo %PRODUCT_ID% | findstr /I "_dx" >nul
if errorlevel 1 (
    set "PROJECTS=%PROJECTS% 3rdparty/AgilitySDK"
)

REM ---------- Project Specific Options ----------
set "zlib_OPTS=-DBUILD_SHARED_LIBS=0"
set "libpng_OPTS=-DPNG_STATIC=1 -DPNG_SHARED=0"
set "poco_OPTS=-DPOCO_STATIC=1 -DDISABLE_MONGODB=1 -DDISABLE_PDF=1 -DDISABLE_DATA=1 -DDISABLE_ZIP=1"
set "glfw_OPTS=-DGLFW_BUILD_EXAMPLES=0 -DGLFW_BUILD_TESTS=0"

if "%USE_WAYLAND%"=="true" (
    set "glfw_OPTS=%glfw_OPTS% -DGLFW_USE_WAYLAND=1 -DGLFW_CLIENT_LIBRARY=glesv2"
)

REM ---------- Call environment script ----------
if exist "%WORKSPACE%\frameworks\cmake-utils\scripts\env.bat" (
    call "%WORKSPACE%\frameworks\cmake-utils\scripts\env.bat" %PLATFORM%
)

REM ---------- Parallel compile configuration ----------
set "MSBUILD_OPTS="
if "%MP_COMPILE%"=="true" (
    echo Enable parallel build for MSVC MSBuild
    set "CFLAGS=%CFLAGS% -MP"
    set "CXXFLAGS=%CXXFLAGS% -MP"
)

REM ---------- Platform validation & conditional projects ----------
echo %PLATFORM% | findstr /R "^vs2019-.* ^vs2022-.* ^vs2019 ^vs2022" >nul
if %errorlevel% equ 0 (
    echo %PRODUCT_ID% | findstr /I "_dx" >nul
    if errorlevel 1 (
        if exist "3rdparty\glew" if exist "3rdparty\glfw" (
            set "PROJECTS=!PROJECTS! 3rdparty\glew 3rdparty\glfw"
            set "PROJECTS=!PROJECTS! frameworks\ngl\src\v1.0.3\loader"
        )
    )
)

REM ---------- Initialize Common CMake Options ----------
if not "%CMAKE_MAKE_PROGRAM%"=="" (
    set "COMMON_OPTS=%COMMON_OPTS% -DCMAKE_MAKE_PROGRAM=%CMAKE_MAKE_PROGRAM%"
)

REM ---------- Main Build Loop ----------
set "ALL_PROJECTS=%EXTRA_PROJECTS% %PROJECTS%"

for %%p in (%ALL_PROJECTS%) do (
    set "proj_path=%%p"
    for %%i in ("%%p") do set "NAME=%%~nxi"
    set "NAME_UNDERSCORE=!NAME:-=_!"
    
    call :get_dynamic_var !NAME_UNDERSCORE!_OPTS proj_opts
    call :get_dynamic_var !NAME_UNDERSCORE!_TARGET proj_target
    
    call :print_header !NAME!
    
    set "SKIP=false"
    if not "%SKIP_PROJECT%"=="" (
        echo %SKIP_PROJECT% | findstr /I "!NAME!" >nul
        if %errorlevel% equ 0 set "SKIP=true"
    )
    
    if "!SKIP!"=="true" (
        echo SKIPPING...
    ) else (
        echo Configuring CMake for !NAME!...
        
        REM ---- Determine generator and architecture ----
        set "GEN_ARG="
        echo %PLATFORM% | findstr /I "vs2022" >nul && set "GEN_ARG=-G "Visual Studio 17 2022" -A %ARCH%"
        echo %PLATFORM% | findstr /I "vs2019" >nul && set "GEN_ARG=-G "Visual Studio 16 2019" -A %ARCH%"
        if "!GEN_ARG!"=="" set "GEN_ARG=-G "Visual Studio 17 2022" -A %ARCH%"
        REM ----------------------------------------------

        REM ---- Auto-detect MSVC toolset that has an ARM64 compiler ----
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

        REM ---- Set build directory with architecture suffix ----
        set "BUILD_DIR=%WORKSPACE%\build\!NAME!-%ARCH%"
        REM ------------------------------------------------------

        REM ---- Locate ZLIB library according to current architecture ----
        set "ZLIB_ADDITIONAL_OPTS="
        if exist "%WORKSPACE%\build\zlib-%ARCH%\Release\zlib-1.2.8-static.lib" (
            set "ZLIB_ADDITIONAL_OPTS=-DZLIB_LIBRARY="%WORKSPACE%\build\zlib-%ARCH%\Release\zlib-1.2.8-static.lib" -DZLIB_INCLUDE_DIR="%WORKSPACE%\3rdparty\zlib;%WORKSPACE%\build\zlib-%ARCH%""
        ) else if exist "%WORKSPACE%\build\zlib-%ARCH%\Release\zlibstatic.lib" (
            set "ZLIB_ADDITIONAL_OPTS=-DZLIB_LIBRARY="%WORKSPACE%\build\zlib-%ARCH%\Release\zlibstatic.lib" -DZLIB_INCLUDE_DIR="%WORKSPACE%\3rdparty\zlib;%WORKSPACE%\build\zlib-%ARCH%""
        )
        REM -----------------------------------------------------------------

        cmake -S "%WORKSPACE%\!proj_path!" !GEN_ARG! !TOOLSET_ARG! -DCMAKE_CONFIGURATION_TYPES=%CONFIG% ^
              -DCMAKE_POLICY_VERSION_MINIMUM="3.5" ^
              %COMMON_OPTS% !proj_opts! !ZLIB_ADDITIONAL_OPTS! -DPRODUCT_NAME=%PRODUCT_NAME% ^
              -B "!BUILD_DIR!"
        
        if errorlevel 1 (
            echo ERROR: CMake configuration failed for !NAME!
            exit /b 1
        )
        
        echo Building !NAME!...
        cmake --build "!BUILD_DIR!" --config %CONFIG% !proj_target! %MSBUILD_OPTS% --parallel 30
        
        if errorlevel 1 (
            echo ERROR: Build failed for !NAME!
            exit /b 1
        )
    )
)

echo.
echo All 3rdparty dependencies processed successfully.
exit /b 0

REM ---------- Helper Subroutines ----------
:print_header
echo.
echo.
echo ######################################################
echo # PROJECT:  %~1
echo # PLATFORM: %PLATFORM%
echo # CONFIG:   %CONFIG%
echo # ARCH:     %ARCH%
echo ######################################################
exit /b

:get_dynamic_var
set "var_name=%~1"
set "result_var=%~2"
set "%result_var%=!%var_name%!"
exit /b
