# FindGLEW.cmake
#
# On developer machines, build_windows.bat generates a per-machine bridge in
# _FindGLEW.cmake (an alias file listed in .gitignore) that hard-codes the local
# 3rdparty GLEW build. If that bridge exists, use it first. Otherwise fall back
# to the standard search below.

if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/_FindGLEW.cmake")
    include("${CMAKE_CURRENT_LIST_DIR}/_FindGLEW.cmake")
    if(GLEW_FOUND)
        return()
    endif()
endif()

include(TryFindPackageCfg)
try_find_package_cfg()

if(GLEW_FOUND)
        return()
endif()

include(IncludeStandardFindModule)
include_standard_find_module()
